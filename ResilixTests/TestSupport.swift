import Foundation
import XCTest
@testable import Resilix

/// Factory for the packets used by the tests.
func makePacket(type: MeshPacketType = .chat,
                source: String = "A",
                destination: String = "C",
                payload: Data = Data(),
                priority: PacketPriority = .normal,
                ttl: UInt8 = ResilixConstants.defaultTTL,
                expiry: TimeInterval = ResilixConstants.packetExpirySeconds,
                integrityTag: Data = Data([1, 2, 3])) -> MeshPacket {
    MeshPacket(id: UUID().uuidString,
               version: ResilixConstants.protocolVersion,
               type: type,
               sourceNodeID: source,
               destinationNodeID: destination,
               createdAt: Date(),
               expiresAt: Date().addingTimeInterval(expiry),
               ttl: ttl,
               priority: priority,
               payloadEnvelope: payload,
               integrityTag: integrityTag)
}
