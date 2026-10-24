import Foundation

enum ResilixError: LocalizedError, Equatable {
    case transportUnavailable(String)
    case routingNoRoute
    case packetExpired
    case packetDuplicate
    case packetMalformed(String)
    case packetTooLarge
    case ttlExceeded
    case securityInvalidSignature
    case securityDecryptionFailed
    case persistenceFailed(String)
    case permissionDenied(String)
    case queueFull
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .transportUnavailable(let t): return "Transport unavailable: \(t). Check Bluetooth and local network permissions."
        case .routingNoRoute: return "No viable mesh path is currently available."
        case .packetExpired: return "Message expired before delivery."
        case .packetDuplicate: return "Duplicate packet ignored."
        case .packetMalformed(let r): return "Invalid packet: \(r)"
        case .packetTooLarge: return "Packet exceeds size limit."
        case .ttlExceeded: return "Packet hop limit reached."
        case .securityInvalidSignature: return "Message authentication failed."
        case .securityDecryptionFailed: return "Could not decrypt message."
        case .persistenceFailed(let m): return "Could not save data: \(m)"
        case .permissionDenied(let p): return "Permission denied: \(p)"
        case .queueFull: return "Forwarding queue is full. Try again shortly."
        case .unsupportedVersion: return "Unsupported protocol version."
        }
    }
}
