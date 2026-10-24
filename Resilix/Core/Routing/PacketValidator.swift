import Foundation

enum PacketValidator {
    /// Validates the structure of an incoming packet.
    ///
    /// The function never traps: malformed input coming from a hostile peer
    /// is reported as an error, not as a crash.
    static func validate(_ packet: MeshPacket) throws {
        guard packet.version == ResilixConstants.protocolVersion else { throw ResilixError.unsupportedVersion }
        guard !packet.id.isEmpty else { throw ResilixError.packetMalformed("missing id") }
        guard !packet.sourceNodeID.isEmpty else { throw ResilixError.packetMalformed("missing source") }
        guard !packet.originNodeID.isEmpty else { throw ResilixError.packetMalformed("missing origin") }
        guard packet.ttl > 0 else { throw ResilixError.ttlExceeded }
        guard packet.hopCount <= Int(ResilixConstants.maxHops) else { throw ResilixError.ttlExceeded }
        guard !packet.isExpired else { throw ResilixError.packetExpired }
        guard packet.payloadEnvelope.count <= ResilixConstants.maxPacketSizeBytes else { throw ResilixError.packetTooLarge }
        guard !packet.integrityTag.isEmpty else { throw ResilixError.securityInvalidSignature }
    }
}
