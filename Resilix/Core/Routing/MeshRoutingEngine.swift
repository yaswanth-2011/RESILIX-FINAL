import Foundation

@MainActor
class MeshRoutingEngine: ObservableObject {
    @Published private(set) var routes: [MeshRoute] = []
    private let routeTable = RouteTable()
    private let peerRegistry = MeshPeerRegistry()
    private var failurePenalties: [String: (score:Int, lastFail:Date)] = [:]

    // Deterministic route scoring - unit testable
    static func scoreRoute(_ route: MeshRoute, failurePenalty: Int = 0) -> Double {
        // lower is better
        let hopCost = Double(route.hopCount) * 10
        let qualityCost: Double = {
            switch route.quality { case .stable: return 0; case .degraded: return 8; case .unknown: return 4; case .unavailable: return 100 }
        }()
        let freshnessCost = Date().timeIntervalSince(route.freshness) / 60.0 // 1 per minute
        let failureCost = Double(failurePenalty) * 5
        return hopCost + qualityCost + freshnessCost + failureCost
    }

    func bestRoute(to destination: String) async -> MeshRoute? {
        let all = await routeTable.allRoutes()
        let candidates = all.filter { $0.destination == destination && !$0.isExpired }
        guard !candidates.isEmpty else { return nil }
        return candidates.min { Self.scoreRoute($0, failurePenalty: failurePenalties[$0.nextHop]?.score ?? 0) < Self.scoreRoute($1, failurePenalty: failurePenalties[$1.nextHop]?.score ?? 0) }
    }

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
        let cur = failurePenalties[peerID]?.score ?? 0
        failurePenalties[peerID] = (min(cur+1, 10), Date())
    }
    func recordSuccess(peerID: String) {
        failurePenalties[peerID] = (max((failurePenalties[peerID]?.score ?? 1)-1,0), Date())
    }
    func hysteresisShouldSwitch(from old: MeshRoute, to new: MeshRoute) -> Bool {
        let sOld = Self.scoreRoute(old, failurePenalty: failurePenalties[old.nextHop]?.score ?? 0)
        let sNew = Self.scoreRoute(new, failurePenalty: failurePenalties[new.nextHop]?.score ?? 0)
        return sNew + 3 < sOld // need 3 point improvement
    }
}
