import Foundation

enum DeliveryState: String, Codable, Sendable, CaseIterable {
    case draft, queued, sending, relaying, delivered, expired, failed, cancelled
    var label: String {
        switch self {
        case .draft: return "Draft"
        case .queued: return "Queued for mesh"
        case .sending: return "Sending"
        case .relaying: return "Relaying"
        case .delivered: return "Delivered"
        case .expired: return "Expired"
        case .failed: return "No route available"
        case .cancelled: return "Cancelled"
        }
    }
}

struct MeshMessage: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var packetID: String?
    var threadID: String // destination node or group
    var sourceNodeID: String
    var destinationNodeID: String
    var text: String
    var createdAt: Date
    var deliveryState: DeliveryState
    var expirySeconds: TimeInterval?
    var lastRoute: String? // e.g. "A -> B -> C"
    var priority: PacketPriority
}
