import Foundation

enum MeshTransportEvent: Sendable, Equatable {
    case peerDiscovered(id: String, alias: String)
    case peerLost(id: String)
    case connected(id: String)
    case disconnected(id: String)
    case error(String)
}

protocol MeshTransport: AnyObject, Sendable {
    var transportKind: MeshTransportKind { get }
    var isAvailable: Bool { get }
    var discoveredPeers: [MeshNode] { get }
    func startDiscovery() async
    func stopDiscovery() async
    func connect(to peerID: String) async throws
    func disconnect(from peerID: String) async
    func sendFrame(_ data: Data, to peerID: String) async throws
    func receivedFrames() -> AsyncStream<(Data, String)>
    func connectionEvents() -> AsyncStream<MeshTransportEvent>
}
