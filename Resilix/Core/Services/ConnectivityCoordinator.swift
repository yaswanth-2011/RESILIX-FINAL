import Foundation

@MainActor
class ConnectivityCoordinator: ObservableObject {
    private let transports: [any MeshTransport]
    init(transports: [any MeshTransport]) { self.transports = transports }
    func startAll() async { for t in transports { await t.startDiscovery() } }
    func stopAll() async { for t in transports { await t.stopDiscovery() } }
}
