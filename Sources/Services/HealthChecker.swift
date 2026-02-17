import Foundation

/// Runs SQLite health diagnostics on databases.
actor HealthChecker {

    func check(_ database: SQLiteDatabase) async -> HealthStatus {
        let conn = SQLiteConnection(path: database.path)
        do {
            try await conn.open()
            defer { Task { await conn.close() } }

            // 1. Integrity check
            let integrity = try await conn.integrityCheck()
            if integrity != "ok" {
                return .error("Integrity check failed: \(integrity)")
            }

            // 2. Check for corruption indicators
            let freelistCount = try await conn.scalar("PRAGMA freelist_count") ?? "0"
            let pageCount = try await conn.scalar("PRAGMA page_count") ?? "1"

            if let free = Int(freelistCount), let total = Int(pageCount), total > 0 {
                let freeRatio = Double(free) / Double(total)
                if freeRatio > 0.5 {
                    return .warning("High fragmentation (\(Int(freeRatio * 100))% free pages). Consider VACUUM.")
                }
            }

            // 3. WAL checkpoint status
            if database.journalMode?.lowercased() == "wal" {
                let walPages = try await conn.query("PRAGMA wal_checkpoint(PASSIVE)")
                if let row = walPages.first,
                   let total = row["busy"].flatMap(Int.init),
                   total > 0 {
                    return .warning("WAL has \(total) busy pages -- may need checkpointing")
                }
            }

            // 4. Check file size anomalies
            if database.fileSize == 0 {
                return .warning("Empty database file")
            }

            return .healthy
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
