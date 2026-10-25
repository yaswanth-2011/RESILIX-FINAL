import Foundation

enum DemoDataFactory {
    static let nodeA = DemoNode(id: "A", label: L("Source"), alias: "Node A")
    static let nodeB = DemoNode(id: "B", label: L("Relay"), alias: "Relay B")
    static let nodeC = DemoNode(id: "C", label: L("Destination"), alias: "Node C")

    static let messages: [MeshMessage] = [
        MeshMessage(id: "m1", packetID: "p1", threadID: "C", sourceNodeID: "A", destinationNodeID: "C", text: L("Need help at the north shelter"), createdAt: Date().addingTimeInterval(-300), deliveryState: .delivered, expirySeconds: nil, lastRoute: "A -> B -> C", priority: .normal),
        MeshMessage(id: "m2", packetID: "p2", threadID: "B", sourceNodeID: "A", destinationNodeID: "B", text: L("Water supplies low near sector 7"), createdAt: Date().addingTimeInterval(-600), deliveryState: .delivered, expirySeconds: nil, lastRoute: "A -> B", priority: .normal),
    ]
    static let queued = MeshMessage(id: "m3", packetID: "p3", threadID: "C", sourceNodeID: "A", destinationNodeID: "C", text: L("Queued message awaiting route"), createdAt: Date(), deliveryState: .queued, expirySeconds: 300, lastRoute: nil, priority: .normal)

    static let sos = Incident(id: "sos1", category: .medical, severity: .critical, status: .active, createdAt: Date().addingTimeInterval(-200), lastUpdateAt: Date(), sourceNodeID: "A", note: L("Injured hiker near ridge"), latitude: 37.7749, longitude: -122.4194, routeSummary: "A -> B -> C", hops: 2, acknowledged: false, version: 1, expiry: Date().addingTimeInterval(3600))

    static let resources: [MapResource] = [
        MapResource(id: "r1", category: .shelter, title: L("North Shelter"), notes: L("Capacity 40, demo"), latitude: 37.78, longitude: -122.42, createdAt: Date().addingTimeInterval(-3600), lastVerifiedAt: Date(), verification: .verified, sourceNodeID: "B", isDemo: true),
        MapResource(id: "r2", category: .water, title: L("Water point"), notes: L("Community reported"), latitude: 37.77, longitude: -122.41, createdAt: Date().addingTimeInterval(-7200), lastVerifiedAt: nil, verification: .communityReported, sourceNodeID: "A", isDemo: true),
        MapResource(id: "r3", category: .hazard, title: L("Blocked road"), notes: L("Stale report"), latitude: 37.76, longitude: -122.43, createdAt: Date().addingTimeInterval(-86400*2), lastVerifiedAt: Date().addingTimeInterval(-86400*2), verification: .unverified, sourceNodeID: nil, isDemo: true),
    ]

    static let route2Hop = MeshRoute(destination: "C", nextHop: "B", hopCount: 2, transport: .peerToPeerWiFi, quality: .stable, freshness: Date(), failureScore: 0, hops: [RouteHop(nodeID: "A", transport: .peerToPeerWiFi, quality: .stable), RouteHop(nodeID: "B", transport: .bluetooth, quality: .stable), RouteHop(nodeID: "C", transport: .peerToPeerWiFi, quality: .stable)])
    static let route3Hop = MeshRoute(destination: "D", nextHop: "B", hopCount: 3, transport: .bluetooth, quality: .degraded, freshness: Date(), failureScore: 1, hops: [RouteHop(nodeID: "A", transport: .bluetooth, quality: .stable), RouteHop(nodeID: "B", transport: .bluetooth, quality: .degraded), RouteHop(nodeID: "C", transport: .bluetooth, quality: .stable), RouteHop(nodeID: "D", transport: .peerToPeerWiFi, quality: .unknown)])
}
