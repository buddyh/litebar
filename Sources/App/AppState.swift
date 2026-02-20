import Foundation
import SwiftUI
import UserNotifications
import Darwin

@MainActor
@Observable
final class AppState {
    var databases: [SQLiteDatabase] = []
    var config: AppConfig
    var isLoading = false
    var lastRefresh: Date?

    // Track previous alert states to only notify on transitions
    private var previousAlerts: Set<String> = []

    private let inspector = DatabaseInspector()
    private let healthChecker = HealthChecker()
    private let watchExecutor = WatchExecutor()
    private let backupManager = BackupManager()
    private var refreshTask: Task<Void, Never>?
    private var configWatchSource: DispatchSourceFileSystemObject?
    private var pendingConfigRefresh: Task<Void, Never>?

    var totalWarnings: Int {
        databases.reduce(0) { count, db in
            count + db.watchResults.filter { $0.alertState != .normal }.count + (db.isQuiet ? 1 : 0)
        }
    }

    init(autoStart: Bool = true, requestNotifications: Bool = true) {
        self.config = AppConfig.load()
        if requestNotifications {
            requestNotificationPermission()
        }
        if autoStart {
            startAutoRefresh()
            startConfigWatch()
        }
    }

    // MARK: - Full refresh cycle

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        // Reload config (might have been edited by agent)
        config = AppConfig.load().normalized()
        var nextAlerts: Set<String> = []

        for entry in config.databases {
            let url = URL(filePath: entry.path)

            // Find or create database entry
            let dbIdx: Int
            if let existing = databases.firstIndex(where: { $0.path == url }) {
                dbIdx = existing
            } else {
                var db = SQLiteDatabase(path: url)
                db.customName = entry.name
                db.group = entry.group
                db.isRegistered = true
                databases.append(db)
                dbIdx = databases.count - 1
            }

            databases[dbIdx].customName = entry.name
            databases[dbIdx].group = entry.group
            databases[dbIdx].isRegistered = true

            guard FileManager.default.fileExists(atPath: entry.path) else {
                databases[dbIdx].healthStatus = .error("File not found")
                databases[dbIdx].lastChecked = Date()
                databases[dbIdx].isQuiet = false
                databases[dbIdx].watchResults = []
                continue
            }

            // Snapshot previous row counts before re-inspecting
            let prevCounts = Dictionary(
                uniqueKeysWithValues: databases[dbIdx].tables.map { ($0.name, $0.rowCount) }
            )

            if let inspected = await inspector.inspect(url) {
                applyInspection(inspected, to: dbIdx)
            } else {
                databases[dbIdx].healthStatus = .error("Inspection failed")
                databases[dbIdx].lastChecked = Date()
                databases[dbIdx].watchResults = []
                continue
            }

            databases[dbIdx].previousRowCounts = prevCounts

            // Activity pulse: check if database is quiet
            databases[dbIdx].isQuiet = isDatabaseQuiet(databases[dbIdx])

            // Health check
            databases[dbIdx].healthStatus = await healthChecker.check(databases[dbIdx])
            databases[dbIdx].lastChecked = Date()

            // Run watch expressions
            if let watches = entry.watches, !watches.isEmpty {
                let results = await watchExecutor.execute(watches: watches, on: databases[dbIdx])
                databases[dbIdx].watchResults = results

                for (watch, result) in zip(watches, results) where result.alertState != .normal {
                    let key = alertKey(databaseID: databases[dbIdx].id, watch: watch)
                    nextAlerts.insert(key)
                    if !previousAlerts.contains(key) {
                        watchExecutor.sendAlert(
                            dbName: databases[dbIdx].displayName,
                            watchName: result.name,
                            value: result.displayValue
                        )
                    }
                }
            } else {
                databases[dbIdx].watchResults = []
            }
        }

        // Remove databases no longer in config
        let configPaths = Set(config.databases.map { $0.path })
        databases.removeAll { !configPaths.contains($0.path.path(percentEncoded: false)) }
        previousAlerts = nextAlerts

        lastRefresh = Date()
    }

    // MARK: - Config management

    func addDatabase(path: String, name: String? = nil, group: String? = nil) {
        config.addDatabase(path: path, name: name, group: group)
        try? config.save()
    }

    func removeDatabase(_ db: SQLiteDatabase) {
        config.removeDatabase(path: db.path.path(percentEncoded: false))
        try? config.save()
        databases.removeAll { $0.id == db.id }
    }

    func addDatabaseFromPicker() {
        NSApp.activate(ignoringOtherApps: true)
        // Menu bar popovers can reject runModal() with an alert beep.
        // Defer and use async presentation so the picker appears reliably.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }

            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = true
            panel.allowedContentTypes = [.database, .data]
            panel.message = "Select SQLite database files to monitor"
            panel.level = .floating

            panel.begin { response in
                guard response == .OK else { return }
                for url in panel.urls {
                    let name = url.deletingPathExtension().lastPathComponent
                    self.addDatabase(path: url.path(percentEncoded: false), name: name)
                }
                Task { await self.refresh() }
            }
        }
    }

    func openConfig() {
        NSApp.activate(ignoringOtherApps: true)
        _ = AppConfig.load()
        NSWorkspace.shared.open(AppConfig.configURL)
    }

    func openLitebarDirectory() {
        NSApp.activate(ignoringOtherApps: true)
        do {
            try FileManager.default.createDirectory(at: AppConfig.configDir, withIntermediateDirectories: true)
            guard NSWorkspace.shared.open(AppConfig.configDir) else {
                NSLog("[Litebar] Failed to open config directory at %@", AppConfig.configDir.path(percentEncoded: false))
                return
            }
        } catch {
            NSLog("[Litebar] Failed to create config directory at %@: %@", AppConfig.configDir.path(percentEncoded: false), error.localizedDescription)
        }
    }

    func openAgentGuide() {
        NSApp.activate(ignoringOtherApps: true)
        _ = AppConfig.load()
        NSWorkspace.shared.open(AppConfig.agentGuideURL)
    }

    func quit() {
        stopConfigWatch()
        stopAutoRefresh()
        NSApp.terminate(nil)
    }

    // MARK: - Health & Refresh

    func refreshDatabase(_ db: SQLiteDatabase) async {
        guard let idx = databases.firstIndex(where: { $0.id == db.id }) else { return }
        config = AppConfig.load().normalized()

        let prevCounts = Dictionary(
            uniqueKeysWithValues: databases[idx].tables.map { ($0.name, $0.rowCount) }
        )

        if let inspected = await inspector.inspect(db.path) {
            applyInspection(inspected, to: idx)
            databases[idx].previousRowCounts = prevCounts
        }
        databases[idx].isQuiet = isDatabaseQuiet(databases[idx])
        databases[idx].healthStatus = await healthChecker.check(databases[idx])
        databases[idx].lastChecked = Date()

        let dbPath = databases[idx].path.path(percentEncoded: false)
        if let watches = config.databases.first(where: { $0.path == dbPath })?.watches, !watches.isEmpty {
            databases[idx].watchResults = await watchExecutor.execute(watches: watches, on: databases[idx])
        } else {
            databases[idx].watchResults = []
        }
    }

    func checkHealth(for db: SQLiteDatabase) async -> HealthStatus {
        await healthChecker.check(db)
    }

    func backup(_ db: SQLiteDatabase) async throws -> BackupRecord {
        try await backupManager.backup(db)
    }

    // MARK: - Auto refresh

    func startAutoRefresh() {
        NSLog("[Litebar] startAutoRefresh called")
        refreshTask?.cancel()
        refreshTask = Task {
            NSLog("[Litebar] refresh loop starting")
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(Double(config.refreshInterval)))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func startConfigWatch() {
        do {
            try FileManager.default.createDirectory(at: AppConfig.configDir, withIntermediateDirectories: true)
        } catch {
            NSLog("[Litebar] Failed to create config directory for watcher: %@", error.localizedDescription)
            return
        }

        let dirPath = AppConfig.configDir.path(percentEncoded: false)
        let fd = open(dirPath, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("[Litebar] Failed to open config directory for watcher at %@", dirPath)
            return
        }

        let mask: DispatchSource.FileSystemEvent = [.write, .rename, .delete, .attrib, .extend]
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.pendingConfigRefresh?.cancel()
            self.pendingConfigRefresh = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self else { return }
                await self.refresh()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        configWatchSource = source
    }

    private func stopConfigWatch() {
        pendingConfigRefresh?.cancel()
        pendingConfigRefresh = nil
        configWatchSource?.cancel()
        configWatchSource = nil
    }

    // MARK: - Grouped databases

    var groupedDatabases: [(group: String, databases: [SQLiteDatabase])] {
        let grouped = Dictionary(grouping: databases) { $0.group ?? "Ungrouped" }
        return grouped.sorted { $0.key < $1.key }.map { (group: $0.key, databases: $0.value) }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func applyInspection(_ inspected: SQLiteDatabase, to index: Int) {
        databases[index].fileSize = inspected.fileSize
        databases[index].tableCount = inspected.tableCount
        databases[index].tables = inspected.tables
        databases[index].lastModified = inspected.lastModified
        databases[index].walSize = inspected.walSize
        databases[index].shmSize = inspected.shmSize
        databases[index].journalMode = inspected.journalMode
        databases[index].pageSize = inspected.pageSize
        databases[index].pageCount = inspected.pageCount
        databases[index].encoding = inspected.encoding
        databases[index].sqliteVersion = inspected.sqliteVersion
    }

    private func isDatabaseQuiet(_ database: SQLiteDatabase) -> Bool {
        guard let modified = database.lastModified else { return false }
        let minutesSinceWrite = Date().timeIntervalSince(modified) / 60
        return minutesSinceWrite > Double(config.activityTimeoutMinutes)
    }

    private func alertKey(databaseID: String, watch: AppConfig.WatchExpression) -> String {
        "\(databaseID):\(watch.name):\(watch.query)"
    }
}
