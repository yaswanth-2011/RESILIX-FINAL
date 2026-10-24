import Foundation

/// The kind of payload a packet carries.
enum MeshPacketType: String, Codable, Sendable, CaseIterable {
    case chat
    case sos = "sos"
    case acknowledgement
    case routeAdvertisement
    case capabilityAdvertisement
    case healthCheck
    case resourceReport
    /// One chunk of a media transfer.
    case mediaChunk
    /// Start / cancel / acknowledge a media transfer.
    case mediaControl
}

/// Priority of a packet. SOS packets are always forwarded first.
enum PacketPriority: Int, Codable, Sendable, Comparable, CaseIterable {
    case low = 0
    case normal = 1
    case high = 2
    case sos = 3
    public static func < (lhs: PacketPriority, rhs: PacketPriority) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The unit of exchange between Resilix nodes.
///
/// A packet is the only thing that ever travels over a transport. Chat
/// messages, acknowledgements, route advertisements, capability
/// advertisements and media transfer control blocks are all packets with a
/// different `type` and payload.
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
    var integrityTag: Data // HMAC-SHA256 over the canonical header + payload

    // MARK: - Routing metadata
    /// Node that originally created the packet (unchanged while relaying).
    var originNodeID: String
    /// Number of hops the packet already travelled.
    var hopCount: Int
    /// Nodes that already handled this packet (loop prevention).
    var visited: [String]
    /// Identifier of the encrypted session the payload belongs to (if any).
    var sessionID: String?

    var isExpired: Bool { Date() > expiresAt }
    var isBroadcast: Bool { destinationNodeID.isEmpty }

    init(id: String = UUID().uuidString,
         version: UInt8 = ResilixConstants.protocolVersion,
         type: MeshPacketType,
         sourceNodeID: String,
         destinationNodeID: String,
         createdAt: Date = Date(),
         expiresAt: Date,
         ttl: UInt8 = ResilixConstants.defaultTTL,
         priority: PacketPriority = .normal,
         payloadEnvelope: Data,
         integrityTag: Data,
         originNodeID: String? = nil,
         hopCount: Int = 0,
         visited: [String] = [],
         sessionID: String? = nil) {
        self.id = id
        self.version = version
        self.type = type
        self.sourceNodeID = sourceNodeID
        self.destinationNodeID = destinationNodeID
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.ttl = ttl
        self.priority = priority
        self.payloadEnvelope = payloadEnvelope
        self.integrityTag = integrityTag
        self.originNodeID = originNodeID ?? sourceNodeID
        self.hopCount = hopCount
        self.visited = visited
        self.sessionID = sessionID
    }

    /// Decoding is tolerant so packets written by older protocol revisions
    /// can still be inspected (and rejected) instead of crashing the node.
    private enum CodingKeys: String, CodingKey {
        case id, version, type, sourceNodeID, destinationNodeID, createdAt, expiresAt
        case ttl, priority, payloadEnvelope, integrityTag
        case originNodeID, hopCount, visited, sessionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        version = try container.decodeIfPresent(UInt8.self, forKey: .version) ?? ResilixConstants.protocolVersion
        type = try container.decodeIfPresent(MeshPacketType.self, forKey: .type) ?? .healthCheck
        sourceNodeID = try container.decodeIfPresent(String.self, forKey: .sourceNodeID) ?? ""
        destinationNodeID = try container.decodeIfPresent(String.self, forKey: .destinationNodeID) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt) ?? createdAt.addingTimeInterval(ResilixConstants.packetExpirySeconds)
        ttl = try container.decodeIfPresent(UInt8.self, forKey: .ttl) ?? 0
        priority = try container.decodeIfPresent(PacketPriority.self, forKey: .priority) ?? .normal
        payloadEnvelope = try container.decodeIfPresent(Data.self, forKey: .payloadEnvelope) ?? Data()
        integrityTag = try container.decodeIfPresent(Data.self, forKey: .integrityTag) ?? Data()
        originNodeID = try container.decodeIfPresent(String.self, forKey: .originNodeID) ?? sourceNodeID
        hopCount = try container.decodeIfPresent(Int.self, forKey: .hopCount) ?? 0
        visited = try container.decodeIfPresent([String].self, forKey: .visited) ?? []
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
    }

    func withDecrementedTTL() -> MeshPacket {
        var c = self
        if c.ttl > 0 { c.ttl -= 1 }
        c.hopCount += 1
        return c
    }

    /// Marks the packet as handled by `nodeID` (loop prevention).
    func markedVisited(by nodeID: String) -> MeshPacket {
        var c = self
        if !c.visited.contains(nodeID) { c.visited.append(nodeID) }
        return c
    }

    func hasVisited(_ nodeID: String) -> Bool { visited.contains(nodeID) }
}
