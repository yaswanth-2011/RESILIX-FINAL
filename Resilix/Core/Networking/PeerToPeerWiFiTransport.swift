import Foundation
import Network

/// Peer-to-peer Wi-Fi transport built on `Network.framework`.
///
/// The device advertises a Bonjour service (`_resilix._tcp`) over
/// peer-to-peer Wi-Fi and browses for the same service. Every connection
/// starts with the `PeerHello` handshake, afterwards the same
/// length-prefixed frame format as the Bluetooth transport is used, so a
/// packet can span several TCP segments and is reassembled transparently.
final class PeerToPeerWiFiTransport: MeshTransport, @unchecked Sendable {
    let transportKind: MeshTransportKind = .peerToPeerWiFi

    private let queue = DispatchQueue(label: "com.resilix.wifi")
    private var browser: NWBrowser?
    private var listener: NWListener?

    private var nodeID: String = ""
    private var alias: String = ResilixConstants.defaultAlias
    private var localHello: PeerHello?

    /// Known peers and the endpoint that can be reached to open a connection.
    private var nodes: [String: MeshNode] = [:]
    private var endpoints: [String: NWEndpoint] = [:]
    private var connections: [String: NWConnection] = [:]
    private var connectionTasks: [String: Task<NWConnection, Error>] = [:]
    private var hellos: [String: PeerHello] = [:]
    private var buffers: [ObjectIdentifier: StreamFrameBuffer] = [:]
    private var peerIDByConnection: [ObjectIdentifier: String] = [:]
    private var fragments: [String: (count: Int, chunks: [Int: Data], updated: Date)] = [:]

    private var frameCont: AsyncStream<(Data, String)>.Continuation?
    private var eventCont: AsyncStream<MeshTransportEvent>.Continuation?
    private let frameStream: AsyncStream<(Data, String)>
    private let eventStream: AsyncStream<MeshTransportEvent>

    private static let maximumFrameBytes = 16 * 1024

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

    // MARK: - MeshTransport

    var isAvailable: Bool {
        queue.sync { listener != nil || browser != nil }
    }

    var discoveredPeers: [MeshNode] {
        queue.sync { Array(nodes.values) }
    }

    var connectedPeerIDs: Set<String> {
        queue.sync { Set(connections.keys) }
    }

    func configure(nodeID: String, alias: String, hello: PeerHello) async {
        queue.async { [weak self] in
            guard let self else { return }
            self.nodeID = nodeID
            self.alias = alias
            self.localHello = hello
            self.startListener()
        }
    }

    func peerHello(for peerID: String) -> PeerHello? {
        queue.sync { hellos[peerID] }
    }

    func startDiscovery() async {
        queue.async { [weak self] in
            self?.startBrowser()
        }
    }

    func stopDiscovery() async {
        queue.async { [weak self] in
            guard let self else { return }
            self.browser?.cancel()
            self.browser = nil
        }
    }

    func connect(to peerID: String) async throws {
        _ = try await connection(for: peerID)
    }

    func disconnect(from peerID: String) async {
        queue.async { [weak self] in
            guard let self else { return }
            self.connections[peerID]?.cancel()
            self.connections.removeValue(forKey: peerID)
            self.connectionTasks.removeValue(forKey: peerID)?.cancel()
            self.eventCont?.yield(.disconnected(id: peerID))
        }
    }

    func sendFrame(_ data: Data, to peerID: String) async throws {
        let connection = try await connection(for: peerID)
        let frames = FrameCodec.frames(for: data, mtu: Self.maximumFrameBytes, transferID: UUID().uuidString)
        for frame in frames {
            try await send(frame, over: connection)
        }
    }

    func receivedFrames() -> AsyncStream<(Data, String)> { frameStream }
    func connectionEvents() -> AsyncStream<MeshTransportEvent> { eventStream }

    // MARK: - Bonjour

    private func makeParameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        parameters.allowLocalEndpointReuse = true
        return parameters
    }

    private func startBrowser() {
        guard browser == nil else { return }
        // `.bonjourWithTXTRecord` is required: a plain `.bonjour` browser reports
        // empty metadata, so the node id would fall back to an endpoint
        // description that never matches the peer again.
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: ResilixConstants.bonjourServiceType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: makeParameters())
        self.browser = browser
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                break
            case .failed(let error):
                self?.eventCont?.yield(.error(String(format: L("Local network unavailable: %@"), error.localizedDescription)))
            case .waiting(let error):
                self?.eventCont?.yield(.error(String(format: L("Waiting for local network: %@"), error.localizedDescription)))
            default:
                break
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.handle(results: results)
        }
        browser.start(queue: queue)
    }

    private func handle(results: Set<NWBrowser.Result>) {
        for result in results {
            var txt: [String: String] = [:]
            if case let .bonjour(record) = result.metadata {
                txt = record.dictionary
            }
            let peerID = txt["node"]
                ?? Self.nodeID(from: result.endpoint)
                ?? result.endpoint.debugDescription
            let alias = txt["alias"] ?? "Resilix Node"
            nodes[peerID] = MeshNode(id: peerID,
                                     alias: alias,
                                     displayName: alias,
                                     lastSeen: Date(),
                                     isRelay: false,
                                     transportHint: MeshTransportKind.peerToPeerWiFi.rawValue)
            endpoints[peerID] = result.endpoint
            eventCont?.yield(.peerDiscovered(id: peerID, alias: alias))
        }
    }

    private func startListener() {
        guard listener == nil, !nodeID.isEmpty else { return }
        do {
            let listener = try NWListener(using: makeParameters())
            self.listener = listener
            let txt = NWTXTRecord(["node": nodeID, "alias": alias, "v": String(ResilixConstants.protocolVersion)])
            listener.service = NWListener.Service(name: BluetoothTransport.advertisedName(nodeID: nodeID),
                                                  type: ResilixConstants.bonjourServiceType,
                                                  txtRecord: txt)
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    self?.eventCont?.yield(.error(String(format: L("Listener failed: %@"), error.localizedDescription)))
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
        } catch {
            eventCont?.yield(.error(String(format: L("Could not start local network listener: %@"), error.localizedDescription)))
        }
    }

    /// Recovers the node id from an advertised Bonjour service name.
    private static func nodeID(from endpoint: NWEndpoint) -> String? {
        guard case let .service(name, _, _, _) = endpoint else { return nil }
        return BluetoothTransport.nodeID(fromAdvertisedName: name)
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.sendHandshake(on: connection)
                self?.read(on: connection)
            case .failed(let error):
                self?.eventCont?.yield(.error(String(format: L("Connection failed: %@"), error.localizedDescription)))
            case .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    // MARK: - Connections

    private func connection(for peerID: String) async throws -> NWConnection {
        if let existing = await withCheckedContinuation({ (c: CheckedContinuation<NWConnection?, Never>) in
            queue.async { c.resume(returning: self.connections[peerID]) }
        }) {
            return existing
        }
        let task = await withCheckedContinuation { (c: CheckedContinuation<Task<NWConnection, Error>, Never>) in
            queue.async {
                if let existing = self.connectionTasks[peerID] {
                    c.resume(returning: existing)
                } else {
                    let task = Task { [weak self] () throws -> NWConnection in
                        guard let self else { throw ResilixError.transportUnavailable(L("Wi-Fi transport stopped")) }
                        guard let endpoint = await self.endpoint(for: peerID) else {
                            throw ResilixError.transportUnavailable(String(format: L("No route to %@"), peerID))
                        }
                        let connection = NWConnection(to: endpoint, using: self.makeParameters())
                        try await self.startAndWait(connection)
                        self.register(connection, peerID: peerID)
                        return connection
                    }
                    self.connectionTasks[peerID] = task
                    c.resume(returning: task)
                }
            }
        }
        defer { queue.async { self.connectionTasks.removeValue(forKey: peerID) } }
        return try await task.value
    }

    private func endpoint(for peerID: String) async -> NWEndpoint? {
        await withCheckedContinuation { (c: CheckedContinuation<NWEndpoint?, Never>) in
            queue.async { c.resume(returning: self.endpoints[peerID]) }
        }
    }

    private func startAndWait(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume()
                case .failed(let error):
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(throwing: error)
                case .cancelled:
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(throwing: ResilixError.transportUnavailable(L("Connection cancelled")))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    private func register(_ connection: NWConnection, peerID: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.connections[peerID] = connection
            self.peerIDByConnection[ObjectIdentifier(connection)] = peerID
            self.sendHandshake(on: connection)
            self.read(on: connection)
            self.eventCont?.yield(.connected(id: peerID))
        }
    }

    private func send(_ data: Data, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func sendHandshake(on connection: NWConnection) {
        guard let hello = localHello, let frame = FrameCodec.handshakeFrame(hello) else { return }
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    // MARK: - Receiving

    private func read(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.queue.async { self.handle(data: data, connection: connection) }
            }
            if let error {
                self.eventCont?.yield(.error(String(format: L("Receive failed: %@"), error.localizedDescription)))
                return
            }
            if isComplete { return }
            self.read(on: connection)
        }
    }

    private func handle(data: Data, connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        var buffer = buffers[key] ?? StreamFrameBuffer()
        let frames = buffer.append(data)
        buffers[key] = buffer
        let knownPeerID = peerIDByConnection[key]
        for frame in frames {
            switch frame.kind {
            case .handshake:
                guard let hello = try? JSONDecoder().decode(PeerHello.self, from: frame.payload) else { continue }
                hellos[hello.nodeID] = hello
                nodes[hello.nodeID] = MeshNode(id: hello.nodeID,
                                               alias: hello.alias,
                                               displayName: hello.alias,
                                               lastSeen: Date(),
                                               isRelay: hello.supportsRelay,
                                               transportHint: MeshTransportKind.peerToPeerWiFi.rawValue)
                connections[hello.nodeID] = connection
                peerIDByConnection[key] = hello.nodeID
                eventCont?.yield(.peerDiscovered(id: hello.nodeID, alias: hello.alias))
                eventCont?.yield(.connected(id: hello.nodeID))
            case .single:
                let peer = peerIDByConnection[key] ?? knownPeerID ?? "unknown"
                frameCont?.yield((frame.payload, peer))
            case .fragment:
                guard let transferID = frame.transferID else { continue }
                var entry = fragments[transferID] ?? (count: frame.count, chunks: [:], updated: Date())
                entry.chunks[frame.index] = frame.payload
                entry.updated = Date()
                fragments[transferID] = entry
                if entry.chunks.count == entry.count {
                    let parts = entry.chunks.map { index, payload in
                        FrameCodec.ParsedFrame(kind: .fragment, index: index, count: entry.count, transferID: nil, payload: payload)
                    }
                    fragments.removeValue(forKey: transferID)
                    if let assembled = FrameCodec.reassemble(parts) {
                        let peer = peerIDByConnection[key] ?? knownPeerID ?? "unknown"
                        frameCont?.yield((assembled, peer))
                    }
                }
            }
        }
    }
}
