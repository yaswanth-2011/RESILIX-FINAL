import Foundation
import Combine

/// Distance-vector routing for the mesh.
///
/// Every node advertises the destinations it knows about together with the
/// number of hops. A node that receives an advertisement from a neighbour
/// learns a route whose *next hop* is that neighbour. Because the
/// advertisement travels hop by hop, a device that cannot reach the
/// destination directly still learns a multi hop path through a relay.
///
/// The engine deliberately keeps the algorithm small and predictable:
///
/// * routes expire after `ResilixConstants.routeExpirySeconds`;
/// * a failed transmission raises a penalty for the next hop, a successful
///   one lowers it again (so a broken link is avoided quickly);
/// * a new route replaces an existing one only when it is clearly better
///   (hysteresis) which avoids route flapping.
@MainActor
class MeshRoutingEngine: ObservableObject {
    @Published private(set) var routes: [MeshRoute] = []
    @Published private(set) var neighbours: [String: MeshNode] = [:]

    private let routeTable = RouteTable()
    private var failurePenalties: [String: Int] = [:]
    private var localNodeID: String = ""
    private var localAlias: String = ""
    private var localSupportsRelay: Bool = true
    /// When disabled only direct neighbours are used as next hop.
    var automaticRoutingEnabled: Bool = true

    // MARK: - Configuration

    func configure(localNodeID: String, alias: String, supportsRelay: Bool) {
        self.localNodeID = localNodeID
        self.localAlias = alias
        self.localSupportsRelay = supportsRelay
    }

    // MARK: - Scoring

    /// Deterministic route scoring - unit testable. Lower is better.
    /// Pure scoring function: `nonisolated` so it can be used from tests and
    /// from background contexts without hopping to the main actor.
    nonisolated static func scoreRoute(_ route: MeshRoute, failurePenalty: Int = 0) -> Double {
        let hopCost = Double(route.hopCount) * 10
        let qualityCost: Double = {
            switch route.quality {
            case .stable: return 0
            case .degraded: return 8
            case .unknown: return 4
            case .unavailable: return 100
            }
        }()
        let freshnessCost = Date().timeIntervalSince(route.freshness) / 60.0 // 1 per minute
        let failureCost = Double(failurePenalty) * 5
        return hopCost + qualityCost + freshnessCost + failureCost
    }

    // MARK: - Neighbours

    func registerNeighbour(_ node: MeshNode, transport: MeshTransportKind, quality: LinkQuality) async {
        neighbours[node.id] = node
        let route = MeshRoute(destination: node.id,
                              nextHop: node.id,
                              hopCount: 1,
                              transport: transport,
                              quality: quality,
                              freshness: Date(),
                              failureScore: 0,
                              hops: [RouteHop(nodeID: node.id, transport: transport, quality: quality)])
        await routeTable.upsert(route)
        await publishRoutes()
    }

    func removeNeighbour(id: String) async {
        neighbours.removeValue(forKey: id)
        await routeTable.remove(destination: id)
        await routeTable.removeRoutes(via: id)
        await publishRoutes()
    }

    // MARK: - Route updates

    func upsert(route: MeshRoute) async {
        await routeTable.upsert(route)
        routes = await routeTable.allRoutes()
    }

    func removeRoutes(via peerID: String) async {
        await routeTable.removeRoutes(via: peerID)
        routes = await routeTable.allRoutes()
    }

    func expireStale() async {
        await routeTable.expireStale()
        routes = await routeTable.allRoutes()
    }

    func recordFailure(peerID: String) {
        let current = failurePenalties[peerID] ?? 0
        failurePenalties[peerID] = min(current + 1, 10)
    }

    func recordSuccess(peerID: String) {
        let current = failurePenalties[peerID] ?? 1
        failurePenalties[peerID] = max(current - 1, 0)
    }

    func hysteresisShouldSwitch(from old: MeshRoute, to new: MeshRoute) -> Bool {
        let sOld = Self.scoreRoute(old, failurePenalty: failurePenalties[old.nextHop] ?? 0)
        let sNew = Self.scoreRoute(new, failurePenalty: failurePenalties[new.nextHop] ?? 0)
        return sNew + 3 < sOld // need a 3 point improvement
    }

    // MARK: - Lookup

    func bestRoute(to destination: String) async -> MeshRoute? {
        await expireStale()
        guard let route = await routeTable.route(to: destination) else { return nil }
        if !automaticRoutingEnabled && route.hopCount > 1 { return nil }
        return route
    }

    func routeHops(to destination: String) async -> [RouteHop] {
        await bestRoute(to: destination)?.hops ?? []
    }

    // MARK: - Distance vector exchange

    /// Merges an advertisement received from `peerID`.
    ///
    /// The sender advertises "I reach X in N hops", therefore the route to X
    /// through that neighbour has N + 1 hops.
    func merge(advertisement: RouteAdvertisement, from peerID: String) async {
        for entry in advertisement.entries {
            guard entry.destination != localNodeID else { continue }
            let candidate = MeshRoute(destination: entry.destination,
                                      nextHop: peerID,
                                      hopCount: entry.hopCount + 1,
                                      transport: neighbours[peerID] != nil ? .peerToPeerWiFi : .bluetooth,
                                      quality: entry.quality,
                                      freshness: Date(),
                                      failureScore: 0,
                                      hops: [RouteHop(nodeID: peerID, transport: .peerToPeerWiFi, quality: entry.quality)])
            if let existing = await routeTable.route(to: entry.destination) {
                guard hysteresisShouldSwitch(from: existing, to: candidate)
                        || existing.nextHop == peerID else { continue }
            }
            await routeTable.upsert(candidate)
        }
        await publishRoutes()
    }

    /// Builds the advertisement that is sent to `peerID`.
    ///
    /// Split horizon: routes that already use `peerID` as next hop are not
    /// advertised back to it, which prevents routing loops.
    func advertisement(for peerID: String?) -> RouteAdvertisement {
        let entries = routes.compactMap { route -> RouteEntry? in
            guard route.destination != localNodeID else { return nil }
            if let peerID, route.nextHop == peerID { return nil }
            return RouteEntry(destination: route.destination, hopCount: route.hopCount, quality: route.quality)
        }
        return RouteAdvertisement(nodeID: localNodeID,
                                  alias: localAlias,
                                  supportsRelay: localSupportsRelay,
                                  entries: entries)
    }

    private func publishRoutes() async {
        routes = await routeTable.allRoutes()
    }
}
