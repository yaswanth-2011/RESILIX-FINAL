import Foundation
enum MeshConnectionState: String, Codable, Sendable {
    case disconnected, connecting, connected, failed
}
