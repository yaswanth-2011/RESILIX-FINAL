import Foundation

actor RouteTable {
    private var routes: [String: MeshRoute] = [:]
    func upsert(_ route: MeshRoute) { routes[route.destination] = route }
    func remove(destination: String) { routes.removeValue(forKey: destination) }
    func route(to destination: String) -> MeshRoute? { routes[destination] }
    func allRoutes() -> [MeshRoute] { Array(routes.values) }
    func expireStale() {
        routes = routes.filter { !$0.value.isExpired }
    }
    func removeRoutes(via peerID: String) {
        routes = routes.filter { $0.value.nextHop != peerID }
    }
}
