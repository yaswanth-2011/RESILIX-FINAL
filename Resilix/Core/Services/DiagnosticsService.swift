import Foundation
import Combine

@MainActor
class DiagnosticsService: ObservableObject {
    @Published var snapshot: DiagnosticsSnapshot = DiagnosticsSnapshot(
        timestamp: Date(),
        bluetoothState: "Unknown",
        p2pWiFiState: "Unknown",
        wifiAwareState: L("Not supported on this device"),
        connectedCount: 0,
        discoveredCount: 0,
        routeCount: 0,
        queueCount: 0,
        forwardedCount: 0,
        droppedDuplicates: 0,
        expiredCount: 0,
        relayActive: false,
        protocolVersion: ResilixConstants.protocolVersion,
        persistenceStatus: "OK",
        permissionStatus: "Unknown",
        lastTransportEvent: nil,
        isDemo: false
    )
    
    private var duplicateDrops = 0
    private var expiredPackets = 0
    private var lastEvent: String? = nil
    
    func refresh(
        transports: [any MeshTransport],
        queueCount: Int,
        relayActive: Bool,
        isDemo: Bool,
        routingEngine: MeshRoutingEngine? = nil,
        relayManager: RelayManager? = nil
    ) async {
        var bt = "Unavailable"
        var p2p = "Unavailable"
        var aware = L("Not supported on this device")
        var discovered = 0
        
        for t in transports {
            switch t.transportKind {
            case .bluetooth:
                bt = t.isAvailable ? "Available" : "Unavailable"
                discovered += t.discoveredPeers.count
            case .peerToPeerWiFi:
                p2p = t.isAvailable ? "Available" : "Unavailable"
                discovered += t.discoveredPeers.count
            case .wifiAware:
                aware = t.isAvailable ? "Available" : L("Not supported on this device")
                discovered += t.discoveredPeers.count
            default:
                break
            }
        }
        
        let routeCount = routingEngine?.routes.count ?? 0
        let forwarded = relayManager?.forwardedCount ?? 0
        let queue = queueCount
        
        snapshot = DiagnosticsSnapshot(
            timestamp: Date(),
            bluetoothState: bt,
            p2pWiFiState: p2p,
            wifiAwareState: aware,
            connectedCount: discovered,
            discoveredCount: discovered,
            routeCount: routeCount,
            queueCount: queue,
            forwardedCount: forwarded,
            droppedDuplicates: duplicateDrops,
            expiredCount: expiredPackets,
            relayActive: relayActive,
            protocolVersion: ResilixConstants.protocolVersion,
            persistenceStatus: "OK",
            permissionStatus: "Authorized",
            lastTransportEvent: lastEvent ?? L("Mesh idle"),
            isDemo: isDemo
        )
    }
    
    func recordDuplicateDrop() { duplicateDrops += 1 }
    func recordExpiredPacket() { expiredPackets += 1 }
    func recordTransportEvent(_ event: String) { lastEvent = event }
    
    func reset() {
        duplicateDrops = 0
        expiredPackets = 0
        lastEvent = nil
    }
}
