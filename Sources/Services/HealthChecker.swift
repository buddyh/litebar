import Foundation

/// Runs SQLite health diagnostics on databases.
actor HealthChecker {

    func check(_ database: SQLiteDatabase) async -> HealthStatus {
        let conn = SQLiteConnection(path: database.path)
        do {
            try await conn.open()

            // 1. Integrity check
            let integrity = try await conn.integrityCheck()
            if integrity != "ok" {
                await conn.close()
                return .error("Integrity check failed: \(integrity)")
            }

            // 2. Check for corruption indicators
            let freelistCount = try await conn.scalar("PRAGMA freelist_count") ?? "0"
            let pageCount = try await conn.scalar("PRAGMA page_count") ?? "1"

            if let free = Int(freelistCount), let total = Int(pageCount), total > 0 {
                let freeRatio = Double(free) / Double(total)
                if freeRatio > 0.5 {
                    await conn.close()
                    return .warning("High fragmentation (\(Int(freeRatio * 100))% free pages). Consider VACUUM.")
                }
            }

            // 3. WAL pressure signal (read-only safe)
            if database.journalMode?.lowercased() == "wal" {
                let walBytes = database.walSize ?? 0
                let warnThreshold: Int64 = 100 * 1024 * 1024 // 100 MB
                if walBytes > warnThreshold {
                    let formatted = ByteCountFormatter.string(fromByteCount: walBytes, countStyle: .file)
                    await conn.close()
                    return .warning("Large WAL file (\(formatted)). Consider checkpointing from a read-write process.")
                }
            }

            // 4. Check file size anomalies
            if database.fileSize == 0 {
                await conn.close()
                return .warning("Empty database file")
            }

            await conn.close()
            return .healthy
        } catch {
            await conn.close()
            return .error(error.localizedDescription)
        }
    }
}
