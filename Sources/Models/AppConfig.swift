import Foundation
import Yams

struct AppConfig: Codable, Sendable {
    var refreshInterval: Int = 60
    var activityTimeoutMinutes: Int = 30
    var databases: [DatabaseEntry] = []

    enum CodingKeys: String, CodingKey {
        case refreshInterval = "refresh_interval"
        case activityTimeoutMinutes = "activity_timeout_minutes"
        case databases
    }

    struct DatabaseEntry: Codable, Sendable, Identifiable {
        var id: String { path }
        let path: String
        var name: String?
        var group: String?
        var watches: [WatchExpression]?

        enum CodingKeys: String, CodingKey {
            case path, name, group, watches
        }
    }

    struct WatchExpression: Codable, Sendable, Identifiable {
        var id: String { name }
        let name: String
        let query: String
        var warnAbove: Double?
        var warnBelow: Double?
        var format: WatchFormat?

        enum CodingKeys: String, CodingKey {
            case name, query
            case warnAbove = "warn_above"
            case warnBelow = "warn_below"
            case format
        }
    }

    enum WatchFormat: String, Codable, Sendable {
        case number
        case dollar
        case bytes
        case percent
        case text
    }

    static let configDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appending(path: "Litebar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let configURL: URL = configDir.appending(path: "config.yaml")

    // Also check for JSON for backwards compatibility
    static let legacyConfigURL: URL = configDir.appending(path: "config.json")

    static func load() -> AppConfig {
        // Try YAML first
        if FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)),
           let contents = try? String(contentsOf: configURL, encoding: .utf8),
           let config = try? YAMLDecoder().decode(AppConfig.self, from: contents) {
            return config
        }
        return AppConfig()
    }

    func save() throws {
        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(self)
        try yaml.write(to: Self.configURL, atomically: true, encoding: .utf8)
    }

    mutating func addDatabase(path: String, name: String? = nil, group: String? = nil) {
        guard !databases.contains(where: { $0.path == path }) else { return }
        databases.append(DatabaseEntry(path: path, name: name, group: group, watches: nil))
    }

    mutating func removeDatabase(path: String) {
        databases.removeAll { $0.path == path }
    }
}
