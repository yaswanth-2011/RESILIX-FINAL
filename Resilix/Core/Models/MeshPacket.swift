import Foundation

enum MeshPacketType: String, Codable, Sendable, CaseIterable {
    case chat
    case sos = "sos"
    case acknowledgement
    case routeAdvertisement
    case capabilityAdvertisement
    case healthCheck
    case resourceReport
}

enum PacketPriority: Int, Codable, Sendable, Comparable, CaseIterable {
    case low = 0
    case normal = 1
    case high = 2
    case sos = 3
    public static func < (lhs: PacketPriority, rhs: PacketPriority) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct MeshPacket: Codable, Sendable, Equatable, Identifiable {
    var id: String // UUID string
    var version: UInt8
    var type: MeshPacketType
    var sourceNodeID: String
    var destinationNodeID: String // empty means broadcast
    var createdAt: Date
    var expiresAt: Date
    var ttl: UInt8
    var priority: PacketPriority
    var payloadEnvelope: Data // encrypted or plain codable data
    var integrityTag: Data // HMAC placeholder

    var isExpired: Bool { Date() > expiresAt }
    var isBroadcast: Bool { destinationNodeID.isEmpty }

    func withDecrementedTTL() -> MeshPacket {
        var c = self; if c.ttl > 0 { c.ttl -= 1 }; return c
    }
}
