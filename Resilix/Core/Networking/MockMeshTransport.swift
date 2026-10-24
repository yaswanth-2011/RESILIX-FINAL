import Foundation

/// In-process transport used by Demo Mode and by the unit tests.
///
/// It behaves like a radio that instantly delivers everything that is sent
/// to it, which makes it possible to exercise the full mesh pipeline (packet
/// building, validation, de-duplication, relaying, acknowledgement) on a
/// single device.
final class MockMeshTransport: MeshTransport, @unchecked Sendable {
    let transportKind: MeshTransportKind = .mock

    private let lock = NSLock()
    private var peers: [MeshNode] = []
    private var connected: Set<String> = []
    private var hellos: [String: PeerHello] = [:]

    private var frameCont: AsyncStream<(Data, String)>.Continuation?
    private var eventCont: AsyncStream<MeshTransportEvent>.Continuation?
    private let frameStream: AsyncStream<(Data, String)>
    private let eventStream: AsyncStream<MeshTransportEvent>

    init() {
        var fc: AsyncStream<(Data, String)>.Continuation?
        frameStream = AsyncStream { fc = $0 }
        frameCont = fc
        var ec: AsyncStream<MeshTransportEvent>.Continuation?
        eventStream = AsyncStream { ec = $0 }
        eventCont = ec
    }

    deinit {
        frameCont?.finish()
        eventCont?.finish()
    }

    var isAvailable: Bool { true }

    var discoveredPeers: [MeshNode] {
        lock.lock(); defer { lock.unlock() }
        return peers
    }

    var connectedPeerIDs: Set<String> {
        lock.lock(); defer { lock.unlock() }
        return connected
    }

    func configure(nodeID: String, alias: String, hello: PeerHello) async {}

    func peerHello(for peerID: String) -> PeerHello? {
        lock.lock(); defer { lock.unlock() }
        return hellos[peerID]
    }

    func startDiscovery() async {}
    func stopDiscovery() async {}

    func connect(to peerID: String) async throws {
        lock.lock()
        connected.insert(peerID)
        lock.unlock()
        eventCont?.yield(.connected(id: peerID))
    }

    func disconnect(from peerID: String) async {
        lock.lock()
        connected.remove(peerID)
        lock.unlock()
        eventCont?.yield(.disconnected(id: peerID))
    }

    func sendFrame(_ data: Data, to peerID: String) async throws {
        try? await Task.sleep(nanoseconds: 20_000_000)
        frameCont?.yield((data, peerID))
    }

    func receivedFrames() -> AsyncStream<(Data, String)> { frameStream }
    func connectionEvents() -> AsyncStream<MeshTransportEvent> { eventStream }

    // MARK: - Simulation helpers

    func simulatePeer(_ node: MeshNode) {
        lock.lock()
        if !peers.contains(where: { $0.id == node.id }) { peers.append(node) }
        lock.unlock()
        eventCont?.yield(.peerDiscovered(id: node.id, alias: node.alias))
    }

    func simulateHello(_ hello: PeerHello) {
        lock.lock()
        hellos[hello.nodeID] = hello
        if !peers.contains(where: { $0.id == hello.nodeID }) {
            peers.append(MeshNode(id: hello.nodeID, alias: hello.alias, lastSeen: Date(), isRelay: hello.supportsRelay))
        }
        lock.unlock()
        eventCont?.yield(.peerDiscovered(id: hello.nodeID, alias: hello.alias))
    }

    func simulateIncoming(_ data: Data, from peerID: String) {
        frameCont?.yield((data, peerID))
    }

    func simulateDisconnect(_ peerID: String) {
        lock.lock()
        connected.remove(peerID)
        lock.unlock()
        eventCont?.yield(.disconnected(id: peerID))
    }
}
