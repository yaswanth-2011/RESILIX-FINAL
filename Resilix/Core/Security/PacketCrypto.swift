import Foundation
import CryptoKit

/// Canonical byte representation of a packet.
///
/// The signature covers every field that a relay could use to change the
/// meaning of a packet (destination, TTL, priority, expiry, payload) so a
/// malicious relay cannot rewrite or replay a message.
enum PacketCrypto {
    static func canonicalBytes(_ packet: MeshPacket) -> Data {
        // NOTE: the TTL, the hop counter and the visited list are *not*
        // covered by the signature on purpose: a relay has to be able to
        // decrement the TTL and to record its own hop without being able to
        // forge the origin's signature. Everything that changes the meaning
        // of the packet for the receiver is covered.
        let header = [
            packet.id,
            String(packet.version),
            packet.type.rawValue,
            packet.sourceNodeID,
            packet.destinationNodeID,
            packet.originNodeID,
            String(packet.createdAt.timeIntervalSince1970),
            String(packet.expiresAt.timeIntervalSince1970),
            String(packet.priority.rawValue),
            String(packet.payloadEnvelope.count)
        ].joined(separator: "|")
        var data = Data(header.utf8)
        data.append(SHA256.hash(data: packet.payloadEnvelope))
        return data
    }

    /// Hex encoded SHA-256 of a payload (used for media integrity checks).
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
