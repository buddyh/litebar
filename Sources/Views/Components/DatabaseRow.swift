import SwiftUI

struct DatabaseRow: View {
    @Environment(AppState.self) private var appState
    let database: SQLiteDatabase
    @State private var isExpanded = false
    @State private var isRefreshing = false
    @State private var isCheckingHealth = false
    @State private var isBackingUp = false
    @State private var actionMessage: String?
    @State private var actionMessageColor: Color = .secondary

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if isExpanded {
                expandedDetail
            }
        }
        .background(isExpanded ? Color.primary.opacity(0.03) : .clear, in: .rect(cornerRadius: 6))
    }

    // MARK: - Main Row

    private var mainRow: some View {
        HStack(spacing: 8) {
            // Status indicator: combines health + activity pulse
            statusIndicator

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(database.displayName)
                        .font(.system(.caption, weight: .medium))
                        .lineLimit(1)
                    if database.isQuiet {
                        Text("QUIET")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(.orange, in: .capsule)
                    }
                }

                HStack(spacing: 6) {
                    Text(database.formattedSize)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text("\(database.tableCount) tables")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    // Show delta summary if any
                    if !database.tableDeltas.isEmpty {
                        deltasSummary
                    }
                }
            }

            Spacer()

            // Watch expression badges (compact)
            if !database.watchResults.isEmpty {
                watchBadges
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }
    }

    private var statusIndicator: some View {
        ZStack {
            Image(systemName: database.healthStatus.icon)
                .foregroundStyle(database.healthStatus.color)
                .font(.caption)
            if database.isQuiet {
                Circle()
                    .fill(.orange)
                    .frame(width: 6, height: 6)
                    .offset(x: 5, y: -5)
            }
        }
    }

    private var deltasSummary: some View {
        let ups = database.tableDeltas.filter { $0.delta > 0 }.count
        let downs = database.tableDeltas.filter { $0.delta < 0 }.count
        return HStack(spacing: 2) {
            if ups > 0 {
                Text("+\(ups)")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.green)
            }
            if downs > 0 {
                Text("-\(downs)")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
    }

    private var watchBadges: some View {
        HStack(spacing: 3) {
            ForEach(database.watchResults.prefix(3)) { watch in
                VStack(spacing: 0) {
                    Text(watch.displayValue)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(watch.stateColor)
                    Text(watch.name)
                        .font(.system(size: 7))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    watch.alertState != .normal
                        ? Color.orange.opacity(0.1)
                        : Color.clear,
                    in: .rect(cornerRadius: 4)
                )
            }
        }
    }

    // MARK: - Expanded Detail

    @ViewBuilder
    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Path
            HStack {
                Text(database.path.path(percentEncoded: false))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    NSWorkspace.shared.selectFile(
                        database.path.path(percentEncoded: false),
                        inFileViewerRootedAtPath: ""
                    )
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }

            // Activity pulse
            if let modified = database.lastModified {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(database.isQuiet ? .orange : .green)
                            .frame(width: 6, height: 6)
                        Text("Last write: \(modified, style: .relative)")
                            .font(.system(size: 9))
                            .foregroundStyle(database.isQuiet ? .orange : .secondary)
                    }
                    Text(modified.formatted(date: .abbreviated, time: .standard))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            healthDetail

            // Watch expressions (full detail)
            if !database.watchResults.isEmpty {
                watchesDetail
            }

            // Table deltas
            if !database.tableDeltas.isEmpty {
                deltasDetail
            }

            // Metadata
            metadataGrid

            // Tables
            if !database.tables.isEmpty {
                tablesList
            }

            // Actions
            actionBar
            if let actionMessage {
                Text(actionMessage)
                    .font(.system(size: 9))
                    .foregroundStyle(actionMessageColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var watchesDetail: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Watches")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(database.watchResults) { watch in
                HStack(spacing: 6) {
                    Circle()
                        .fill(watch.alertState == .normal ? .green : .orange)
                        .frame(width: 5, height: 5)
                    Text(watch.name)
                        .font(.system(size: 10))
                    Spacer()
                    Text(watch.displayValue)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(watch.stateColor)
                    if let error = watch.error {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 8))
                            .foregroundStyle(.red)
                            .help(error)
                    }
                }
            }
        }
    }

    private var deltasDetail: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Changes since last refresh")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(database.tableDeltas, id: \.table) { delta in
                HStack(spacing: 4) {
                    Text(delta.table)
                        .font(.system(size: 9, design: .monospaced))
                    Spacer()
                    Text(delta.delta > 0 ? "+\(delta.delta)" : "\(delta.delta)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(delta.delta > 0 ? .green : .red)
                }
            }
        }
    }

    private var healthDetail: some View {
        HStack(spacing: 6) {
            Image(systemName: database.healthStatus.icon)
                .font(.system(size: 9))
                .foregroundStyle(database.healthStatus.color)
            Text(database.healthStatus.label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var metadataGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            GridRow {
                MetadataLabel(title: "Journal", value: database.journalMode ?? "?")
                MetadataLabel(title: "Encoding", value: database.encoding ?? "?")
                MetadataLabel(title: "SQLite", value: database.sqliteVersion ?? "?")
            }
            if let pageSize = database.pageSize, let pageCount = database.pageCount {
                GridRow {
                    MetadataLabel(title: "Page Size", value: ByteCountFormatter.string(fromByteCount: Int64(pageSize), countStyle: .file))
                    MetadataLabel(title: "Pages", value: "\(pageCount)")
                    MetadataLabel(title: "Health", value: database.healthStatus.label)
                }
            }
        }
    }

    private var tablesList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Tables")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(database.tables) { table in
                        HStack(spacing: 6) {
                            Image(systemName: "tablecells")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                            Text(table.name)
                                .font(.system(size: 10, design: .monospaced))
                            Spacer()
                            // Show delta if available
                            if let prev = database.previousRowCounts[table.name] {
                                let delta = table.rowCount - prev
                                if delta != 0 {
                                    Text(delta > 0 ? "+\(delta)" : "\(delta)")
                                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                                        .foregroundStyle(delta > 0 ? .green : .red)
                                }
                            }
                            Text("\(table.rowCount) rows")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                isRefreshing = true
                actionMessage = nil
                Task {
                    await appState.refreshDatabase(database)
                    await MainActor.run {
                        isRefreshing = false
                        actionMessage = "Refreshed"
                        actionMessageColor = .secondary
                    }
                }
            } label: {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 10))
                }
            }
            .buttonStyle(.borderless)
            .disabled(isRefreshing || isCheckingHealth || isBackingUp)

            Button {
                isCheckingHealth = true
                actionMessage = nil
                Task {
                    let status = await appState.checkHealth(for: database)
                    await MainActor.run {
                        if let idx = appState.databases.firstIndex(where: { $0.id == database.id }) {
                            appState.databases[idx].healthStatus = status
                            appState.databases[idx].lastChecked = Date()
                        }
                        isCheckingHealth = false
                        actionMessage = status.label
                        actionMessageColor = {
                            switch status {
                            case .healthy, .unknown: return .secondary
                            case .warning: return .orange
                            case .error: return .red
                            }
                        }()
                    }
                }
            } label: {
                if isCheckingHealth {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Label("Health Check", systemImage: "stethoscope")
                        .font(.system(size: 10))
                }
            }
            .buttonStyle(.borderless)
            .disabled(isRefreshing || isCheckingHealth || isBackingUp)

            Button {
                isBackingUp = true
                actionMessage = nil
                Task {
                    do {
                        let result = try await appState.backup(database)
                        await MainActor.run {
                            isBackingUp = false
                            actionMessage = "Backup saved: \(result.backupPath.lastPathComponent)"
                            actionMessageColor = .secondary
                        }
                    } catch {
                        await MainActor.run {
                            isBackingUp = false
                            actionMessage = "Backup failed: \(error.localizedDescription)"
                            actionMessageColor = .red
                        }
                    }
                }
            } label: {
                if isBackingUp {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Label("Backup", systemImage: "arrow.down.doc")
                        .font(.system(size: 10))
                }
            }
            .buttonStyle(.borderless)
            .disabled(isRefreshing || isCheckingHealth || isBackingUp)

            Spacer()
        }
        .padding(.top, 4)
    }
}

struct MetadataLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8))
                .foregroundStyle(.quaternary)
            Text(value)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
