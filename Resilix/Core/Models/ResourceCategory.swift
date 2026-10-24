import Foundation
enum ResourceCategory: String, Codable, Sendable, CaseIterable {
    case shelter, hospital, evacuationPoint = "evacuation_point", water, food, charging, rescue, safeRoute = "safe_route", hazard
    var label: String {
        switch self {
        case .shelter: return "Shelter"
        case .hospital: return "Hospital"
        case .evacuationPoint: return "Evacuation point"
        case .water: return "Water"
        case .food: return "Food"
        case .charging: return "Charging"
        case .rescue: return "Rescue"
        case .safeRoute: return "Safe route"
        case .hazard: return "Hazard"
        }
    }
}
