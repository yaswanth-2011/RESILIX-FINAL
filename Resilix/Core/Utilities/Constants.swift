import Foundation

enum ResilixConstants {
    static let serviceType = "resilix-mesh"
    static let protocolVersion: UInt8 = 1
    static let maxTTL: UInt8 = 16
    static let defaultTTL: UInt8 = 8
    static let maxPacketSizeBytes = 32_768
    static let maxQueueSize = 200
    static let maxQueueBytes = 2_000_000
    static let dedupCacheSize = 1024
    static let routeExpirySeconds: TimeInterval = 120
    static let packetExpirySeconds: TimeInterval = 300
    static let bleServiceUUID = "8A9E7B4C-1C2D-4E5F-9A8B-7C6D5E4F3A2B"
    static let bleCharacteristicUUID = "7B8A6C5D-2D3E-4F5A-8B9C-6D5E4F3A2B1C"
    static let appGroupID = "group.com.resilix.shared"
}
