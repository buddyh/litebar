import Foundation
import SQLite3

/// Lightweight wrapper around the SQLite3 C API for read-only inspection.
actor SQLiteConnection {
    private var db: OpaquePointer?
    let path: URL

    init(path: URL) {
        self.path = path
    }

    func open() throws {
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(path.path(percentEncoded: false), &db, flags, nil)
        guard result == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            throw LitebarError.cannotOpen(msg)
        }
        // Set a short busy timeout so we don't block
        sqlite3_busy_timeout(db, 1000)
    }

    func close() {
        if let db {
            sqlite3_close_v2(db)
        }
        db = nil
    }

    func query(_ sql: String) throws -> [[String: String]] {
        guard let db else { throw LitebarError.notConnected }

        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepareResult == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw LitebarError.queryFailed(msg)
        }
        defer { sqlite3_finalize(stmt) }

        var rows: [[String: String]] = []
        let columnCount = sqlite3_column_count(stmt)

        while true {
            let stepResult = sqlite3_step(stmt)
            if stepResult == SQLITE_ROW {
                var row: [String: String] = [:]
                for i in 0..<columnCount {
                    let name = String(cString: sqlite3_column_name(stmt, i))
                    if let text = sqlite3_column_text(stmt, i) {
                        row[name] = String(cString: text)
                    } else {
                        row[name] = nil
                    }
                }
                rows.append(row)
                continue
            }

            if stepResult == SQLITE_DONE {
                break
            }

            let msg = String(cString: sqlite3_errmsg(db))
            throw LitebarError.queryFailed(msg)
        }
        return rows
    }

    func scalar(_ sql: String) throws -> String? {
        guard let db else { throw LitebarError.notConnected }

        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepareResult == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw LitebarError.queryFailed(msg)
        }
        defer { sqlite3_finalize(stmt) }

        let stepResult = sqlite3_step(stmt)
        if stepResult == SQLITE_DONE {
            return nil
        }
        guard stepResult == SQLITE_ROW else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw LitebarError.queryFailed(msg)
        }

        guard let text = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        return String(cString: text)
    }

    func integrityCheck() throws -> String {
        try scalar("PRAGMA integrity_check") ?? "unknown"
    }

    // Connection cleanup is handled via explicit close() calls.
    // The actor isolation prevents accessing `db` in deinit under Swift 6.
}

enum LitebarError: LocalizedError {
    case cannotOpen(String)
    case notConnected
    case queryFailed(String)
    case backupFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let msg): "Cannot open database: \(msg)"
        case .notConnected: "Not connected to database"
        case .queryFailed(let msg): "Query failed: \(msg)"
        case .backupFailed(let msg): "Backup failed: \(msg)"
        }
    }
}
