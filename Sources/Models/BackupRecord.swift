import Foundation

struct BackupRecord: Identifiable, Sendable {
    let id: UUID
    let sourceDatabase: URL
    let backupPath: URL
    let timestamp: Date
    let sizeBytes: Int64
    var verified: Bool = false

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var age: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
