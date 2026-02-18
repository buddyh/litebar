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
        var path: String
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

    static var configDir: URL {
        if let override = ProcessInfo.processInfo.environment["LITEBAR_CONFIG_DIR"], !override.isEmpty {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".litebar", directoryHint: .isDirectory)
    }

    static var configURL: URL { configDir.appending(path: "config.yaml") }
    static var agentGuideURL: URL { configDir.appending(path: "AGENTS.md") }

    private static var legacyConfigDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appending(path: "Litebar", directoryHint: .isDirectory)
    }

    private static var legacyYAMLConfigURL: URL { legacyConfigDir.appending(path: "config.yaml") }
    private static var legacyJSONConfigURL: URL { legacyConfigDir.appending(path: "config.json") }

    static func load() -> AppConfig {
        ensureSupportFiles()

        guard FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) else {
            return AppConfig().normalized()
        }

        do {
            let contents = try String(contentsOf: configURL, encoding: .utf8)
            let config = try YAMLDecoder().decode(AppConfig.self, from: contents)
            return config.normalized()
        } catch {
            NSLog("[Litebar] Failed to parse config at %@: %@", configURL.path(percentEncoded: false), error.localizedDescription)
            return AppConfig().normalized()
        }
    }

    func save() throws {
        try Self.createConfigDirectoryIfNeeded()
        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(normalized())
        try yaml.write(to: Self.configURL, atomically: true, encoding: .utf8)
    }

    mutating func addDatabase(path: String, name: String? = nil, group: String? = nil) {
        guard let normalizedPath = Self.normalizedAbsolutePath(path) else { return }
        guard !databases.contains(where: { $0.path == normalizedPath }) else { return }
        databases.append(
            DatabaseEntry(
                path: normalizedPath,
                name: name.trimmedNilIfEmpty,
                group: group.trimmedNilIfEmpty,
                watches: nil
            )
        )
    }

    mutating func removeDatabase(path: String) {
        guard let normalizedPath = Self.normalizedAbsolutePath(path) else { return }
        databases.removeAll { $0.path == normalizedPath }
    }

    func normalized() -> AppConfig {
        var normalized = self
        normalized.refreshInterval = max(10, refreshInterval)
        normalized.activityTimeoutMinutes = max(1, activityTimeoutMinutes)

        var mergedByPath: [String: DatabaseEntry] = [:]
        var pathOrder: [String] = []

        for entry in databases {
            guard let path = Self.normalizedAbsolutePath(entry.path) else { continue }

            let watches = entry.watches?
                .map { $0.normalized() }
                .filter { !$0.name.isEmpty && !$0.query.isEmpty }
            let normalizedWatches = (watches?.isEmpty == true) ? nil : watches

            let normalizedEntry = DatabaseEntry(
                path: path,
                name: entry.name.trimmedNilIfEmpty,
                group: entry.group.trimmedNilIfEmpty,
                watches: normalizedWatches
            )

            // Merge duplicate database paths so agent-appended entries can
            // update metadata/watches for an existing database definition.
            if var existing = mergedByPath[path] {
                if let name = normalizedEntry.name {
                    existing.name = name
                }
                if let group = normalizedEntry.group {
                    existing.group = group
                }
                // Only overwrite watches when the later entry includes a watches field.
                if entry.watches != nil {
                    existing.watches = normalizedWatches
                }
                mergedByPath[path] = existing
            } else {
                mergedByPath[path] = normalizedEntry
                pathOrder.append(path)
            }
        }

        normalized.databases = pathOrder.compactMap { mergedByPath[$0] }
        return normalized
    }

    private static func normalizedAbsolutePath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.hasPrefix("/") || trimmed.hasPrefix("~") else { return nil }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let url = URL(filePath: expanded).standardizedFileURL
        guard url.path(percentEncoded: false).hasPrefix("/") else { return nil }
        return url.path(percentEncoded: false)
    }

    private static func ensureSupportFiles() {
        try? createConfigDirectoryIfNeeded()
        ensureConfigFile()
        ensureAgentGuideFile()
    }

    private static func createConfigDirectoryIfNeeded() throws {
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    }

    private static func ensureConfigFile() {
        guard !FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) else { return }

        if migrateLegacyConfig() {
            return
        }

        let template = bundledTemplateText(resource: "config", ext: "yaml") ?? defaultConfigTemplate
        try? template.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func ensureAgentGuideFile() {
        guard !FileManager.default.fileExists(atPath: agentGuideURL.path(percentEncoded: false)) else { return }
        let template = bundledTemplateText(resource: "AGENTS", ext: "md") ?? fallbackAgentGuideTemplate
        try? template.write(to: agentGuideURL, atomically: true, encoding: .utf8)
    }

    private static func migrateLegacyConfig() -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: legacyYAMLConfigURL.path(percentEncoded: false)) {
            do {
                try fm.copyItem(at: legacyYAMLConfigURL, to: configURL)
                return true
            } catch {
                NSLog("[Litebar] Failed to migrate legacy YAML config: %@", error.localizedDescription)
            }
        }

        if fm.fileExists(atPath: legacyJSONConfigURL.path(percentEncoded: false)) {
            do {
                let data = try Data(contentsOf: legacyJSONConfigURL)
                let decoded = try JSONDecoder().decode(AppConfig.self, from: data).normalized()
                let yaml = try YAMLEncoder().encode(decoded)
                try yaml.write(to: configURL, atomically: true, encoding: .utf8)
                return true
            } catch {
                NSLog("[Litebar] Failed to migrate legacy JSON config: %@", error.localizedDescription)
            }
        }

        return false
    }

    private static func bundledTemplateText(resource: String, ext: String) -> String? {
        #if SWIFT_PACKAGE
        guard let url = Bundle.module.url(forResource: resource, withExtension: ext, subdirectory: "litebar") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
        #else
        return nil
        #endif
    }
}

private extension AppConfig.WatchExpression {
    func normalized() -> AppConfig.WatchExpression {
        AppConfig.WatchExpression(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            warnAbove: warnAbove,
            warnBelow: warnBelow,
            format: format
        )
    }
}

private extension Optional where Wrapped == String {
    var trimmedNilIfEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

private let defaultConfigTemplate = """
refresh_interval: 60
activity_timeout_minutes: 30
databases: []
"""

private let fallbackAgentGuideTemplate = """
# Litebar Runtime Agent Guide

Use this folder to manage Litebar monitoring configuration.

- `config.yaml` controls databases and watches.
- Use absolute paths.
- Watch queries must return one value.
"""
