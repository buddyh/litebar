import Foundation
import UserNotifications

/// Runs watch expression queries against databases and evaluates thresholds.
actor WatchExecutor {

    func execute(
        watches: [AppConfig.WatchExpression],
        on database: SQLiteDatabase
    ) async -> [WatchResult] {
        let conn = SQLiteConnection(path: database.path)
        do {
            try await conn.open()
            defer { Task { await conn.close() } }

            var results: [WatchResult] = []
            for watch in watches {
                var result = WatchResult(
                    id: "\(database.id):\(watch.name)",
                    name: watch.name,
                    query: watch.query,
                    format: watch.format ?? .number
                )

                do {
                    let raw = try await conn.scalar(watch.query)
                    result.value = raw
                    result.numericValue = raw.flatMap(Double.init)
                    result.lastUpdated = Date()

                    // Evaluate thresholds
                    if let num = result.numericValue {
                        if let above = watch.warnAbove, num > above {
                            result.alertState = .warning
                        }
                        if let below = watch.warnBelow, num < below {
                            result.alertState = .warning
                        }
                    }
                } catch {
                    result.error = error.localizedDescription
                    result.alertState = .critical
                }

                results.append(result)
            }
            return results
        } catch {
            return watches.map { watch in
                var r = WatchResult(
                    id: "\(database.id):\(watch.name)",
                    name: watch.name,
                    query: watch.query,
                    format: watch.format ?? .number
                )
                r.error = error.localizedDescription
                r.alertState = .critical
                return r
            }
        }
    }

    /// Send a macOS notification for watch alerts
    @MainActor
    func sendAlert(dbName: String, watchName: String, value: String) {
        let content = UNMutableNotificationContent()
        content.title = "Litebar"
        content.body = "\(dbName): \(watchName) = \(value)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "sqlamp-\(dbName)-\(watchName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
