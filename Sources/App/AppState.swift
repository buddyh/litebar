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
    private var userRefreshTask: Task<Void, Never>?
    private var refreshRequested = false
    private var configWatchSource: DispatchSourceFileSystemObject?
    private var aboutWindowController: NSWindowController?
    private var pendingConfigRefresh: Task<Void, Never>?
    private var dbWatchSources: [String: DispatchSourceFileSystemObject] = [:]
    private var pendingDbRefresh: Task<Void, Never>?

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

    func requestRefresh() {
        refreshRequested = true
        guard userRefreshTask == nil else { return }

        // Use a detached task so refresh execution cannot inherit cancellation
        // from caller contexts (e.g. debounced config-watch tasks).
        userRefreshTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.processRefreshQueue()
        }
    }

    func refresh() async {
        requestRefresh()
        while userRefreshTask != nil {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func processRefreshQueue() async {
        defer { userRefreshTask = nil }

        while refreshRequested {
            refreshRequested = false
            await runRefreshCycle()
            if Task.isCancelled { break }
        }
    }

    private func runRefreshCycle() async {
        isLoading = true
        defer { isLoading = false }

        // Reload config (might have been edited by agent)
        config = AppConfig.load().normalized()
        var nextAlerts: Set<String> = []
        var updatedDatabases = databases

        for entry in config.databases {
            let url = URL(filePath: entry.path)

            // Find or create database entry
            let dbIdx: Int
            if let existing = updatedDatabases.firstIndex(where: { $0.path == url }) {
                dbIdx = existing
            } else {
                var db = SQLiteDatabase(path: url)
                db.customName = entry.name
                db.group = entry.group
                db.isRegistered = true
                updatedDatabases.append(db)
                dbIdx = updatedDatabases.count - 1
            }

            updatedDatabases[dbIdx].customName = entry.name
            updatedDatabases[dbIdx].group = entry.group
            updatedDatabases[dbIdx].isRegistered = true

            guard FileManager.default.fileExists(atPath: entry.path) else {
                updatedDatabases[dbIdx].healthStatus = .error("File not found")
                updatedDatabases[dbIdx].lastChecked = Date()
                updatedDatabases[dbIdx].isQuiet = false
                updatedDatabases[dbIdx].watchResults = []
                continue
            }

            // Snapshot previous row counts before re-inspecting
            let prevCounts = Dictionary(
                uniqueKeysWithValues: updatedDatabases[dbIdx].tables.map { ($0.name, $0.rowCount) }
            )

            if let inspected = await inspector.inspect(url) {
                applyInspection(inspected, to: &updatedDatabases[dbIdx])
            } else {
                updatedDatabases[dbIdx].healthStatus = .error("Inspection failed")
                updatedDatabases[dbIdx].lastChecked = Date()
                updatedDatabases[dbIdx].watchResults = []
                continue
            }

            updatedDatabases[dbIdx].previousRowCounts = prevCounts

            // Activity pulse: check if database is quiet
            updatedDatabases[dbIdx].isQuiet = isDatabaseQuiet(updatedDatabases[dbIdx])

            // Health check
            updatedDatabases[dbIdx].healthStatus = await healthChecker.check(updatedDatabases[dbIdx])
            updatedDatabases[dbIdx].lastChecked = Date()

            // Run watch expressions
            if let watches = entry.watches, !watches.isEmpty {
                let results = await watchExecutor.execute(watches: watches, on: updatedDatabases[dbIdx])
                updatedDatabases[dbIdx].watchResults = results

                for (watch, result) in zip(watches, results) where result.alertState != .normal {
                    let key = alertKey(databaseID: updatedDatabases[dbIdx].id, watch: watch)
                    nextAlerts.insert(key)
                    if !previousAlerts.contains(key) {
                        watchExecutor.sendAlert(
                            dbName: updatedDatabases[dbIdx].displayName,
                            watchName: result.name,
                            value: result.displayValue
                        )
                    }
                }
            } else {
                updatedDatabases[dbIdx].watchResults = []
            }
        }

        // Remove databases no longer in config
        let configPaths = Set(config.databases.map { $0.path })
        updatedDatabases.removeAll { !configPaths.contains($0.path.path(percentEncoded: false)) }
        databases = updatedDatabases
        previousAlerts = nextAlerts

        lastRefresh = Date()
        updateDatabaseWatchers(for: config.databases)
    }

    // MARK: - Config management

    func addDatabase(path: String, name: String? = nil, group: String? = nil) {
        config.addDatabase(path: path, name: name, group: group)
        try? config.save()
    }

    func updateRefreshInterval(seconds: Int) {
        config.refreshInterval = max(10, seconds)
        config = config.normalized()
        do {
            try config.save()
        } catch {
            NSLog("[Litebar] Failed to save refresh interval: %@", error.localizedDescription)
        }
        startAutoRefresh()
        requestRefresh()
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
                self.requestRefresh()
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
        stopAllDatabaseWatchers()
        stopAutoRefresh()
        NSApp.terminate(nil)
    }

    func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func openAboutWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let ctrl = aboutWindowController {
            ctrl.window?.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: AboutView())
        let window = NSPanel(contentViewController: hosting)
        window.title = "About Litebar"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        let ctrl = NSWindowController(window: window)
        aboutWindowController = ctrl
        ctrl.showWindow(nil)
    }

    // MARK: - Health & Refresh

    func refreshDatabase(_ db: SQLiteDatabase) async {
        guard let idx = databases.firstIndex(where: { $0.id == db.id }) else { return }
        config = AppConfig.load().normalized()
        var updated = databases[idx]

        let prevCounts = Dictionary(
            uniqueKeysWithValues: updated.tables.map { ($0.name, $0.rowCount) }
        )

        if let inspected = await inspector.inspect(updated.path) {
            applyInspection(inspected, to: &updated)
            updated.previousRowCounts = prevCounts
        }
        updated.isQuiet = isDatabaseQuiet(updated)
        updated.healthStatus = await healthChecker.check(updated)
        updated.lastChecked = Date()

        let dbPath = updated.path.path(percentEncoded: false)
        if let watches = config.databases.first(where: { $0.path == dbPath })?.watches, !watches.isEmpty {
            updated.watchResults = await watchExecutor.execute(watches: watches, on: updated)
        } else {
            updated.watchResults = []
        }
        databases[idx] = updated
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
                await MainActor.run { self.requestRefresh() }
                try? await Task.sleep(for: .seconds(Double(config.refreshInterval)))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        userRefreshTask?.cancel()
        userRefreshTask = nil
    }

    private func updateDatabaseWatchers(for databases: [AppConfig.DatabaseEntry]) {
        let neededDirs = Set(databases.map { ($0.path as NSString).deletingLastPathComponent })

        for dir in Set(dbWatchSources.keys).subtracting(neededDirs) {
            dbWatchSources.removeValue(forKey: dir)?.cancel()
        }

        for dir in neededDirs where dbWatchSources[dir] == nil {
            let fd = open(dir, O_EVTONLY)
            guard fd >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .rename, .delete, .attrib],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                guard let self else { return }
                self.pendingDbRefresh?.cancel()
                self.pendingDbRefresh = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self else { return }
                    await MainActor.run { self.requestRefresh() }
                }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            dbWatchSources[dir] = source
        }
    }

    private func stopAllDatabaseWatchers() {
        pendingDbRefresh?.cancel()
        pendingDbRefresh = nil
        dbWatchSources.values.forEach { $0.cancel() }
        dbWatchSources.removeAll()
    }

    func startConfigWatch() {
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
                await MainActor.run { self.requestRefresh() }
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

    private func applyInspection(_ inspected: SQLiteDatabase, to database: inout SQLiteDatabase) {
        database.fileSize = inspected.fileSize
        database.tableCount = inspected.tableCount
        database.tables = inspected.tables
        database.lastModified = inspected.lastModified
        database.walSize = inspected.walSize
        database.shmSize = inspected.shmSize
        database.journalMode = inspected.journalMode
        database.pageSize = inspected.pageSize
        database.pageCount = inspected.pageCount
        database.encoding = inspected.encoding
        database.sqliteVersion = inspected.sqliteVersion
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
