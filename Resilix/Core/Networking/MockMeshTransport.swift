import Foundation

final class MockMeshTransport: MeshTransport, @unchecked Sendable {
    let transportKind: MeshTransportKind = .mock
    var isAvailable: Bool { true }
    private var peers: [MeshNode] = []
    private var frameContinuation: AsyncStream<(Data,String)>.Continuation?
    private var eventContinuation: AsyncStream<MeshTransportEvent>.Continuation?
    private var frameStream: AsyncStream<(Data,String)>
    private var eventStream: AsyncStream<MeshTransportEvent>
    private var simulatedPeers: [String: MeshNode] = [:]
    var discoveredPeers: [MeshNode] { peers }

    init() {
        var fc: AsyncStream<(Data,String)>.Continuation?
        frameStream = AsyncStream { fc = $0 }
        frameContinuation = fc
        var ec: AsyncStream<MeshTransportEvent>.Continuation?
        eventStream = AsyncStream { ec = $0 }
        eventContinuation = ec
    }

    func startDiscovery() async {}
    func stopDiscovery() async {}
    func connect(to peerID: String) async throws {
        eventContinuation?.yield(.connected(id: peerID))
    }
    func disconnect(from peerID: String) async {
        eventContinuation?.yield(.disconnected(id: peerID))
    }
    func sendFrame(_ data: Data, to peerID: String) async throws {
        try? await Task.sleep(nanoseconds: 50_000_000)
        frameContinuation?.yield((data, peerID))
    }
    func receivedFrames() -> AsyncStream<(Data, String)> { frameStream }
    func connectionEvents() -> AsyncStream<MeshTransportEvent> { eventStream }

    func simulatePeer(_ node: MeshNode) {
        peers.append(node)
        simulatedPeers[node.id] = node
        eventContinuation?.yield(.peerDiscovered(id: node.id, alias: node.alias))
    }
    func simulateIncoming(_ data: Data, from peerID: String) {
        frameContinuation?.yield((data, peerID))
    }
}
