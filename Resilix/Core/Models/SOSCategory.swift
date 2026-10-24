import Foundation
enum SOSCategory: String, Codable, Sendable, CaseIterable {
    case medical, trapped, fire, flood, danger, missingPerson = "missing_person", evacuation, other
    var label: String {
        switch self {
        case .medical: return "Medical"
        case .trapped: return "Trapped"
        case .fire: return "Fire"
        case .flood: return "Flood"
        case .danger: return "Danger"
        case .missingPerson: return "Missing person"
        case .evacuation: return "Evacuation"
        case .other: return "Other"
        }
    }
}
