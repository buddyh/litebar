import Foundation
import SQLite3
import XCTest
@testable import Litebar

final class WatchExecutorTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
        tempDir = base.appending(path: "litebar-watch-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testWatchesSeeLatestRowsAfterInsert() async throws {
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

        let watch = AppConfig.WatchExpression(
            name: "Proposals Awaiting Approval",
            query: "SELECT COUNT(*) FROM orchestration_proposals WHERE status = 'proposed'",
            warnAbove: nil,
            warnBelow: nil,
            format: .number
        )
        let db = SQLiteDatabase(path: dbURL)
        let executor = WatchExecutor()

        let first = await executor.execute(watches: [watch], on: db)
        XCTAssertEqual(first.first?.value, "37")

        try execSQL("INSERT INTO orchestration_proposals(status) VALUES ('proposed');", on: dbURL)

        let second = await executor.execute(watches: [watch], on: db)
        XCTAssertEqual(second.first?.value, "38")
    }

    private func execSQL(_ sql: String, on dbURL: URL) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(dbURL.path(percentEncoded: false), &db, flags, nil) == SQLITE_OK else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close_v2(db)
            throw NSError(
                domain: "WatchExecutorTests",
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
                domain: "WatchExecutorTests",
                code: Int(result),
                userInfo: [NSLocalizedDescriptionKey: "SQL failed: \(message)"]
            )
        }
    }
}
