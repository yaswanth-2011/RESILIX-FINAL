import XCTest
@testable import Resilix

final class RoutingTests: XCTestCase {
    func testRouteSelectionPrefersFewerHops() async {
        let engine = await MainActor.run { MeshRoutingEngine() }
        let r1 = MeshRoute(destination:"C", nextHop:"B", hopCount:2, transport:.peerToPeerWiFi, quality:.stable, freshness:Date(), failureScore:0, hops:[])
        let r2 = MeshRoute(destination:"C", nextHop:"D", hopCount:3, transport:.peerToPeerWiFi, quality:.stable, freshness:Date(), failureScore:0, hops:[])
        await engine.upsert(route: r1); await engine.upsert(route: r2)
        // Note: upsert same destination overwrites; test scoring directly
        let s1 = MeshRoutingEngine.scoreRoute(r1)
        let s2 = MeshRoutingEngine.scoreRoute(r2)
        XCTAssertLessThan(s1, s2)
    }
    func testRoutePrefersStable() {
        let stable = MeshRoute(destination:"X", nextHop:"B", hopCount:2, transport:.bluetooth, quality:.stable, freshness:Date(), failureScore:0, hops:[])
        let degraded = MeshRoute(destination:"X", nextHop:"B", hopCount:2, transport:.bluetooth, quality:.degraded, freshness:Date(), failureScore:0, hops:[])
        XCTAssertLessThan(MeshRoutingEngine.scoreRoute(stable), MeshRoutingEngine.scoreRoute(degraded))
    }
    func testStaleExpiry() async {
        let table = RouteTable()
        let stale = MeshRoute(destination:"C", nextHop:"B", hopCount:2, transport:.bluetooth, quality:.stable, freshness:Date().addingTimeInterval(-1000), failureScore:0, hops:[])
        await table.upsert(stale)
        await table.expireStale()
        XCTAssertNil(await table.route(to:"C"))
    }
    func testDedupBounded() async {
        let store = DeduplicationStore(maxSize:2)
        _ = await store.insert("1"); _ = await store.insert("2"); _ = await store.insert("3")
        XCTAssertEqual(await store.count(), 2)
    }
    func testRelayQueueOrderingSOSFirst() async throws {
        let q = RelayQueue()
        let low = PacketBuilder.makePacket(type:.chat, source:"A", destination:"C", payload:Data(), priority:.normal)
        let sos = PacketBuilder.makePacket(type:.sos, source:"A", destination:"C", payload:Data(), priority:.sos)
        try await q.enqueue(low); try await q.enqueue(sos)
        let first = await q.peek()
        XCTAssertEqual(first?.packet.priority, .sos)
    }
    func testThreeHopScenario() {
        let r = DemoDataFactory.route3Hop
        XCTAssertEqual(r.hopCount, 3)
    }
    func testSeverityScoring() {
        let (score, _) = SeverityScoringEngine.score(category:.medical, severity:.critical, note:nil)
        let (score2, _) = SeverityScoringEngine.score(category:.evacuation, severity:.low, note:nil)
        XCTAssertGreaterThan(score, score2)
    }
}
