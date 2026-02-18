import Foundation
import XCTest
@testable import Litebar

final class AppConfigTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
        tempDir = base.appending(path: "litebar-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        setenv("LITEBAR_CONFIG_DIR", tempDir.path(percentEncoded: false), 1)
    }

    override func tearDownWithError() throws {
        unsetenv("LITEBAR_CONFIG_DIR")
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testLoadBootstrapsConfigAndAgentGuide() {
        _ = AppConfig.load()

        XCTAssertTrue(FileManager.default.fileExists(atPath: AppConfig.configURL.path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: AppConfig.agentGuideURL.path(percentEncoded: false)))
    }

    func testLoadNormalizesInvalidValuesAndRelativePaths() throws {
        let yaml = """
        refresh_interval: 5
        activity_timeout_minutes: 0
        databases:
          - path: relative.db
            name: Relative
          - path: \(tempDir.appending(path: "valid.sqlite").path(percentEncoded: false))
            name: Valid
        """
        try yaml.write(to: AppConfig.configURL, atomically: true, encoding: .utf8)

        let loaded = AppConfig.load()

        XCTAssertEqual(loaded.refreshInterval, 10)
        XCTAssertEqual(loaded.activityTimeoutMinutes, 1)
        XCTAssertEqual(loaded.databases.count, 1)
        XCTAssertEqual(loaded.databases.first?.name, "Valid")
    }

    func testAddDatabaseRejectsRelativePath() {
        var config = AppConfig()
        config.addDatabase(path: "relative.db")

        XCTAssertTrue(config.databases.isEmpty)
    }
}
