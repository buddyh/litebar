import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            databasesTab
                .tabItem { Label("Databases", systemImage: "cylinder.split.1x2") }
            configTab
                .tabItem { Label("Agent Setup", systemImage: "person.2.fill") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 380)
    }

    // MARK: - Databases Tab

    private var databasesTab: some View {
        VStack(spacing: 0) {
            if appState.config.databases.isEmpty {
                VStack(spacing: 8) {
                    Text("No databases configured")
                        .foregroundStyle(.secondary)
                    Text("Populate ~/.litebar/config.yaml via your agent")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.config.databases) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.name ?? URL(filePath: entry.path).lastPathComponent)
                                    .font(.system(.body, weight: .medium))
                                if let group = entry.group {
                                    Text(group)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.quaternary, in: .capsule)
                                }
                            }
                            Text(entry.path)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let watches = entry.watches, !watches.isEmpty {
                                Text("\(watches.count) watch expressions")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Add Database...") {
                    appState.addDatabaseFromPicker()
                }
                Spacer()
                Button("Open ~/.litebar") {
                    appState.openLitebarDirectory()
                }
            }
            .padding(12)
        }
    }

    // MARK: - Config Tab

    private var configTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Agent-Managed Folder") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(AppConfig.configDir.path(percentEncoded: false))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button("Open Folder") {
                            appState.openLitebarDirectory()
                        }
                        .controlSize(.small)
                    }
                    Text("Agents should manage this folder. It contains config.yaml and an AGENTS.md capability guide.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Open config.yaml") {
                            appState.openConfig()
                        }
                        .controlSize(.small)
                        Button("Open AGENTS.md") {
                            appState.openAgentGuide()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(4)
            }

            GroupBox("Backups") {
                let backupPath = AppConfig.configDir.appending(path: "backups", directoryHint: .isDirectory)
                HStack {
                    Text(backupPath.path(percentEncoded: false))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button("Open") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: backupPath.path(percentEncoded: false))
                    }
                    .controlSize(.small)
                }
                .padding(4)
            }

            GroupBox("Current Settings") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("Refresh interval:").foregroundStyle(.secondary)
                        Text("\(appState.config.refreshInterval)s")
                    }
                    GridRow {
                        Text("Activity timeout:").foregroundStyle(.secondary)
                        Text("\(appState.config.activityTimeoutMinutes) min")
                    }
                    GridRow {
                        Text("Databases:").foregroundStyle(.secondary)
                        Text("\(appState.config.databases.count)")
                    }
                    GridRow {
                        Text("Watch expressions:").foregroundStyle(.secondary)
                        Text("\(appState.config.databases.reduce(0) { $0 + ($1.watches?.count ?? 0) })")
                    }
                }
                .font(.caption)
                .padding(4)
            }

            GroupBox("Quick Controls") {
                HStack {
                    Text("Refresh cadence")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Stepper(
                        value: Binding(
                            get: { appState.config.refreshInterval },
                            set: { appState.updateRefreshInterval(seconds: $0) }
                        ),
                        in: 10...3600,
                        step: 5
                    ) {
                        Text("\(appState.config.refreshInterval)s")
                            .font(.caption.monospacedDigit())
                    }
                    .frame(width: 170, alignment: .trailing)
                }
                Text("Writes to ~/.litebar/config.yaml. Agents can still update this value.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "cylinder.split.1x2")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Litebar")
                        .font(.headline)
                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("Litebar monitors SQLite health, activity, and custom watch queries for agent-driven systems.")
                .font(.callout)

            VStack(alignment: .leading, spacing: 6) {
                Label("Menu bar visibility into tables, watch values, and alerts", systemImage: "checkmark.circle")
                Label("Agent-managed config at ~/.litebar/config.yaml", systemImage: "checkmark.circle")
                Label("Open source: github.com/buddyh/litebar", systemImage: "checkmark.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            HStack {
                Link("GitHub Repo", destination: URL(string: "https://github.com/buddyh/litebar")!)
                Link("GitHub @buddyh", destination: URL(string: "https://github.com/buddyh")!)
                Link("X @buddyhadry", destination: URL(string: "https://x.com/buddyhadry")!)
                Spacer()
                Button("Open About Window") {
                    NotificationCenter.default.post(name: .litebarOpenAbout, object: nil)
                }
                .controlSize(.small)
            }
        }
        .padding()
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? short
        return short == build ? short : "\(short) (\(build))"
    }
}
