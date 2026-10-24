import Foundation

@MainActor
class DemoModeController: ObservableObject {
    @Published var isDemoMode = false
    @Published var demoStep: Int = 0
    @Published var demoLog: [String] = []
    private let meshController: MeshController
    private let mock: MockMeshTransport

    init(meshController: MeshController, mock: MockMeshTransport) {
        self.meshController = meshController; self.mock = mock
        // Load persisted demo flag separately
        if let data = UserDefaults.standard.object(forKey: "resilix.demoMode") as? Bool { isDemoMode = data }
    }

    func setDemo(_ enabled: Bool) {
        isDemoMode = enabled
        UserDefaults.standard.set(enabled, forKey: "resilix.demoMode")
        if enabled { startDemo() } else { reset() }
    }

    func startDemo() {
        guard isDemoMode else { return }
        demoLog = ["Demo: Node A (Source) -> Node B (Relay) -> Node C (Destination)"]
        Task {
            mock.simulatePeer(MeshNode(id: "A", alias: "Node A", lastSeen: Date(), isRelay: false))
            mock.simulatePeer(MeshNode(id: "B", alias: "Relay B", lastSeen: Date(), isRelay: true))
            mock.simulatePeer(MeshNode(id: "C", alias: "Node C", lastSeen: Date(), isRelay: false))
        }
    }

    func sendDemoMessage() async {
        let text = "Need help at the north shelter"
        let payload = text.data(using: .utf8)!
        var packet = PacketBuilder.makePacket(type: .chat, source: "A", destination: "C", payload: payload, priority: .normal)
        demoLog.append("A created packet \(packet.id.prefix(8))")
        // Simulate B verification and forwarding
        do {
            try PacketValidator.validate(packet)
            demoLog.append("B verified packet metadata")
            packet = packet.withDecrementedTTL()
            demoLog.append("B forwarded to C (TTL now \(packet.ttl))")
            try await meshController.send(packet: packet)
            demoLog.append("C received packet")
            // Ack back
            let ack = PacketBuilder.makePacket(type: .acknowledgement, source: "C", destination: "A", payload: Data("ack:\(packet.id)".utf8), priority: .normal)
            try await meshController.send(packet: ack)
            demoLog.append("Ack returned to A — Delivered via 2 hops")
        } catch { demoLog.append("Demo failed: \(error.localizedDescription)") }
    }

    func reset() { demoLog = []; demoStep = 0 }
}
