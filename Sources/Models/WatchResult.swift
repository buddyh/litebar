import Foundation
import SwiftUI

struct WatchResult: Identifiable, Sendable {
    let id: String
    let name: String
    let query: String
    var value: String?
    var numericValue: Double?
    var alertState: AlertState = .normal
    var format: AppConfig.WatchFormat
    var lastUpdated: Date?
    var error: String?

    enum AlertState: Sendable {
        case normal
        case warning
        case critical
    }

    var displayValue: String {
        guard let value else { return "--" }
        guard let num = numericValue else { return value }

        switch format {
        case .dollar:
            return "$\(String(format: "%.2f", num))"
        case .bytes:
            return ByteCountFormatter.string(fromByteCount: Int64(num), countStyle: .file)
        case .percent:
            return "\(String(format: "%.1f", num))%"
        case .number:
            if num == num.rounded() && num < 1_000_000 {
                return String(Int(num))
            }
            return String(format: "%.1f", num)
        case .text:
            return value
        }
    }

    var stateColor: Color {
        switch alertState {
        case .normal: .primary
        case .warning: .orange
        case .critical: .red
        }
    }
}
