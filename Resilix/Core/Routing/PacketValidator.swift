import Foundation

enum PacketValidator {
    static func validate(_ packet: MeshPacket) throws {
        guard packet.version == ResilixConstants.protocolVersion else { throw ResilixError.unsupportedVersion }
        guard !packet.id.isEmpty else { throw ResilixError.packetMalformed("missing id") }
        guard !packet.sourceNodeID.isEmpty else { throw ResilixError.packetMalformed("missing source") }
        guard packet.ttl > 0 else { throw ResilixError.ttlExceeded }
        guard !packet.isExpired else { throw ResilixError.packetExpired }
        guard packet.payloadEnvelope.count <= ResilixConstants.maxPacketSizeBytes else { throw ResilixError.packetTooLarge }
        // integrity placeholder: ensure tag non-empty
        guard !packet.integrityTag.isEmpty else { throw ResilixError.securityInvalidSignature }
    }
}
