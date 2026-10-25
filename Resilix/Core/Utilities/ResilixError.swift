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
        case .transportUnavailable(let t): return String(format: L("Transport unavailable: %@. Check Bluetooth and local network permissions."), t)
        case .routingNoRoute: return L("No viable mesh path is currently available.")
        case .packetExpired: return L("Message expired before delivery.")
        case .packetDuplicate: return L("Duplicate packet ignored.")
        case .packetMalformed(let r): return String(format: L("Invalid packet: %@"), r)
        case .packetTooLarge: return L("Packet exceeds size limit.")
        case .ttlExceeded: return L("Packet hop limit reached.")
        case .securityInvalidSignature: return L("Message authentication failed.")
        case .securityDecryptionFailed: return L("Could not decrypt message.")
        case .persistenceFailed(let m): return String(format: L("Could not save data: %@"), m)
        case .permissionDenied(let p): return String(format: L("Permission denied: %@"), p)
        case .queueFull: return L("Forwarding queue is full. Try again shortly.")
        case .unsupportedVersion: return L("Unsupported protocol version.")
        }
    }
}
