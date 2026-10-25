import Foundation
import Combine

/// Drives the demo mode.
///
/// In demo mode the in-process `MockMeshTransport` publishes the simulated
/// nodes A, B and C so that the mesh pipeline (discovery, routing,
/// acknowledgement) can be inspected on a single device. The demo never
/// pretends that a real radio link exists: every log line states what
/// actually happened.
@MainActor
final class DemoModeController: ObservableObject {
    @Published private(set) var isDemoMode = false
    @Published private(set) var demoStep: Int = 0
    @Published private(set) var demoLog: [String] = []
    private let meshController: MeshController
    private let mock: MockMeshTransport

    init(meshController: MeshController, mock: MockMeshTransport) {
        self.meshController = meshController
        self.mock = mock
        if let data = UserDefaults.standard.object(forKey: "resilix.demoMode") as? Bool {
            isDemoMode = data
        }
    }

    func setDemo(_ enabled: Bool) {
        isDemoMode = enabled
        UserDefaults.standard.set(enabled, forKey: "resilix.demoMode")
        if enabled {
            startDemo()
        } else {
            reset()
        }
    }

    func startDemo() {
        guard isDemoMode else { return }
        demoLog = [L("Demo: simulated nodes A (source), B (relay), C (destination)")]
        Task {
            mock.simulatePeer(MeshNode(id: "A", alias: "Node A", lastSeen: Date(), isRelay: false))
            mock.simulatePeer(MeshNode(id: "B", alias: "Relay B", lastSeen: Date(), isRelay: true))
            mock.simulatePeer(MeshNode(id: "C", alias: "Node C", lastSeen: Date(), isRelay: false))
        }
    }

    /// Sends a packet through the simulated transport.
    func sendDemoMessage() async {
        let text = L("Need help at the north shelter")
        demoLog.append(L("Demo: creating a chat packet for Node C"))
        do {
            let packet = try await meshController.sendPlainPacket(type: .chat,
                                                                 payload: Data(text.utf8),
                                                                 destination: "C",
                                                                 priority: .normal)
            demoLog.append(String(format: L("Packet %@ handed to the simulated transport"), String(packet.id.prefix(8))))
            demoLog.append(L("Delivery is reported only when the peer acknowledges the packet"))
        } catch {
            demoLog.append(String(format: L("Demo failed: %@"), error.localizedDescription))
        }
    }

    func reset() {
        demoLog = []
        demoStep = 0
    }
}
