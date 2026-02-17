import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            Tab("Databases", systemImage: "cylinder.split.1x2") {
                databasesTab
            }
            Tab("Config", systemImage: "doc.text") {
                configTab
            }
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
                    Text("Edit config.yaml to add databases and watch expressions")
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
                Button("Edit config.yaml") {
                    appState.openConfig()
                }
            }
            .padding(12)
        }
    }

    // MARK: - Config Tab

    private var configTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Config File") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(AppConfig.configURL.path(percentEncoded: false))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button("Open") {
                            appState.openConfig()
                        }
                        .controlSize(.small)
                    }
                    Text("Edit this file to add databases, watch expressions, and alerts. Agents can also edit it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(4)
            }

            GroupBox("Backups") {
                let backupPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    .appending(path: "Litebar/Backups")
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

            Spacer()
        }
        .padding()
    }
}
