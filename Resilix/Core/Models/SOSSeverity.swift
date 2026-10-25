import Foundation
enum SOSSeverity: String, Codable, Sendable, CaseIterable {
    case critical, high, moderate, low
    var label: String {
        switch self {
        case .critical: return L("sos.severity.critical")
        case .high: return L("sos.severity.high")
        case .moderate: return L("sos.severity.moderate")
        case .low: return L("sos.severity.low")
        }
    }
    var priority: PacketPriority {
        switch self { case .critical: return .sos; case .high: return .high; case .moderate: return .normal; case .low: return .low }
    }
}
