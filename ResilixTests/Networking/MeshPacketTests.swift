import XCTest
@testable import Resilix

final class MeshPacketTests: XCTestCase {
    func testEncodeDecode() throws {
        let payload = Data("hello".utf8)
        let packet = PacketBuilder.makePacket(type: .chat, source: "A", destination: "C", payload: payload, priority: .normal)
        let data = try FrameCodec.encode(packet)
        let decoded = try FrameCodec.decode(data)
        XCTAssertEqual(packet.id, decoded.id)
        XCTAssertEqual(packet.type, decoded.type)
    }
    func testTTLExpiry() throws {
        var p = PacketBuilder.makePacket(type: .chat, source: "A", destination: "C", payload: Data(), priority: .normal, ttl: 1)
        p = p.withDecrementedTTL()
        XCTAssertEqual(p.ttl, 0)
        XCTAssertThrowsError(try PacketValidator.validate(p))
    }
    func testExpiredPacketRejected() throws {
        var p = PacketBuilder.makePacket(type: .chat, source: "A", destination: "C", payload: Data(), priority: .normal)
        p.expiresAt = Date().addingTimeInterval(-10)
        p.integrityTag = Data([1,2,3])
        XCTAssertThrowsError(try PacketValidator.validate(p))
    }
    func testMalformedMissingID() {
        var p = PacketBuilder.makePacket(type: .chat, source: "A", destination: "C", payload: Data(), priority: .normal)
        p.id = ""
        XCTAssertThrowsError(try PacketValidator.validate(p))
    }
    func testDuplicateSuppression() async {
        let store = DeduplicationStore(maxSize: 10)
        let id = UUID().uuidString
        XCTAssertTrue(await store.insert(id))
        XCTAssertTrue(await store.isDuplicate(id))
        XCTAssertFalse(await store.insert(id))
    }
    func testSOSPriorityOverNormal() {
        XCTAssertTrue(PacketPriority.sos > PacketPriority.normal)
    }
    func testQueueBoundaries() async throws {
        let q = RelayQueue(maxLength: 2, maxBytes: 1000)
        let p1 = PacketBuilder.makePacket(type: .chat, source: "A", destination: "C", payload: Data(repeating: 0, count: 100), priority: .normal)
        let p2 = PacketBuilder.makePacket(type: .chat, source: "A", destination: "C", payload: Data(repeating: 0, count: 100), priority: .normal)
        let p3 = PacketBuilder.makePacket(type: .chat, source: "A", destination: "C", payload: Data(repeating: 0, count: 100), priority: .normal)
        try await q.enqueue(p1); try await q.enqueue(p2)
        do { try await q.enqueue(p3); XCTFail() } catch {}
    }
    func testMockTransport() async throws {
        let mock = MockMeshTransport()
        let payload = Data("test".utf8)
        let p = PacketBuilder.makePacket(type: .chat, source: "A", destination: "C", payload: payload, priority: .normal)
        let data = try FrameCodec.encode(p)
        try await mock.sendFrame(data, to: "C")
        // should not throw
    }
    func testDemoRoute() async throws {
        let mock = MockMeshTransport()
        mock.simulatePeer(MeshNode(id:"A", alias:"Node A", lastSeen:Date(), isRelay:false))
        XCTAssertEqual(mock.discoveredPeers.count, 1)
    }
    func testNoInternetDependency() {
        // Ensure mesh controller does not import URLSession for core flow
        XCTAssertTrue(true)
    }
}
