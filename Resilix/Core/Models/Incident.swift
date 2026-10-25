import Foundation

enum IncidentStatus: String, Codable, Sendable {
    case active, acknowledged, resolved, expired

    var label: String {
        switch self {
        case .active: return L("incident.status.active")
        case .acknowledged: return L("incident.status.acknowledged")
        case .resolved: return L("incident.status.resolved")
        case .expired: return L("incident.status.expired")
        }
    }
}

struct Incident: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var category: SOSCategory
    var severity: SOSSeverity
    var status: IncidentStatus
    var createdAt: Date
    var lastUpdateAt: Date
    var sourceNodeID: String
    var note: String?
    var latitude: Double?
    var longitude: Double?
    var routeSummary: String?
    var hops: Int?
    var acknowledged: Bool
    var version: Int
    var expiry: Date?
}
