import Foundation
import CryptoKit

enum PacketBuilder {
    static func makePacket(type: MeshPacketType, source: String, destination: String, payload: Data, priority: PacketPriority, ttl: UInt8 = ResilixConstants.defaultTTL, expiry: TimeInterval = ResilixConstants.packetExpirySeconds) -> MeshPacket {
        let now = Date()
        let packet = MeshPacket(
            id: UUID().uuidString,
            version: ResilixConstants.protocolVersion,
            type: type,
            sourceNodeID: source,
            destinationNodeID: destination,
            createdAt: now,
            expiresAt: now.addingTimeInterval(expiry),
            ttl: ttl,
            priority: priority,
            payloadEnvelope: payload,
            integrityTag: hmac(for: payload)
        )
        return packet
    }
    static func hmac(for data: Data) -> Data {
        // Use SHA256 as placeholder for HMAC; real would use symmetric key
        let hash = SHA256.hash(data: data)
        return Data(hash)
    }
}
