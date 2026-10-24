import Foundation

/// Registry of the peers this device currently knows about.
actor MeshPeerRegistry {
    private var peers: [String: MeshNode] = [:]
    private var transports: [String: MeshTransportKind] = [:]

    func update(_ node: MeshNode) {
        peers[node.id] = node
    }

    func update(_ node: MeshNode, transport: MeshTransportKind) {
        peers[node.id] = node
        transports[node.id] = transport
    }

    func remove(_ id: String) {
        peers.removeValue(forKey: id)
        transports.removeValue(forKey: id)
    }

    func peer(_ id: String) -> MeshNode? { peers[id] }

    func allPeers() -> [MeshNode] { Array(peers.values) }

    func connectedCount() -> Int { peers.count }

    func transport(for id: String) -> MeshTransportKind? { transports[id] }

    /// Removes peers that were not seen for a while.
    @discardableResult
    func prune(olderThan interval: TimeInterval) -> Int {
        let cutoff = Date().addingTimeInterval(-interval)
        let stale = peers.filter { $0.value.lastSeen < cutoff }.map(\.key)
        for key in stale {
            peers.removeValue(forKey: key)
            transports.removeValue(forKey: key)
        }
        return stale.count
    }
}
