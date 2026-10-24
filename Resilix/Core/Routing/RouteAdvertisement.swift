import Foundation

/// One entry of a distance-vector route advertisement.
///
/// The sender advertises "I can reach `destination` in `hopCount` hops".
/// The receiver turns that into a route whose next hop is the sender.
struct RouteEntry: Codable, Sendable, Equatable {
    var destination: String
    var hopCount: Int
    var quality: LinkQuality
}

/// Payload of a `routeAdvertisement` packet.
struct RouteAdvertisement: Codable, Sendable, Equatable {
    var nodeID: String
    var alias: String
    var supportsRelay: Bool
    var entries: [RouteEntry]

    init(nodeID: String, alias: String, supportsRelay: Bool, entries: [RouteEntry] = []) {
        self.nodeID = nodeID
        self.alias = alias
        self.supportsRelay = supportsRelay
        self.entries = entries
    }
}
