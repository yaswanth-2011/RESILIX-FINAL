import Foundation

struct MeshNode: Codable, Sendable, Equatable, Identifiable, Hashable {
    var id: String
    var alias: String // privacy-safe like "Node 41"
    var displayName: String?
    var lastSeen: Date
    var isRelay: Bool
    var transportHint: String?
}
