import Foundation

actor DeduplicationStore {
    private var seen: [String: Date] = [:]
    private let maxSize: Int
    init(maxSize: Int = ResilixConstants.dedupCacheSize) { self.maxSize = maxSize }

    func isDuplicate(_ packetID: String) -> Bool { seen[packetID] != nil }

    @discardableResult
    func insert(_ packetID: String) -> Bool {
        if seen[packetID] != nil { return false }
        if seen.count >= maxSize, let oldest = seen.min(by: {$0.value < $1.value})?.key { seen.removeValue(forKey: oldest) }
        seen[packetID] = Date()
        return true
    }
    func purgeExpired(olderThan interval: TimeInterval = 600) {
        let cutoff = Date().addingTimeInterval(-interval)
        seen = seen.filter { $0.value > cutoff }
    }
    func count() -> Int { seen.count }
}
