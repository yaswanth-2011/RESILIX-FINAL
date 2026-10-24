import Foundation

@MainActor
class MeshController: ObservableObject {
    @Published var isDiscovering = false
    @Published var lastError: ResilixError?
    private let transports: [any MeshTransport]
    private let dedup = DeduplicationStore()
    private let relayQueue = RelayQueue()
    private let routingEngine: MeshRoutingEngine
    private var receiveTasks: [Task<Void, Never>] = []
    private var forwardingTask: Task<Void, Never>?
    var onPacketReceived: ((MeshPacket)->Void)?
    var onDeliveryUpdate: ((String, DeliveryState)->Void)?
    
    /// Public access to transports for diagnostics
    var availableTransports: [any MeshTransport] { transports }

    init(routingEngine: MeshRoutingEngine, transports: [any MeshTransport]) {
        self.routingEngine = routingEngine
        self.transports = transports
    }

    func start() async {
        isDiscovering = true
        lastError = nil
        for t in transports { await t.startDiscovery() }
        for t in transports {
            let stream = t.receivedFrames()
            receiveTasks.append(Task { [weak self] in
                for await (data, peer) in stream {
                    await self?.handleFrame(data, from: peer)
                }
            })
        }
        // Start forwarding processor
        startForwardingProcessor()
    }
    
    func stop() async {
        isDiscovering = false
        for t in transports { await t.stopDiscovery() }
        receiveTasks.forEach { $0.cancel() }
        forwardingTask?.cancel()
        forwardingTask = nil
    }

    func send(packet: MeshPacket) async throws {
        do {
            try PacketValidator.validate(packet)
            let data = try FrameCodec.encode(packet)
            // choose transport: prefer P2P WiFi for large, bluetooth otherwise
            let transport = selectTransport(for: packet)
            // find next hop via routing or direct
            let nextHop = await routingEngine.bestRoute(to: packet.destinationNodeID)?.nextHop ?? packet.destinationNodeID
            let target = nextHop.isEmpty ? packet.destinationNodeID : nextHop
            try await transport.sendFrame(data, to: target.isEmpty ? "broadcast" : target)
            await dedup.insert(packet.id)
            await onDeliveryUpdate?(packet.id, .sending)
        } catch {
            lastError = error as? ResilixError ?? .transportUnavailable(error.localizedDescription)
            await onDeliveryUpdate?(packet.id, .failed)
            throw error
        }
    }
    
    private func selectTransport(for packet: MeshPacket) -> any MeshTransport {
        let available = transports.filter { $0.isAvailable }
        guard !available.isEmpty else { return transports.first! }
        
        // Prefer P2P WiFi for large packets, Bluetooth for small
        if packet.payloadEnvelope.count > 1024 {
            return available.first { $0.transportKind == .peerToPeerWiFi } ?? available.first!
        } else {
            return available.first { $0.transportKind == .bluetooth } ?? available.first!
        }
    }

    private func handleFrame(_ data: Data, from peer: String) async {
        guard let packet = try? FrameCodec.decode(data) else { return }
        // dedup
        if await dedup.isDuplicate(packet.id) { return }
        do { try PacketValidator.validate(packet) } catch { return }
        await dedup.insert(packet.id)
        
        // Update route table with peer info
        await routingEngine.upsert(route: MeshRoute(
            destination: packet.sourceNodeID,
            nextHop: peer,
            hopCount: 1,
            transport: detectTransport(from: peer),
            quality: .stable,
            freshness: Date(),
            failureScore: 0,
            hops: [RouteHop(nodeID: packet.sourceNodeID, transport: detectTransport(from: peer), quality: .stable)]
        ))
        
        // If packet is for us, deliver
        if packet.destinationNodeID.isEmpty || packet.destinationNodeID == "broadcast" {
            await onPacketReceived?(packet)
            await onDeliveryUpdate?(packet.id, .delivered)
            return
        }
        
        // If we're the destination
        // (In real app, compare with our node ID)
        let isForUs = packet.destinationNodeID == "local" // placeholder
        if isForUs {
            await onPacketReceived?(packet)
            await onDeliveryUpdate?(packet.id, .delivered)
            
            // Send acknowledgement
            if packet.type != .acknowledgement {
                let ack = PacketBuilder.makePacket(
                    type: .acknowledgement,
                    source: "local",
                    destination: packet.sourceNodeID,
                    payload: Data("ack:\(packet.id)".utf8),
                    priority: .normal
                )
                try? await send(packet: ack)
            }
            return
        }
        
        // Otherwise, relay if enabled (checked by RelayManager)
        await onPacketReceived?(packet)
        await onDeliveryUpdate?(packet.id, .relaying)
        
        // TTL handling for forwarding
        var fwd = packet.withDecrementedTTL()
        if fwd.ttl == 0 { 
            await onDeliveryUpdate?(packet.id, .expired)
            return 
        }
        
        // Check if we have a route
        if await routingEngine.bestRoute(to: packet.destinationNodeID) == nil {
            // No route - queue for later
            try? await relayQueue.enqueue(fwd)
        } else {
            // Forward immediately
            try? await send(packet: fwd)
        }
    }
    
    private func detectTransport(from peerID: String) -> MeshTransportKind {
        // In real implementation, would track which transport connected to which peer
        return .peerToPeerWiFi
    }
    
    private func startForwardingProcessor() {
        forwardingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // Check every 2 seconds
                await self?.processQueue()
            }
        }
    }
    
    func processQueuedPackets() async {
        await processQueue()
    }
    
    private func processQueue() async {
        let expired = await relayQueue.removeExpired()
        if expired > 0 {
            // Notify about expired packets
        }
        
        while let queued = await relayQueue.dequeue() {
            // Check if route now exists
            if await routingEngine.bestRoute(to: queued.packet.destinationNodeID) != nil {
                try? await send(packet: queued.packet)
            } else {
                // Re-queue with backoff
                var requeue = queued
                requeue.retryCount += 1
                requeue.nextRetry = Date().addingTimeInterval(pow(2.0, Double(requeue.retryCount)) * 2)
                if requeue.retryCount < 5 && !requeue.packet.isExpired {
                    try? await relayQueue.enqueue(requeue.packet)
                }
            }
        }
    }

    func queueCount() async -> Int { await relayQueue.count }
    
    func getQueuedPackets() async -> [QueuedPacket] { await relayQueue.all() }
}
