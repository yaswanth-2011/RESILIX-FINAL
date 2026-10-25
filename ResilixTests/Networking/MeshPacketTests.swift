import XCTest
@testable import Resilix

final class MeshPacketTests: XCTestCase {
    func testEncodeDecode() throws {
        let payload = Data("hello".utf8)
        let packet = makePacket(payload: payload)
        let data = try FrameCodec.encode(packet)
        let decoded = try FrameCodec.decode(data)
        XCTAssertEqual(packet.id, decoded.id)
        XCTAssertEqual(packet.type, decoded.type)
        XCTAssertEqual(packet.payloadEnvelope, decoded.payloadEnvelope)
    }

    func testTTLExpiry() throws {
        var packet = makePacket(ttl: 1)
        packet = packet.withDecrementedTTL()
        XCTAssertEqual(packet.ttl, 0)
        XCTAssertThrowsError(try PacketValidator.validate(packet))
    }

    func testExpiredPacketRejected() throws {
        var packet = makePacket()
        packet.expiresAt = Date().addingTimeInterval(-10)
        XCTAssertThrowsError(try PacketValidator.validate(packet))
    }

    func testMalformedMissingID() {
        var packet = makePacket()
        packet.id = ""
        XCTAssertThrowsError(try PacketValidator.validate(packet))
    }

    func testMalformedMissingOrigin() {
        var packet = makePacket()
        packet.originNodeID = ""
        XCTAssertThrowsError(try PacketValidator.validate(packet))
    }

    func testOversizedPayloadRejected() {
        var packet = makePacket()
        packet.payloadEnvelope = Data(repeating: 0, count: ResilixConstants.maxPacketSizeBytes + 1)
        XCTAssertThrowsError(try PacketValidator.validate(packet))
    }

    func testMissingIntegrityTagRejected() {
        var packet = makePacket()
        packet.integrityTag = Data()
        XCTAssertThrowsError(try PacketValidator.validate(packet))
    }

    func testHopLimitEnforced() {
        var packet = makePacket()
        packet.hopCount = ResilixConstants.maxHops + 1
        XCTAssertThrowsError(try PacketValidator.validate(packet))
    }

    func testVisitedListPreventsLoop() {
        var packet = makePacket()
        packet = packet.markedVisited(by: "B")
        XCTAssertTrue(packet.hasVisited("B"))
        XCTAssertFalse(packet.hasVisited("C"))
    }

    func testDuplicateSuppression() async {
        let store = DeduplicationStore(maxSize: 10)
        let id = UUID().uuidString
        let inserted = await store.insert(id)
        let duplicate = await store.isDuplicate(id)
        let insertedAgain = await store.insert(id)
        XCTAssertTrue(inserted)
        XCTAssertTrue(duplicate)
        XCTAssertFalse(insertedAgain)
    }

    func testSOSPriorityOverNormal() {
        XCTAssertTrue(PacketPriority.sos > PacketPriority.normal)
    }

    func testQueueBoundaries() async throws {
        let queue = RelayQueue(maxLength: 2, maxBytes: 1000)
        let payload = Data(repeating: 0, count: 100)
        // Distinct packets: `makePacket` mints a new identifier every call. Sending
        // the *same* packet twice is deduplicated by `enqueue`, which would leave
        // the queue below its limit and make the third call succeed.
        try await queue.enqueue(makePacket(payload: payload))
        try await queue.enqueue(makePacket(payload: payload))
        let count = await queue.count
        XCTAssertEqual(count, 2)
        do {
            try await queue.enqueue(makePacket(payload: payload))
            XCTFail("The queue must reject a third packet")
        } catch {
            XCTAssertTrue(error is ResilixError)
        }
    }

    func testMockTransport() async throws {
        let mock = MockMeshTransport()
        let packet = makePacket(payload: Data("test".utf8))
        let data = try FrameCodec.encode(packet)
        try await mock.sendFrame(data, to: "C")
    }

    func testMockTransportReportsPeers() {
        let mock = MockMeshTransport()
        mock.simulatePeer(MeshNode(id: "A", alias: "Node A", lastSeen: Date(), isRelay: false))
        XCTAssertEqual(mock.discoveredPeers.count, 1)
    }
}
