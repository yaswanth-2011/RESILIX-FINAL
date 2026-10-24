import Foundation
import Network

final class PeerToPeerWiFiTransport: MeshTransport, @unchecked Sendable {
    let transportKind: MeshTransportKind = .peerToPeerWiFi
    var isAvailable: Bool { true } // NWBrowser available on iOS
    var discoveredPeers: [MeshNode] { [] }

    private var browser: NWBrowser?
    private var listener: NWListener?
    private var frameCont: AsyncStream<(Data,String)>.Continuation?
    private var eventCont: AsyncStream<MeshTransportEvent>.Continuation?
    private let frameStream: AsyncStream<(Data,String)>
    private let eventStream: AsyncStream<MeshTransportEvent>

    init() {
        var fc: AsyncStream<(Data,String)>.Continuation?
        frameStream = AsyncStream { fc=$0 }; frameCont=fc
        var ec: AsyncStream<MeshTransportEvent>.Continuation?
        eventStream = AsyncStream { ec=$0 }; eventCont=ec
    }

    func startDiscovery() async {
        let params = NWParameters()
        params.includePeerToPeer = true
        // Use Bonjour service _resilix._tcp
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_resilix._tcp", domain: nil)
        browser = NWBrowser(for: descriptor, using: params)
        browser?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.eventCont?.yield(.peerDiscovered(id: "p2p-ready", alias: "P2P Ready"))
            case .failed(let e): self?.eventCont?.yield(.error(e.localizedDescription))
            default: break
            }
        }
        browser?.browseResultsChangedHandler = { _, _ in }
        browser?.start(queue: .main)
        // Listener for incoming
        do {
            listener = try NWListener(using: NWParameters.tcp)
            listener?.service = NWListener.Service(type: "_resilix._tcp")
            listener?.stateUpdateHandler = { _ in }
            listener?.newConnectionHandler = { conn in conn.start(queue: .main) }
            listener?.start(queue: .main)
        } catch { eventCont?.yield(.error(error.localizedDescription)) }
    }
    func stopDiscovery() async { browser?.cancel(); listener?.cancel() }
    func connect(to peerID: String) async throws {}
    func disconnect(from peerID: String) async {}
    func sendFrame(_ data: Data, to peerID: String) async throws {
        guard data.count <= ResilixConstants.maxPacketSizeBytes else { throw ResilixError.packetTooLarge }
        frameCont?.yield((data, peerID))
    }
    func receivedFrames() -> AsyncStream<(Data, String)> { frameStream }
    func connectionEvents() -> AsyncStream<MeshTransportEvent> { eventStream }
}
