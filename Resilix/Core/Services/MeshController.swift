import Foundation
import CoreLocation
import Combine

/// A packet that was decrypted and is ready for the application layer.
struct DeliveredPayload {
    var packet: MeshPacket
    var plaintext: Data
    /// Node that created the packet.
    var originNodeID: String
    /// Peer the packet was received from (the previous hop).
    var previousHop: String
    /// Human readable route, e.g. "A -> B -> C".
    var route: String
}

/// Statistics shown in the mesh screen.
struct MeshStatistics: Sendable, Equatable {
    var sentPackets = 0
    var receivedPackets = 0
    var relayedPackets = 0
    var droppedPackets = 0
    var queuedPackets = 0
    var duplicatePackets = 0
}

/// Owns the mesh: transports, routing, relaying and the packet pipeline.
///
/// Responsibilities
/// -----------------
/// * start / stop the transports and keep the peer list up to date;
/// * build, sign, encrypt and transmit packets;
/// * validate, de-duplicate and decrypt incoming packets;
/// * acknowledge delivery back to the sender;
/// * relay packets that are not addressed to this node (multi hop, store and
///   forward) with a hop limit, an expiry and duplicate suppression;
/// * keep a persistent queue of packets that could not be delivered yet.
@MainActor
final class MeshController: ObservableObject {
    @Published private(set) var isDiscovering = false
    @Published private(set) var lastError: ResilixError?
    @Published private(set) var peers: [MeshNode] = []
    @Published private(set) var connectedPeerIDs: Set<String> = []
    @Published private(set) var statistics = MeshStatistics()
    @Published private(set) var queuedPacketCount = 0

    /// Called for every packet that was addressed to this node.
    var onPacketReceived: ((DeliveredPayload) -> Void)?
    /// Called when the delivery state of an outgoing packet changes.
    var onDeliveryUpdate: ((String, DeliveryState) -> Void)?
    /// Decides whether a packet may be forwarded (flood control).
    var relayDecision: ((MeshPacket) -> Bool)?

    private let transports: [any MeshTransport]
    private let dedup = DeduplicationStore()
    private let relayQueue = RelayQueue()
    private let routingEngine: MeshRoutingEngine
    private let peerRegistry = MeshPeerRegistry()
    private let security = SecurityManager()
    private let peerKeys = PeerKeyStore()

    private var nodeID: String = ""
    private var alias: String = ResilixConstants.defaultAlias
    private var localHello: PeerHello?

    private var receiveTasks: [Task<Void, Never>] = []
    private var eventTasks: [Task<Void, Never>] = []
    private var forwardingTask: Task<Void, Never>?
    private var advertisementTask: Task<Void, Never>?

    init(routingEngine: MeshRoutingEngine, transports: [any MeshTransport]) {
        self.routingEngine = routingEngine
        self.transports = transports
    }

    // MARK: - Public accessors

    var availableTransports: [any MeshTransport] { transports }
    var routing: MeshRoutingEngine { routingEngine }
    /// Identifier of this device inside the mesh.
    var localNodeID: String { nodeID }
    /// Alias of this device inside the mesh.
    var localAlias: String { alias }

    func peerHello(for peerID: String) -> PeerHello? {
        for transport in transports {
            if let hello = transport.peerHello(for: peerID) { return hello }
        }
        return nil
    }

    func connectedPeers() -> [MeshNode] {
        peers.filter { connectedPeerIDs.contains($0.id) }
    }

    func isConnected(to peerID: String) -> Bool {
        connectedPeerIDs.contains(peerID)
    }

    func signalStrength(for peerID: String) -> Int? {
        guard let node = peers.first(where: { $0.id == peerID }) else { return nil }
        return MeshController.signalPercent(for: node)
    }

    /// Maps a peer to a coarse signal value (0...100).
    static func signalPercent(for node: MeshNode) -> Int {
        let age = Date().timeIntervalSince(node.lastSeen)
        switch age {
        case ..<15: return 95
        case ..<45: return 80
        case ..<120: return 62
        case ..<300: return 40
        default: return 20
        }
    }

    // MARK: - Lifecycle

    func configure(nodeID: String, alias: String, hello: PeerHello) async {
        self.nodeID = nodeID
        self.alias = alias
        self.localHello = hello
        routingEngine.configure(localNodeID: nodeID, alias: alias, supportsRelay: hello.supportsRelay)
        for transport in transports {
            await transport.configure(nodeID: nodeID, alias: alias, hello: hello)
        }
    }

    func start() async {
        guard nodeID.isEmpty == false else { return }
        isDiscovering = true
        lastError = nil

        await dedup.restore()
        queuedPacketCount = await relayQueue.restore()

        for transport in transports {
            await transport.startDiscovery()
        }
        for transport in transports {
            let stream = transport.receivedFrames()
            receiveTasks.append(Task { [weak self] in
                for await (data, peer) in stream {
                    await self?.handleFrame(data, from: peer)
                }
            })
            let events = transport.connectionEvents()
            eventTasks.append(Task { [weak self] in
                for await event in events {
                    await self?.handle(event)
                }
            })
        }

        startForwardingProcessor()
        startAdvertisementLoop()
        await refreshPeers()
    }

    func stop() async {
        isDiscovering = false
        for transport in transports {
            await transport.stopDiscovery()
        }
        receiveTasks.forEach { $0.cancel() }
        eventTasks.forEach { $0.cancel() }
        receiveTasks.removeAll()
        eventTasks.removeAll()
        forwardingTask?.cancel()
        forwardingTask = nil
        advertisementTask?.cancel()
        advertisementTask = nil
        await relayQueue.persist()
        await dedup.persist()
    }

    // MARK: - Sending

    /// Encrypts `plaintext` for the destination and sends it through the mesh.
    ///
    /// - Returns: the packet that was created (also used for the delivery
    ///   bookkeeping and for the acknowledgement).
    @discardableResult
    func sendSecurePacket(type: MeshPacketType,
                          plaintext: Data,
                          destination: String,
                          priority: PacketPriority = .normal,
                          expiry: TimeInterval = ResilixConstants.packetExpirySeconds,
                          ttl: UInt8 = ResilixConstants.defaultTTL) async throws -> MeshPacket {
        let envelope = try await makeEnvelope(plaintext: plaintext, destination: destination)
        let payload = try JSONEncoder().encode(envelope)
        var packet = MeshPacket(id: UUID().uuidString,
                                version: ResilixConstants.protocolVersion,
                                type: type,
                                sourceNodeID: nodeID,
                                destinationNodeID: destination,
                                createdAt: Date(),
                                expiresAt: Date().addingTimeInterval(expiry),
                                ttl: ttl,
                                priority: priority,
                                payloadEnvelope: payload,
                                integrityTag: Data(),
                                originNodeID: nodeID,
                                hopCount: 0,
                                visited: [nodeID],
                                sessionID: nil)
        packet.integrityTag = try await security.sign(PacketCrypto.canonicalBytes(packet))
        try await transmit(packet)
        return packet
    }

    /// Sends a packet that is not confidential (route advertisements, SOS
    /// broadcast metadata, acknowledgements).
    @discardableResult
    func sendPlainPacket(type: MeshPacketType,
                         payload: Data,
                         destination: String,
                         priority: PacketPriority = .normal,
                         ttl: UInt8 = ResilixConstants.defaultTTL) async throws -> MeshPacket {
        var packet = MeshPacket(id: UUID().uuidString,
                                version: ResilixConstants.protocolVersion,
                                type: type,
                                sourceNodeID: nodeID,
                                destinationNodeID: destination,
                                createdAt: Date(),
                                expiresAt: Date().addingTimeInterval(ResilixConstants.packetExpirySeconds),
                                ttl: ttl,
                                priority: priority,
                                payloadEnvelope: payload,
                                integrityTag: Data(),
                                originNodeID: nodeID,
                                hopCount: 0,
                                visited: [nodeID],
                                sessionID: nil)
        packet.integrityTag = try await security.sign(PacketCrypto.canonicalBytes(packet))
        try await transmit(packet)
        return packet
    }

    /// Builds the encrypted envelope for the destination.
    private func makeEnvelope(plaintext: Data, destination: String) async throws -> SecureEnvelope {
        let senderKey = try await security.agreementPublicKey()
        var seals: [SecureEnvelope.Seal] = []

        if destination.isEmpty {
            // Broadcast: seal the payload once for every known peer.
            for identity in await peerKeys.allIdentities() {
                let box = try await security.seal(plaintext, for: identity.id, peerPublicKey: identity.agreementPublicKey)
                seals.append(SecureEnvelope.Seal(peerID: identity.id, box: box))
            }
            guard !seals.isEmpty else { throw ResilixError.routingNoRoute }
        } else {
            guard let identity = await peerKeys.identity(for: destination) else {
                throw ResilixError.transportUnavailable(String(format: L("The public key of %@ is not known yet"), destination))
            }
            let box = try await security.seal(plaintext, for: destination, peerPublicKey: identity.agreementPublicKey)
            seals.append(SecureEnvelope.Seal(peerID: destination, box: box))
        }

        return SecureEnvelope(version: 1, senderPublicKey: senderKey, seals: seals)
    }

    /// Sends a packet to the next hop, or stores it for later delivery.
    ///
    /// - Returns: `true` when the packet left the device, `false` when it
    ///   was stored in the persistent queue instead.
    @discardableResult
    private func transmit(_ packet: MeshPacket) async throws -> Bool {
        if packet.destinationNodeID.isEmpty {
            // Broadcast: hand the packet to every connected peer.
            let data = try FrameCodec.encode(packet)
            var delivered = 0
            for peerID in connectedPeerIDs {
                guard let transport = transport(for: peerID, payloadSize: packet.payloadEnvelope.count) else { continue }
                do {
                    try await transport.sendFrame(data, to: peerID)
                    delivered += 1
                } catch {
                    lastError = .transportUnavailable(error.localizedDescription)
                }
            }
            if delivered == 0 {
                try? await relayQueue.enqueue(packet)
                queuedPacketCount = await relayQueue.count
                onDeliveryUpdate?(packet.id, .queued)
                return false
            }
            await dedup.insert(packet.id)
            statistics.sentPackets += delivered
            onDeliveryUpdate?(packet.id, .sending)
            return true
        }

        let target = await nextHop(for: packet.destinationNodeID)
        guard let target else {
            // No route yet: keep the packet for later (store and forward).
            try? await relayQueue.enqueue(packet)
            queuedPacketCount = await relayQueue.count
            onDeliveryUpdate?(packet.id, .queued)
            return false
        }
        guard let transport = transport(for: target, payloadSize: packet.payloadEnvelope.count) else {
            try? await relayQueue.enqueue(packet)
            queuedPacketCount = await relayQueue.count
            onDeliveryUpdate?(packet.id, .queued)
            return false
        }
        do {
            let data = try FrameCodec.encode(packet)
            try await transport.sendFrame(data, to: target)
            await dedup.insert(packet.id)
            statistics.sentPackets += 1
            routingEngine.recordSuccess(peerID: target)
            onDeliveryUpdate?(packet.id, .sending)
        } catch {
            try? await relayQueue.enqueue(packet)
            queuedPacketCount = await relayQueue.count
            lastError = error as? ResilixError ?? .transportUnavailable(error.localizedDescription)
            onDeliveryUpdate?(packet.id, .queued)
            throw error
        }
        return true
    }

    /// Determines the neighbour that has to receive the packet.
    private func nextHop(for destination: String) async -> String? {
        if destination.isEmpty {
            // Broadcast: use every connected peer.
            return connectedPeerIDs.sorted().first
        }
        if let route = await routingEngine.bestRoute(to: destination) {
            return route.nextHop
        }
        if connectedPeerIDs.contains(destination) { return destination }
        return nil
    }

    private func transport(for peerID: String, payloadSize: Int) -> (any MeshTransport)? {
        let candidates = transports.filter { $0.isAvailable && $0.connectedPeerIDs.contains(peerID) }
        guard !candidates.isEmpty else { return nil }
        if payloadSize > 1024 {
            return candidates.first { $0.transportKind == .peerToPeerWiFi } ?? candidates.first
        }
        return candidates.first { $0.transportKind == .bluetooth } ?? candidates.first
    }

    // MARK: - Receiving

    private func handleFrame(_ data: Data, from peerID: String) async {
        guard let packet = try? FrameCodec.decode(data) else {
            statistics.droppedPackets += 1
            return
        }
        do {
            try PacketValidator.validate(packet)
        } catch {
            statistics.droppedPackets += 1
            if let resilixError = error as? ResilixError { lastError = resilixError }
            return
        }

        // Loop prevention: the packet already passed this node.
        if packet.hasVisited(nodeID) {
            statistics.duplicatePackets += 1
            return
        }
        if await dedup.isDuplicate(packet.id) {
            statistics.duplicatePackets += 1
            return
        }
        await dedup.insert(packet.id)
        statistics.receivedPackets += 1

        // The sender is a direct neighbour: refresh the link.
        await refreshNeighbour(peerID: peerID)

        // Verify the origin signature when the origin is known.
        if let identity = await peerKeys.identity(for: packet.originNodeID) {
            let valid = await security.verify(packet.integrityTag,
                                              for: PacketCrypto.canonicalBytes(packet),
                                              publicKey: identity.signingPublicKey)
            if !valid {
                statistics.droppedPackets += 1
                lastError = .securityInvalidSignature
                return
            }
        } else {
            // Unknown origin: the packet can still be relayed (the relay does
            // not need the key) but it must not be delivered to the app.
            lastError = .securityInvalidSignature
        }

        switch packet.type {
        case .routeAdvertisement:
            if let advertisement = try? JSONDecoder().decode(RouteAdvertisement.self, from: packet.payloadEnvelope) {
                await routingEngine.merge(advertisement: advertisement, from: peerID)
                await sendAdvertisement(to: peerID)
            }
            return
        case .acknowledgement:
            if let ack = try? JSONDecoder().decode(MeshAcknowledgement.self, from: packet.payloadEnvelope) {
                onDeliveryUpdate?(ack.packetID, .delivered)
            }
            return
        case .capabilityAdvertisement:
            if let advertisement = try? JSONDecoder().decode(LocationAdvertisement.self, from: packet.payloadEnvelope) {
                applyLocation(advertisement)
            }
            return
        default:
            break
        }

        let addressedToUs = packet.destinationNodeID.isEmpty || packet.destinationNodeID == nodeID
        if !addressedToUs {
            await relay(packet, receivedFrom: peerID)
            return
        }

        guard let plaintext = try await decryptPayload(packet) else {
            statistics.droppedPackets += 1
            return
        }

        let route = routeDescription(for: packet)
        onPacketReceived?(DeliveredPayload(packet: packet,
                                           plaintext: plaintext,
                                           originNodeID: packet.originNodeID,
                                           previousHop: peerID,
                                           route: route))

        if packet.type != .acknowledgement {
            await sendAcknowledgement(for: packet, previousHop: peerID)
        }
    }

    /// Opens the encrypted payload of a packet.
    private func decryptPayload(_ packet: MeshPacket) async -> Data? {
        guard let envelope = try? JSONDecoder().decode(SecureEnvelope.self, from: packet.payloadEnvelope) else {
            lastError = .securityDecryptionFailed
            return nil
        }
        guard let box = envelope.seal(for: nodeID) else {
            // Not addressed to this device (should not happen for delivered
            // packets, but a malformed peer could send one).
            return nil
        }
        // The key of the sender must match the pinned key: a different key
        // is an impersonation attempt and is rejected.
        guard let identity = await peerKeys.identity(for: packet.originNodeID) else {
            lastError = .securityInvalidSignature
            return nil
        }
        guard identity.agreementPublicKey == envelope.senderPublicKey else {
            lastError = .securityInvalidSignature
            return nil
        }
        do {
            return try await security.open(box, from: packet.originNodeID, peerPublicKey: identity.agreementPublicKey)
        } catch {
            lastError = .securityDecryptionFailed
            return nil
        }
    }

    /// Sends the acknowledgement of a received packet back to the sender.
    private func sendAcknowledgement(for packet: MeshPacket, previousHop: String) async {
        let ack = MeshAcknowledgement(packetID: packet.id,
                                      hopCount: packet.hopCount + 1,
                                      route: routeDescription(for: packet),
                                      delivered: true)
        guard let payload = try? JSONEncoder().encode(ack) else { return }
        do {
            var ackPacket = MeshPacket(id: UUID().uuidString,
                                       version: ResilixConstants.protocolVersion,
                                       type: .acknowledgement,
                                       sourceNodeID: nodeID,
                                       destinationNodeID: packet.originNodeID,
                                       createdAt: Date(),
                                       expiresAt: Date().addingTimeInterval(ResilixConstants.packetExpirySeconds),
                                       ttl: ResilixConstants.defaultTTL,
                                       priority: packet.priority,
                                       payloadEnvelope: payload,
                                       integrityTag: Data(),
                                       originNodeID: nodeID,
                                       hopCount: 0,
                                       visited: [nodeID],
                                       sessionID: nil)
            ackPacket.integrityTag = try await security.sign(PacketCrypto.canonicalBytes(ackPacket))
            let target = await routingEngine.bestRoute(to: packet.originNodeID)?.nextHop ?? previousHop
            guard let transport = transport(for: target, payloadSize: payload.count) else { return }
            let data = try FrameCodec.encode(ackPacket)
            try await transport.sendFrame(data, to: target)
            statistics.sentPackets += 1
        } catch {
            // The acknowledgement is best effort: the sender retries.
        }
    }

    /// Forwards a packet that is not addressed to this node.
    private func relay(_ packet: MeshPacket, receivedFrom peerID: String) async {
        guard let decision = relayDecision else { return }
        guard decision(packet) else { return }

        var forwarded = packet.withDecrementedTTL().markedVisited(by: nodeID)
        guard forwarded.ttl > 0 else {
            onDeliveryUpdate?(packet.id, .expired)
            return
        }

        let route = await routingEngine.bestRoute(to: packet.destinationNodeID)
        let nextHop = route?.nextHop
        guard let nextHop, nextHop != receivedFrom, connectedPeerIDs.contains(nextHop) else {
            // No usable next hop: remember the packet until a route appears.
            try? await relayQueue.enqueue(forwarded)
            queuedPacketCount = await relayQueue.count
            return
        }
        guard let transport = transport(for: nextHop, payloadSize: forwarded.payloadEnvelope.count) else {
            try? await relayQueue.enqueue(forwarded)
            queuedPacketCount = await relayQueue.count
            return
        }
        do {
            let data = try FrameCodec.encode(forwarded)
            try await transport.sendFrame(data, to: nextHop)
            statistics.relayedPackets += 1
            routingEngine.recordSuccess(peerID: nextHop)
        } catch {
            routingEngine.recordFailure(peerID: nextHop)
            try? await relayQueue.enqueue(forwarded)
            queuedPacketCount = await relayQueue.count
        }
    }

    private func routeDescription(for packet: MeshPacket) -> String {
        let hops = packet.visited
        if hops.isEmpty { return L("Direct") }
        return hops.joined(separator: " -> ")
    }

    // MARK: - Peer bookkeeping

    private func handle(_ event: MeshTransportEvent) async {
        switch event {
        case .peerDiscovered(let id, let alias):
            if let hello = peerHello(for: id) {
                await registerPeer(hello)
            } else {
                await refreshNeighbour(peerID: id)
                upsertPeer(MeshNode(id: id, alias: alias, displayName: alias, lastSeen: Date(), isRelay: false))
            }
            await sendAdvertisement(to: id)
        case .peerLost(let id):
            peers.removeAll { $0.id == id }
            await routingEngine.removeNeighbour(id: id)
        case .connected(let id):
            connectedPeerIDs.insert(id)
            if let hello = peerHello(for: id) {
                await registerPeer(hello)
            }
            await refreshNeighbour(peerID: id)
            await sendAdvertisement(to: id)
        case .disconnected(let id):
            connectedPeerIDs.remove(id)
            await routingEngine.removeNeighbour(id: id)
        case .error(let message):
            if !message.isEmpty {
                lastError = .transportUnavailable(message)
            }
        }
    }

    private func registerPeer(_ hello: PeerHello) async {
        do {
            _ = try await peerKeys.register(peerID: hello.nodeID,
                                            agreementPublicKey: hello.agreementPublicKey,
                                            signingPublicKey: hello.signingPublicKey,
                                            alias: hello.alias)
        } catch {
            lastError = .securityInvalidSignature
            return
        }
        await refreshNeighbour(peerID: hello.nodeID)
        upsertPeer(MeshNode(id: hello.nodeID,
                            alias: hello.alias,
                            displayName: hello.alias,
                            lastSeen: Date(),
                            isRelay: hello.supportsRelay))
    }

    /// Stores the approximate position a peer shared with the mesh.
    private func applyLocation(_ advertisement: LocationAdvertisement) {
        guard let index = peers.firstIndex(where: { $0.id == advertisement.nodeID }) else { return }
        peers[index].latitude = advertisement.latitude
        peers[index].longitude = advertisement.longitude
        peers[index].lastSeen = Date()
    }

    /// Shares the own position with the mesh (rounded, opt-in).
    func broadcastLocation(latitude: Double, longitude: Double) async {
        let rounded = LocationAdvertisement.rounded(latitude: latitude, longitude: longitude)
        let advertisement = LocationAdvertisement(nodeID: nodeID,
                                                  latitude: rounded.0,
                                                  longitude: rounded.1,
                                                  accuracy: 100,
                                                  timestamp: Date())
        guard let payload = try? JSONEncoder().encode(advertisement) else { return }
        _ = try? await sendPlainPacket(type: .capabilityAdvertisement,
                                       payload: payload,
                                       destination: "",
                                       priority: .low)
    }

    /// Position a peer shared (nil when the peer did not share one).
    func location(of peerID: String) -> CLLocationCoordinate2D? {
        guard let node = peers.first(where: { $0.id == peerID }),
              let latitude = node.latitude,
              let longitude = node.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func upsertPeer(_ node: MeshNode) {
        if let index = peers.firstIndex(where: { $0.id == node.id }) {
            peers[index].alias = node.alias
            if let displayName = node.displayName { peers[index].displayName = displayName }
            peers[index].isRelay = node.isRelay
            peers[index].lastSeen = node.lastSeen
            if let latitude = node.latitude { peers[index].latitude = latitude }
            if let longitude = node.longitude { peers[index].longitude = longitude }
        } else {
            peers.append(node)
        }
    }

    private func refreshNeighbour(peerID: String) async {
        for transport in transports {
            guard let node = transport.discoveredPeers.first(where: { $0.id == peerID }) else { continue }
            await peerRegistry.update(node, transport: transport.transportKind)
            await routingEngine.registerNeighbour(node, transport: transport.transportKind, quality: .stable)
            return
        }
    }

    private func refreshPeers() async {
        var collected: [String: MeshNode] = [:]
        for transport in transports {
            for node in transport.discoveredPeers {
                collected[node.id] = node
            }
        }
        // Keep the information the transports do not know (shared position).
        for (id, node) in collected {
            if let existing = peers.first(where: { $0.id == id }) {
                var merged = node
                merged.latitude = existing.latitude
                merged.longitude = existing.longitude
                if merged.alias.isEmpty { merged.alias = existing.alias }
                merged.displayName = existing.displayName ?? node.displayName
                collected[id] = merged
            }
        }
        peers = Array(collected.values).sorted { $0.alias < $1.alias }
        connectedPeerIDs = Set(transports.flatMap { Array($0.connectedPeerIDs) })
    }

    // MARK: - Periodic work

    private func startForwardingProcessor() {
        forwardingTask?.cancel()
        forwardingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self?.processQueue()
                await self?.refreshPeers()
            }
        }
    }

    private func startAdvertisementLoop() {
        advertisementTask?.cancel()
        advertisementTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                await self?.broadcastAdvertisement()
            }
        }
    }

    /// Sends the route advertisement to every connected peer.
    func broadcastAdvertisement() async {
        for peerID in connectedPeerIDs {
            await sendAdvertisement(to: peerID)
        }
    }

    private func sendAdvertisement(to peerID: String) async {
        let advertisement = routingEngine.advertisement(for: peerID)
        guard let payload = try? JSONEncoder().encode(advertisement) else { return }
        guard let transport = transport(for: peerID, payloadSize: payload.count) else { return }
        do {
            var packet = MeshPacket(id: UUID().uuidString,
                                    version: ResilixConstants.protocolVersion,
                                    type: .routeAdvertisement,
                                    sourceNodeID: nodeID,
                                    destinationNodeID: peerID,
                                    createdAt: Date(),
                                    expiresAt: Date().addingTimeInterval(ResilixConstants.packetExpirySeconds),
                                    ttl: 1,
                                    priority: .low,
                                    payloadEnvelope: payload,
                                    integrityTag: Data(),
                                    originNodeID: nodeID,
                                    hopCount: 0,
                                    visited: [nodeID],
                                    sessionID: nil)
            packet.integrityTag = try await security.sign(PacketCrypto.canonicalBytes(packet))
            let data = try FrameCodec.encode(packet)
            try await transport.sendFrame(data, to: peerID)
        } catch {
            // Advertisements are best effort.
        }
    }

    /// Retries the packets that could not be delivered yet.
    func processQueue() async {
        await relayQueue.removeExpired()
        let ready = await relayQueue.ready()
        for item in ready {
            guard !item.packet.isExpired else { continue }
            let target = await nextHop(for: item.packet.destinationNodeID)
            guard let target, let transport = transport(for: target, payloadSize: item.packet.payloadEnvelope.count) else {
                await relayQueue.incrementRetry(for: item.packet.id)
                continue
            }
            do {
                let data = try FrameCodec.encode(item.packet)
                try await transport.sendFrame(data, to: target)
                await relayQueue.dequeueMatching(id: item.packet.id)
                await dedup.insert(item.packet.id)
                statistics.sentPackets += 1
                onDeliveryUpdate?(item.packet.id, .sending)
            } catch {
                await relayQueue.incrementRetry(for: item.packet.id)
            }
        }
        queuedPacketCount = await relayQueue.count
    }

    func queueCount() async -> Int { await relayQueue.count }
    func getQueuedPackets() async -> [QueuedPacket] { await relayQueue.all() }
}
