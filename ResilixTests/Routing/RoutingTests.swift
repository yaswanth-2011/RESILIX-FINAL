import XCTest
@testable import Resilix

final class RoutingTests: XCTestCase {
    func testRouteSelectionPrefersFewerHops() {
        let short = MeshRoute(destination: "C", nextHop: "B", hopCount: 2, transport: .peerToPeerWiFi, quality: .stable, freshness: Date(), failureScore: 0, hops: [])
        let long = MeshRoute(destination: "C", nextHop: "D", hopCount: 3, transport: .peerToPeerWiFi, quality: .stable, freshness: Date(), failureScore: 0, hops: [])
        XCTAssertLessThan(MeshRoutingEngine.scoreRoute(short), MeshRoutingEngine.scoreRoute(long))
    }

    func testRoutePrefersStable() {
        let stable = MeshRoute(destination: "X", nextHop: "B", hopCount: 2, transport: .bluetooth, quality: .stable, freshness: Date(), failureScore: 0, hops: [])
        let degraded = MeshRoute(destination: "X", nextHop: "B", hopCount: 2, transport: .bluetooth, quality: .degraded, freshness: Date(), failureScore: 0, hops: [])
        XCTAssertLessThan(MeshRoutingEngine.scoreRoute(stable), MeshRoutingEngine.scoreRoute(degraded))
    }

    func testFailurePenaltyIsAvoided() {
        let route = MeshRoute(destination: "X", nextHop: "B", hopCount: 2, transport: .bluetooth, quality: .stable, freshness: Date(), failureScore: 0, hops: [])
        XCTAssertGreaterThan(MeshRoutingEngine.scoreRoute(route, failurePenalty: 3),
                             MeshRoutingEngine.scoreRoute(route))
    }

    func testStaleExpiry() async {
        let table = RouteTable()
        let stale = MeshRoute(destination: "C", nextHop: "B", hopCount: 2, transport: .bluetooth, quality: .stable, freshness: Date().addingTimeInterval(-1000), failureScore: 0, hops: [])
        await table.upsert(stale)
        await table.expireStale()
        let expiredRoute = await table.route(to: "C")
        XCTAssertNil(expiredRoute)
    }

    func testDedupBounded() async {
        let store = DeduplicationStore(maxSize: 2)
        _ = await store.insert("1")
        _ = await store.insert("2")
        _ = await store.insert("3")
        let remaining = await store.count()
        XCTAssertEqual(remaining, 2)
    }

    func testRelayQueueOrderingSOSFirst() async throws {
        let queue = RelayQueue()
        let low = makePacket(type: .chat, priority: .normal)
        let sos = makePacket(type: .sos, priority: .sos)
        try await queue.enqueue(low)
        try await queue.enqueue(sos)
        let first = await queue.peek()
        XCTAssertEqual(first?.packet.priority, .sos)
    }

    func testRelayQueuePersistsAcrossInstances() async throws {
        let queue = RelayQueue()
        try await queue.enqueue(makePacket())
        await queue.persist()

        let restored = RelayQueue()
        let count = await restored.restore()
        XCTAssertGreaterThanOrEqual(count, 1)
    }

    func testRelayQueueRemovesDeliveredPacket() async throws {
        let queue = RelayQueue()
        let packet = makePacket()
        try await queue.enqueue(packet)
        await queue.dequeueMatching(id: packet.id)
        let remaining = await queue.count
        XCTAssertEqual(remaining, 0)
    }

    func testHopLimitStopsForwarding() {
        var packet = makePacket(ttl: 1)
        packet = packet.withDecrementedTTL()
        XCTAssertEqual(packet.ttl, 0)
        XCTAssertThrowsError(try PacketValidator.validate(packet))
    }

    func testThreeHopScenario() {
        let route = DemoDataFactory.route3Hop
        XCTAssertEqual(route.hopCount, 3)
    }

    func testSeverityScoring() {
        let (score, _) = SeverityScoringEngine.score(category: .medical, severity: .critical, note: nil)
        let (score2, _) = SeverityScoringEngine.score(category: .evacuation, severity: .low, note: nil)
        XCTAssertGreaterThan(score, score2)
    }
}
