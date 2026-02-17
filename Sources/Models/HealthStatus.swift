import Foundation
import SwiftUI

enum HealthStatus: Sendable, Equatable {
    case healthy
    case warning(String)
    case error(String)
    case unknown

    var label: String {
        switch self {
        case .healthy: "Healthy"
        case .warning(let msg): "Warning: \(msg)"
        case .error(let msg): "Error: \(msg)"
        case .unknown: "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .healthy: .green
        case .warning: .orange
        case .error: .red
        case .unknown: .secondary
        }
    }
}
