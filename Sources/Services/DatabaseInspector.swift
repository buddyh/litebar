import Foundation

/// Inspects a single SQLite database file and extracts metadata.
actor DatabaseInspector {

    func inspect(_ url: URL) async -> SQLiteDatabase? {
        let conn = SQLiteConnection(path: url)
        do {
            try await conn.open()
            defer { Task { await conn.close() } }

            var db = SQLiteDatabase(path: url)
            db.fileSize = fileSize(url)
            db.lastModified = modificationDate(url)
            db.walSize = fileSize(walURL(for: url))
            db.shmSize = fileSize(shmURL(for: url))

            // Pragmas
            db.journalMode = try await conn.scalar("PRAGMA journal_mode")
            if let ps = try await conn.scalar("PRAGMA page_size") { db.pageSize = Int(ps) }
            if let pc = try await conn.scalar("PRAGMA page_count") { db.pageCount = Int(pc) }
            db.encoding = try await conn.scalar("PRAGMA encoding")
            db.sqliteVersion = try await conn.scalar("SELECT sqlite_version()")

            // Tables
            let tableRows = try await conn.query(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )

            db.tableCount = tableRows.count
            for row in tableRows {
                guard let name = row["name"] else { continue }
                let quotedTableName = quotedIdentifier(name)
                var table = TableInfo(name: name)

                if let countStr = try? await conn.scalar("SELECT COUNT(*) FROM \(quotedTableName)") {
                    table.rowCount = Int64(countStr) ?? 0
                }

                let columns = try await conn.query("PRAGMA table_info(\(quotedTableName))")
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

                let indices = try await conn.query("PRAGMA index_list(\(quotedTableName))")
                table.indexCount = indices.count

                db.tables.append(table)
            }

            return db
        } catch {
            NSLog("[Litebar] Inspect failed for %@: %@", url.path(), error.localizedDescription)
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

    private func walURL(for url: URL) -> URL {
        URL(filePath: url.path(percentEncoded: false) + "-wal")
    }

    private func shmURL(for url: URL) -> URL {
        URL(filePath: url.path(percentEncoded: false) + "-shm")
    }

    private func quotedIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
