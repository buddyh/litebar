import SwiftUI

struct MenuBarPanel: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""

    private var filteredGroups: [(group: String, databases: [SQLiteDatabase])] {
        if searchText.isEmpty {
            return appState.groupedDatabases
        }
        return appState.groupedDatabases.compactMap { group in
            let filtered = group.databases.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText) ||
                $0.path.path().localizedCaseInsensitiveContains(searchText)
            }
            return filtered.isEmpty ? nil : (group: group.group, databases: filtered)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if appState.isLoading && appState.databases.isEmpty {
                loadingView
            } else if appState.databases.isEmpty {
                emptyState
            } else {
                searchBar
                Divider()
                databaseList
            }

            Divider()
            footer
        }
        .frame(width: 420, height: 520)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "cylinder.split.1x2")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Litebar")
                .font(.headline)
            Spacer()
            if appState.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if let lastRefresh = appState.lastRefresh {
                Text(lastRefresh, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await appState.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(appState.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("Search...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: .rect(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Database List

    private var databaseList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(filteredGroups, id: \.group) { group in
                    if filteredGroups.count > 1 || group.group != "Ungrouped" {
                        Text(group.group)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                    }
                    ForEach(group.databases) { db in
                        DatabaseRow(database: db)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading databases...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "cylinder")
                .font(.largeTitle)
                .foregroundStyle(.quaternary)
            Text("No databases registered")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Point an agent at ~/.litebar/config.yaml to populate monitors")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("Add Database...") {
                appState.addDatabaseFromPicker()
            }
            .controlSize(.small)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("\(appState.databases.count) databases")
                .font(.caption)
                .foregroundStyle(.secondary)
            if appState.totalWarnings > 0 {
                Text("\(appState.totalWarnings) alerts")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            Text("Agent-managed")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Button {
                appState.addDatabaseFromPicker()
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Add database")

            Button {
                appState.openLitebarDirectory()
            } label: {
                Image(systemName: "folder")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Open ~/.litebar")

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
