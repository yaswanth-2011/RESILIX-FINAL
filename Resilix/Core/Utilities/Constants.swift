import Foundation

enum ResilixConstants {
    static let serviceType = "resilix-mesh"
    static let protocolVersion: UInt8 = 2
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

    // MARK: - Networking
    /// Bonjour service type used for peer-to-peer Wi-Fi discovery.
    static let bonjourServiceType = "_resilix._tcp"
    /// Bonjour service type used for Wi-Fi Aware discovery.
    static let bonjourServiceTypeAware = "_resilix-aware._tcp"
    /// Negotiated BLE MTU payload size (ATT payload after the 3 byte header).
    static let bleMTU = 180
    /// Largest frame written to a BLE characteristic in one go.
    static let bleMaxFrameBytes = 160
    /// Chunk size used by the media transfer protocol.
    static let mediaChunkSize = 16 * 1024
    /// Hard limit for a single media transfer (bytes).
    static let maxMediaBytes = 64 * 1024 * 1024
    /// Maximum number of hops a packet may take.
    static let maxHops = 6
    /// Number of packets a single source may inject per minute.
    static let relayRateLimitPerMinute = 60
    /// Maximum number of packets kept in the persistent forwarding queue.
    static let maxPersistedQueueSize = 200

    // MARK: - Media
    /// Directory (inside application support) that stores received media.
    static let mediaDirectoryName = "Media"
    /// Directory that stores the local profile photo.
    static let profileDirectoryName = "Profile"
    /// Directory that stores downloaded map packs.
    static let mapDirectoryName = "Maps"
    /// Directory that stores downloaded AI models.
    static let modelDirectoryName = "Models"

    // MARK: - Identity
    /// Default alias used when a node has not chosen a name yet.
    static let defaultAlias = "Resilix Node"
}
