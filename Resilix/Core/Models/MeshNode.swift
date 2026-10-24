import Foundation

/// A peer that was discovered in the mesh.
struct MeshNode: Codable, Sendable, Equatable, Identifiable, Hashable {
    var id: String
    var alias: String // privacy-safe like "Node 41"
    var displayName: String?
    var lastSeen: Date
    var isRelay: Bool
    var transportHint: String?
    /// Approximate position the peer shared (only when it opted in).
    var latitude: Double?
    /// Approximate position the peer shared (only when it opted in).
    var longitude: Double?

    var hasLocation: Bool { latitude != nil && longitude != nil }
}
