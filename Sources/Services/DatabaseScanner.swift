import Foundation

/// Discovers SQLite database files on the filesystem.
actor DatabaseScanner {
    private let fileManager = FileManager.default
    private let sqliteExtensions: Set<String> = ["db", "sqlite", "sqlite3", "sqlitedb"]
    private let sqliteMagicBytes: [UInt8] = Array("SQLite format 3\0".utf8)
    private let skipDirectories: Set<String> = [
        "node_modules", ".build", ".git", "DerivedData",
        "Pods", ".venv", "venv", "__pycache__", ".tox",
    ]

    /// Recursively scan a directory for SQLite databases.
    func scan(directory: URL, maxDepth: Int = 6) async -> [SQLiteDatabase] {
        var results: [SQLiteDatabase] = []
        await scanRecursive(directory: directory, depth: 0, maxDepth: maxDepth, results: &results)
        return results
    }

    private func scanRecursive(
        directory: URL,
        depth: Int,
        maxDepth: Int,
        results: inout [SQLiteDatabase]
    ) async {
        guard depth < maxDepth else { return }
        guard fileManager.isReadableFile(atPath: directory.path(percentEncoded: false)) else { return }

        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles,
        ]

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: options
        ) else { return }

        for url in contents {
            if Task.isCancelled { return }

            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues?.isDirectory ?? false

            if isDirectory {
                let dirName = url.lastPathComponent
                guard !skipDirectories.contains(dirName) else { continue }
                await scanRecursive(
                    directory: url,
                    depth: depth + 1,
                    maxDepth: maxDepth,
                    results: &results
                )
            } else if isSQLiteFile(url) {
                if var db = await inspect(url) {
                    db.fileSize = fileSize(url)
                    db.lastModified = modificationDate(url)
                    db.walSize = fileSize(url.appendingPathExtension("wal"))
                    db.shmSize = fileSize(url.appendingPathExtension("shm"))
                    results.append(db)
                }
            }
        }
    }

    private func isSQLiteFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if sqliteExtensions.contains(ext) { return true }

        // Check magic bytes for extensionless files
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 16) else { return false }
        return Array(data).starts(with: sqliteMagicBytes)
    }

    /// Open the database read-only and extract table metadata.
    private func inspect(_ url: URL) async -> SQLiteDatabase? {
        let conn = SQLiteConnection(path: url)
        do {
            try await conn.open()
            defer { Task { await conn.close() } }

            var db = SQLiteDatabase(path: url)

            // Journal mode
            db.journalMode = try await conn.scalar("PRAGMA journal_mode")

            // Page info
            if let ps = try await conn.scalar("PRAGMA page_size") { db.pageSize = Int(ps) }
            if let pc = try await conn.scalar("PRAGMA page_count") { db.pageCount = Int(pc) }

            // Encoding
            db.encoding = try await conn.scalar("PRAGMA encoding")

            // SQLite version
            db.sqliteVersion = try await conn.scalar("SELECT sqlite_version()")

            // Tables
            let tableRows = try await conn.query(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )

            db.tableCount = tableRows.count
            for row in tableRows {
                guard let name = row["name"] else { continue }
                var table = TableInfo(name: name)

                // Row count (with safety limit)
                if let countStr = try? await conn.scalar("SELECT COUNT(*) FROM \"\(name)\"") {
                    table.rowCount = Int64(countStr) ?? 0
                }

                // Column info
                let columns = try await conn.query("PRAGMA table_info(\"\(name)\")")
                table.columnCount = columns.count
                table.columns = columns.map { col in
                    ColumnInfo(
                        name: col["name"] ?? "",
                        type: col["type"] ?? "",
                        isPrimaryKey: col["pk"] == "1",
                        isNotNull: col["notnull"] == "1",
                        defaultValue: col["dflt_value"]
                    )
                }

                // Index count
                let indices = try await conn.query("PRAGMA index_list(\"\(name)\")")
                table.indexCount = indices.count

                db.tables.append(table)
            }

            return db
        } catch {
            return nil
        }
    }

    private func fileSize(_ url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return attrs?[.size] as? Int64 ?? 0
    }

    private func modificationDate(_ url: URL) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return attrs?[.modificationDate] as? Date
    }
}
