import Foundation
enum ResourceCategory: String, Codable, Sendable, CaseIterable {
    case shelter, hospital, evacuationPoint = "evacuation_point", water, food, charging, rescue, safeRoute = "safe_route", hazard
    var label: String {
        switch self {
        case .shelter: return L("resource.category.shelter")
        case .hospital: return L("resource.category.hospital")
        case .evacuationPoint: return L("resource.category.evacuationPoint")
        case .water: return L("resource.category.water")
        case .food: return L("resource.category.food")
        case .charging: return L("resource.category.charging")
        case .rescue: return L("resource.category.rescue")
        case .safeRoute: return L("resource.category.safeRoute")
        case .hazard: return L("resource.category.hazard")
        }
    }
}
