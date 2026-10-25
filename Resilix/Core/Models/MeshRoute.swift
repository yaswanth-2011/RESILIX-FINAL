import Foundation

enum LinkQuality: String, Codable, Sendable {
    case unknown, stable, degraded, unavailable
    var label: String {
        switch self {
        case .unknown: return L("link.quality.unknown")
        case .stable: return L("link.quality.stable")
        case .degraded: return L("link.quality.degraded")
        case .unavailable: return L("link.quality.unavailable")
        }
    }
}

struct RouteHop: Codable, Sendable, Equatable, Hashable {
    var nodeID: String
    var transport: MeshTransportKind
    var quality: LinkQuality
}

struct MeshRoute: Codable, Sendable, Equatable, Identifiable {
    var id: String { destination + ">" + nextHop }
    var destination: String
    var nextHop: String
    var hopCount: Int
    var transport: MeshTransportKind
    var quality: LinkQuality
    var freshness: Date
    var failureScore: Int
    var hops: [RouteHop]

    var isExpired: Bool { Date().timeIntervalSince(freshness) > ResilixConstants.routeExpirySeconds }
}
