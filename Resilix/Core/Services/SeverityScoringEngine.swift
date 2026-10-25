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
            if severity == .critical { return String(format: L("Critical severity with %@ - prioritized for immediate relay."), category.label.lowercased()) }
            if severity == .high { return String(format: L("High severity %@ requires prompt forwarding."), category.label.lowercased()) }
            return String(format: L("%@ reported with %@ severity."), category.label, severity.label.lowercased())
        }()
        return (total, reason)
    }
}
