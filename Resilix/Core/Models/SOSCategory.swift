import Foundation
enum SOSCategory: String, Codable, Sendable, CaseIterable {
    case medical, trapped, fire, flood, danger, missingPerson = "missing_person", evacuation, other
    var label: String {
        switch self {
        case .medical: return L("sos.category.medical")
        case .trapped: return L("sos.category.trapped")
        case .fire: return L("sos.category.fire")
        case .flood: return L("sos.category.flood")
        case .danger: return L("sos.category.danger")
        case .missingPerson: return L("sos.category.missingPerson")
        case .evacuation: return L("sos.category.evacuation")
        case .other: return L("sos.category.other")
        }
    }
}
