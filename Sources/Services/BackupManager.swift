import Foundation
import SQLite3

/// Manages SQLite database backups using the SQLite Online Backup API.
actor BackupManager {
    private let backupRoot: URL
    private var historyStore: [String: [BackupRecord]] = [:]

    init() {
        self.backupRoot = AppConfig.configDir.appending(path: "backups", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
    }

    func backup(_ database: SQLiteDatabase) async throws -> BackupRecord {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let safeName = database.displayName.replacingOccurrences(of: "/", with: "_")
        let destDir = backupRoot.appending(path: safeName)
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destPath = destDir.appending(path: "\(safeName)_\(timestamp).sqlite3")

        // Use SQLite Online Backup API for a consistent copy
        try await performBackup(from: database.path, to: destPath)

        let attrs = try FileManager.default.attributesOfItem(atPath: destPath.path(percentEncoded: false))
        let size = attrs[.size] as? Int64 ?? 0

        let record = BackupRecord(
            id: UUID(),
            sourceDatabase: database.path,
            backupPath: destPath,
            timestamp: Date(),
            sizeBytes: size,
            verified: true
        )

        historyStore[database.id, default: []].insert(record, at: 0)

        return record
    }

    func history(for database: SQLiteDatabase) -> [BackupRecord] {
        historyStore[database.id] ?? []
    }

    // MARK: - SQLite Online Backup API

    private func performBackup(from sourcePath: URL, to destPath: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var sourceDB: OpaquePointer?
            var destDB: OpaquePointer?

            let sourceResult = sqlite3_open_v2(
                sourcePath.path(percentEncoded: false),
                &sourceDB,
                SQLITE_OPEN_READONLY,
                nil
            )
            guard sourceResult == SQLITE_OK else {
                continuation.resume(throwing: LitebarError.backupFailed("Cannot open source"))
                return
            }

            let destResult = sqlite3_open_v2(
                destPath.path(percentEncoded: false),
                &destDB,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
                nil
            )
            guard destResult == SQLITE_OK else {
                sqlite3_close_v2(sourceDB)
                continuation.resume(throwing: LitebarError.backupFailed("Cannot create backup destination"))
                return
            }

            guard let backup = sqlite3_backup_init(destDB, "main", sourceDB, "main") else {
                let msg = destDB.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown"
                sqlite3_close_v2(sourceDB)
                sqlite3_close_v2(destDB)
                continuation.resume(throwing: LitebarError.backupFailed(msg))
                return
            }

            // Copy all pages in one step (-1)
            let stepResult = sqlite3_backup_step(backup, -1)
            sqlite3_backup_finish(backup)
            sqlite3_close_v2(sourceDB)
            sqlite3_close_v2(destDB)

            if stepResult == SQLITE_DONE {
                continuation.resume()
            } else {
                continuation.resume(throwing: LitebarError.backupFailed("Backup step failed: \(stepResult)"))
            }
        }
    }
}
