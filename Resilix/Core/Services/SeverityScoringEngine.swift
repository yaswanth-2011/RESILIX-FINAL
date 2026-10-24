import Foundation

enum SeverityScoringEngine {
    static func score(category: SOSCategory, severity: SOSSeverity, note: String?) -> (score: Int, reason: String) {
        var base: Int
        switch severity {
        case .critical: base = 100
        case .high: base = 75
        case .moderate: base = 40
        case .low: base = 15
        }
        let catBonus: Int = {
            switch category {
            case .medical, .trapped, .fire: return 20
            case .danger, .missingPerson: return 15
            case .flood, .evacuation: return 10
            case .other: return 0
            }
        }()
        let total = min(base + catBonus, 120)
        let reason: String = {
            if severity == .critical { return "Critical severity with \(category.label.lowercased()) - prioritized for immediate relay." }
            if severity == .high { return "High severity \(category.label.lowercased()) requires prompt forwarding." }
            return "\(category.label) reported with \(severity.label.lowercased()) severity."
        }()
        return (total, reason)
    }
}
