import Foundation

struct SQLiteDatabase: Identifiable, Hashable, Sendable {
    let id: String
    let path: URL
    var customName: String?
    var group: String?
    var isPinned: Bool = false
    var isRegistered: Bool = false  // from config vs discovered

    // Discovered metadata
    var fileSize: Int64 = 0
    var tableCount: Int = 0
    var tables: [TableInfo] = []
    var lastModified: Date?
    var walSize: Int64?
    var shmSize: Int64?
    var journalMode: String?
    var pageSize: Int?
    var pageCount: Int?
    var encoding: String?
    var sqliteVersion: String?

    // Status
    var healthStatus: HealthStatus = .unknown
    var lastChecked: Date?
    var backupRecords: [BackupRecord] = []

    // Watch expressions
    var watchResults: [WatchResult] = []

    // Activity pulse
    var isQuiet: Bool = false           // no writes within timeout
    var previousRowCounts: [String: Int64] = [:]  // table name -> last known count

    var tableDeltas: [(table: String, delta: Int64)] {
        tables.compactMap { table in
            guard let prev = previousRowCounts[table.name] else { return nil }
            let delta = table.rowCount - prev
            guard delta != 0 else { return nil }
            return (table: table.name, delta: delta)
        }
    }

    var hasWarnings: Bool {
        watchResults.contains { $0.alertState != .normal } || isQuiet
    }

    var displayName: String {
        customName ?? path.deletingPathExtension().lastPathComponent
    }

    var totalSize: Int64 {
        fileSize + (walSize ?? 0) + (shmSize ?? 0)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    var parentApp: String? {
        // Try to extract app name from path
        // e.g. ~/Library/Containers/com.apple.Notes/Data/...
        let components = path.pathComponents
        if let containerIdx = components.firstIndex(of: "Containers"),
           containerIdx + 1 < components.count {
            return components[containerIdx + 1]
        }
        if let appSupportIdx = components.firstIndex(of: "Application Support"),
           appSupportIdx + 1 < components.count {
            return components[appSupportIdx + 1]
        }
        return nil
    }

    init(path: URL) {
        self.id = path.absoluteString
        self.path = path
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SQLiteDatabase, rhs: SQLiteDatabase) -> Bool {
        lhs.id == rhs.id
    }
}

struct TableInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    var rowCount: Int64 = 0
    var columnCount: Int = 0
    var columns: [ColumnInfo] = []
    var indexCount: Int = 0

    init(name: String) {
        self.id = name
        self.name = name
    }
}

struct ColumnInfo: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let type: String
    let isPrimaryKey: Bool
    let isNotNull: Bool
    let defaultValue: String?
}
