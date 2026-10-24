import Foundation

/// Keeps the identifiers of the packets that were already processed.
///
/// The store is the loop breaker of the mesh: a packet that arrives twice
/// (for example because it was forwarded by two different neighbours) is
/// only handled once. The identifiers are persisted so that a restart does
/// not re-deliver old messages.
actor DeduplicationStore {
    private var seen: [String: Date] = [:]
    private let maxSize: Int
    private let persistence = PersistenceController.shared
    private let fileName = "dedup_store.json"

    init(maxSize: Int = ResilixConstants.dedupCacheSize) { self.maxSize = maxSize }

    func isDuplicate(_ packetID: String) -> Bool { seen[packetID] != nil }

    @discardableResult
    func insert(_ packetID: String) -> Bool {
        if seen[packetID] != nil { return false }
        if seen.count >= maxSize,
           let oldest = seen.min(by: { $0.value < $1.value })?.key {
            seen.removeValue(forKey: oldest)
        }
        seen[packetID] = Date()
        return true
    }

    func purgeExpired(olderThan interval: TimeInterval = 600) {
        let cutoff = Date().addingTimeInterval(-interval)
        seen = seen.filter { $0.value > cutoff }
    }

    func count() -> Int { seen.count }

    // MARK: - Persistence

    func persist() async {
        let payload = seen.map { PacketSeen(id: $0.key, seenAt: $0.value) }
        try? await persistence.save(Array(payload), to: fileName)
    }

    @discardableResult
    func restore() async -> Int {
        let stored: [PacketSeen] = await persistence.loadIfExists([PacketSeen].self, from: fileName) ?? []
        seen = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0.seenAt) })
        purgeExpired()
        return seen.count
    }
}

/// Persisted representation of one "already seen" packet identifier.
struct PacketSeen: Codable, Sendable, Equatable {
    var id: String
    var seenAt: Date
}
