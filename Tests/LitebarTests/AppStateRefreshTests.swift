import Foundation
import SQLite3
import XCTest
@testable import Litebar

final class AppStateRefreshTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
        tempDir = base.appending(path: "litebar-appstate-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        setenv("LITEBAR_CONFIG_DIR", tempDir.path(percentEncoded: false), 1)
    }

    override func tearDownWithError() throws {
        unsetenv("LITEBAR_CONFIG_DIR")
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    @MainActor
    func testRefreshUpdatesWatchValuesAfterInsert() async throws {
        let dbURL = tempDir.appending(path: "runs.db")
        try execSQL("PRAGMA journal_mode=WAL;", on: dbURL)
        try execSQL(
            "CREATE TABLE orchestration_proposals (id INTEGER PRIMARY KEY AUTOINCREMENT, status TEXT NOT NULL);",
            on: dbURL
        )
        try execSQL(
            "WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c WHERE x < 37) INSERT INTO orchestration_proposals(status) SELECT 'proposed' FROM c;",
            on: dbURL
        )

        let configYAML = """
        refresh_interval: 60
        activity_timeout_minutes: 30
        databases:
          - path: \(dbURL.path(percentEncoded: false))
            name: Test DB
            watches:
              - name: Proposals Awaiting Approval
                query: "SELECT COUNT(*) FROM orchestration_proposals WHERE status = 'proposed'"
        """
        try configYAML.write(to: AppConfig.configURL, atomically: true, encoding: .utf8)

        let appState = AppState(autoStart: false, requestNotifications: false)
        await appState.refresh()
        XCTAssertEqual(value(of: "Proposals Awaiting Approval", in: appState), "37")

        try execSQL("INSERT INTO orchestration_proposals(status) VALUES ('proposed');", on: dbURL)

        await appState.refresh()
        XCTAssertEqual(value(of: "Proposals Awaiting Approval", in: appState), "38")
    }

    @MainActor
    func testRequestRefreshUpdatesAfterRapidCalls() async throws {
        let dbURL = tempDir.appending(path: "runs-rapid.db")
        try execSQL("PRAGMA journal_mode=WAL;", on: dbURL)
        try execSQL(
            "CREATE TABLE orchestration_proposals (id INTEGER PRIMARY KEY AUTOINCREMENT, status TEXT NOT NULL);",
            on: dbURL
        )
        try execSQL(
            "WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c WHERE x < 37) INSERT INTO orchestration_proposals(status) SELECT 'proposed' FROM c;",
            on: dbURL
        )

        let configYAML = """
        refresh_interval: 60
        activity_timeout_minutes: 30
        databases:
          - path: \(dbURL.path(percentEncoded: false))
            name: Rapid Test DB
            watches:
              - name: Proposals Awaiting Approval
                query: "SELECT COUNT(*) FROM orchestration_proposals WHERE status = 'proposed'"
        """
        try configYAML.write(to: AppConfig.configURL, atomically: true, encoding: .utf8)

        let appState = AppState(autoStart: false, requestNotifications: false)

        appState.requestRefresh()
        try await waitForValue(named: "Proposals Awaiting Approval", equals: "37", in: appState)

        try execSQL("INSERT INTO orchestration_proposals(status) VALUES ('proposed');", on: dbURL)
        for _ in 0..<8 { appState.requestRefresh() }
        try await waitForValue(named: "Proposals Awaiting Approval", equals: "38", in: appState)

        try execSQL(
            "WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c WHERE x < 5) INSERT INTO orchestration_proposals(status) SELECT 'proposed' FROM c;",
            on: dbURL
        )
        for _ in 0..<8 { appState.requestRefresh() }
        try await waitForValue(named: "Proposals Awaiting Approval", equals: "43", in: appState)
    }

    @MainActor
    private func value(of watchName: String, in appState: AppState) -> String? {
        appState.databases.first?
            .watchResults
            .first(where: { $0.name == watchName })?
            .value
    }

    @MainActor
    private func waitForValue(
        named watchName: String,
        equals expected: String,
        in appState: AppState
    ) async throws {
        let timeoutNanos: UInt64 = 5_000_000_000
        let intervalNanos: UInt64 = 50_000_000
        var waited: UInt64 = 0

        while waited <= timeoutNanos {
            if value(of: watchName, in: appState) == expected {
                return
            }
            try await Task.sleep(nanoseconds: intervalNanos)
            waited += intervalNanos
        }

        throw NSError(
            domain: "AppStateRefreshTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for watch '\(watchName)' to equal '\(expected)'"]
        )
    }

    private func execSQL(_ sql: String, on dbURL: URL) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(dbURL.path(percentEncoded: false), &db, flags, nil) == SQLITE_OK else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close_v2(db)
            throw NSError(
                domain: "AppStateRefreshTests",
                code: Int(SQLITE_CANTOPEN),
                userInfo: [NSLocalizedDescriptionKey: "Failed to open test database: \(message)"]
            )
        }
        defer { sqlite3_close_v2(db) }

        var errMsg: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if result != SQLITE_OK {
            let message = errMsg.map { String(cString: $0) } ?? "Unknown sqlite error"
            sqlite3_free(errMsg)
            throw NSError(
                domain: "AppStateRefreshTests",
                code: Int(result),
                userInfo: [NSLocalizedDescriptionKey: "SQL failed: \(message)"]
            )
        }
    }
}
