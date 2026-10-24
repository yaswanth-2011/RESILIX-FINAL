import Foundation

/// Delivery state of a message.
enum DeliveryState: String, Codable, Sendable, CaseIterable {
    case draft
    case queued
    case sending
    case relaying
    case delivered
    case expired
    case failed
    case cancelled

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
