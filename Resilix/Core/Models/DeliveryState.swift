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
        case .draft: return L("delivery.draft")
        case .queued: return L("delivery.queued")
        case .sending: return L("delivery.sending")
        case .relaying: return L("delivery.relaying")
        case .delivered: return L("delivery.delivered")
        case .expired: return L("delivery.expired")
        case .failed: return L("delivery.failed")
        case .cancelled: return L("delivery.cancelled")
        }
    }
}
