import Foundation
import Combine

@MainActor
class RelayManager: ObservableObject {
    @Published var isRelayActive = false
    @Published var forwardedCount = 0
    @Published var bytesForwarded = 0
    @Published var nearbyRelayPeers = 0
    @Published var upstreamPeers: [String] = []
    @Published var downstreamPeers: [String] = []
    private var perSourceCount: [String: Int] = [:]
    private var rateLimitWindow: Date = Date()
    private let persistence = PersistenceController.shared
    private let maxPerWindow = 20
    private let windowDuration: TimeInterval = 60 // 1 minute

    init() {
        Task { @MainActor in
            let settings = await persistence.loadSettings()
            self.isRelayActive = settings.relayEnabled
        }
    }

    func setRelay(_ active: Bool) async {
        isRelayActive = active
        var s = await persistence.loadSettings()
        s.relayEnabled = active
        try? await persistence.saveSettings(s)
    }

    func shouldForward(packet: MeshPacket) -> Bool {
        guard isRelayActive else { return false }
        
        // Reset rate limit window
        if Date().timeIntervalSince(rateLimitWindow) > windowDuration {
            perSourceCount.removeAll()
            rateLimitWindow = Date()
        }
        
        // Per-source rate limit
        let count = perSourceCount[packet.sourceNodeID] ?? 0
        if count >= maxPerWindow { return false }
        perSourceCount[packet.sourceNodeID] = count + 1
        
        // Priority check - always allow SOS
        if packet.priority == .sos { return true }
        
        return true
    }

    func recordForwarded(bytes: Int, fromPeer: String? = nil, toPeer: String? = nil) {
        forwardedCount += 1
        bytesForwarded += bytes
        if let from = fromPeer, !upstreamPeers.contains(from) { upstreamPeers.append(from) }
        if let to = toPeer, !downstreamPeers.contains(to) { downstreamPeers.append(to) }
    }
    
    func updateNearbyPeers(_ peers: [MeshNode]) {
        nearbyRelayPeers = peers.filter { $0.isRelay }.count
    }
    
    func persistState() async {
        // State is persisted via settings; additional stats could be saved here
    }
    
    func resetCounters() {
        forwardedCount = 0
        bytesForwarded = 0
        upstreamPeers.removeAll()
        downstreamPeers.removeAll()
    }
}
