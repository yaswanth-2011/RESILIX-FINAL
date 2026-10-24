import Foundation
enum SOSSeverity: String, Codable, Sendable, CaseIterable {
    case critical, high, moderate, low
    var label: String { rawValue.capitalized }
    var priority: PacketPriority {
        switch self { case .critical: return .sos; case .high: return .high; case .moderate: return .normal; case .low: return .low }
    }
}
