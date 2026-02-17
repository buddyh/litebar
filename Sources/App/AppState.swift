import Foundation
import SwiftUI
import UserNotifications

@MainActor
@Observable
final class AppState {
    var databases: [SQLiteDatabase] = []
    var config: AppConfig
    var isLoading = false
    var lastRefresh: Date?
    var selectedDatabase: SQLiteDatabase?

    // Track previous alert states to only notify on transitions
    private var previousAlerts: Set<String> = []

    private let inspector = DatabaseInspector()
    private let healthChecker = HealthChecker()
    private let watchExecutor = WatchExecutor()
    private let backupManager = BackupManager()
    private var refreshTask: Task<Void, Never>?

    var totalWarnings: Int {
        databases.reduce(0) { count, db in
            count + db.watchResults.filter { $0.alertState != .normal }.count + (db.isQuiet ? 1 : 0)
        }
    }

    init() {
        self.config = AppConfig.load()
        requestNotificationPermission()
    }

    // MARK: - Full refresh cycle

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        // Reload config (might have been edited by agent)
        config = AppConfig.load()

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

            guard FileManager.default.fileExists(atPath: entry.path) else {
                databases[dbIdx].healthStatus = .error("File not found")
                databases[dbIdx].customName = entry.name
                databases[dbIdx].group = entry.group
                continue
            }

            // Snapshot previous row counts before re-inspecting
            let prevCounts = Dictionary(
                uniqueKeysWithValues: databases[dbIdx].tables.map { ($0.name, $0.rowCount) }
            )

            // Inspect database
            if let inspected = await inspector.inspect(url) {
                databases[dbIdx].fileSize = inspected.fileSize
                databases[dbIdx].tableCount = inspected.tableCount
                databases[dbIdx].tables = inspected.tables
                databases[dbIdx].lastModified = inspected.lastModified
                databases[dbIdx].walSize = inspected.walSize
                databases[dbIdx].shmSize = inspected.shmSize
                databases[dbIdx].journalMode = inspected.journalMode
                databases[dbIdx].pageSize = inspected.pageSize
                databases[dbIdx].pageCount = inspected.pageCount
                databases[dbIdx].encoding = inspected.encoding
                databases[dbIdx].sqliteVersion = inspected.sqliteVersion
            }

            databases[dbIdx].customName = entry.name
            databases[dbIdx].group = entry.group
            databases[dbIdx].isRegistered = true
            databases[dbIdx].previousRowCounts = prevCounts

            // Activity pulse: check if database is quiet
            if let modified = databases[dbIdx].lastModified {
                let minutesSinceWrite = Date().timeIntervalSince(modified) / 60
                databases[dbIdx].isQuiet = minutesSinceWrite > Double(config.activityTimeoutMinutes)
            }

            // Health check
            databases[dbIdx].healthStatus = await healthChecker.check(databases[dbIdx])
            databases[dbIdx].lastChecked = Date()

            // Run watch expressions
            if let watches = entry.watches, !watches.isEmpty {
                let results = await watchExecutor.execute(watches: watches, on: databases[dbIdx])
                databases[dbIdx].watchResults = results

                // Send notifications for new alerts
                for result in results where result.alertState != .normal {
                    let alertKey = "\(databases[dbIdx].displayName):\(result.name)"
                    if !previousAlerts.contains(alertKey) {
                        previousAlerts.insert(alertKey)
                        await watchExecutor.sendAlert(
                            dbName: databases[dbIdx].displayName,
                            watchName: result.name,
                            value: result.displayValue
                        )
                    }
                }

                // Clear resolved alerts
                for result in results where result.alertState == .normal {
                    let alertKey = "\(databases[dbIdx].displayName):\(result.name)"
                    previousAlerts.remove(alertKey)
                }
            }
        }

        // Remove databases no longer in config
        let configPaths = Set(config.databases.map { $0.path })
        databases.removeAll { !configPaths.contains($0.path.path(percentEncoded: false)) }

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
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.database, .data]
        panel.message = "Select SQLite database files to monitor"

        if panel.runModal() == .OK {
            for url in panel.urls {
                let name = url.deletingPathExtension().lastPathComponent
                addDatabase(path: url.path(percentEncoded: false), name: name)
            }
            Task { await refresh() }
        }
    }

    func openConfig() {
        NSWorkspace.shared.open(AppConfig.configURL)
    }

    // MARK: - Health & Refresh

    func refreshDatabase(_ db: SQLiteDatabase) async {
        guard let idx = databases.firstIndex(where: { $0.id == db.id }) else { return }
        if let inspected = await inspector.inspect(db.path) {
            databases[idx].fileSize = inspected.fileSize
            databases[idx].tableCount = inspected.tableCount
            databases[idx].tables = inspected.tables
            databases[idx].lastModified = inspected.lastModified
            databases[idx].walSize = inspected.walSize
            databases[idx].shmSize = inspected.shmSize
            databases[idx].journalMode = inspected.journalMode
            databases[idx].pageSize = inspected.pageSize
            databases[idx].pageCount = inspected.pageCount
            databases[idx].encoding = inspected.encoding
            databases[idx].sqliteVersion = inspected.sqliteVersion
        }
        databases[idx].healthStatus = await healthChecker.check(databases[idx])
        databases[idx].lastChecked = Date()
    }

    func checkHealth(for db: SQLiteDatabase) async -> HealthStatus {
        await healthChecker.check(db)
    }

    func backup(_ db: SQLiteDatabase) async throws -> BackupRecord {
        try await backupManager.backup(db)
    }

    // MARK: - Auto refresh

    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
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

    // MARK: - Grouped databases

    var groupedDatabases: [(group: String, databases: [SQLiteDatabase])] {
        let grouped = Dictionary(grouping: databases) { $0.group ?? "Ungrouped" }
        return grouped.sorted { $0.key < $1.key }.map { (group: $0.key, databases: $0.value) }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
