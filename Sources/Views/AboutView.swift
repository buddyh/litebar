import SwiftUI

struct AboutView: View {
    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? short
        return short == build ? short : "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("Litebar")
                    .font(.title3.weight(.semibold))
                Text("SQLite observability for agent workflows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Version \(version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("Monitor table activity, health, and custom SQL watches", systemImage: "checkmark.circle")
                Label("Agent-managed runtime config in ~/.litebar", systemImage: "checkmark.circle")
                Label("Built for local, privacy-first SQLite visibility", systemImage: "checkmark.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Link("Project Website", destination: URL(string: "https://github.com/buddyh/litebar")!)
                Spacer()
                Link("GitHub @buddyh", destination: URL(string: "https://github.com/buddyh")!)
                Spacer()
                Link("X @buddyhadry", destination: URL(string: "https://x.com/buddyhadry")!)
            }
            .font(.caption)
        }
        .padding(20)
        .frame(width: 420, height: 280)
    }
}
