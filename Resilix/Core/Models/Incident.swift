import Foundation

enum IncidentStatus: String, Codable, Sendable { case active, acknowledged, resolved, expired }

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
