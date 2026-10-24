import Foundation

struct ResilixContact: Codable, Sendable, Equatable, Identifiable {
    var id: String // nodeID
    var displayName: String
    var alias: String
    var lastSeen: Date?
    var isTrusted: Bool
    var isReachable: Bool
    var isRelayReachable: Bool
}
