import Foundation

actor MeshPeerRegistry {
    private var peers: [String: MeshNode] = [:]
    func update(_ node: MeshNode) { peers[node.id] = node }
    func remove(_ id: String) { peers.removeValue(forKey: id) }
    func peer(_ id: String) -> MeshNode? { peers[id] }
    func allPeers() -> [MeshNode] { Array(peers.values) }
    func connectedCount() -> Int { peers.count }
}
