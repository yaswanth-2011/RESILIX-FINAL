import Foundation

struct QueuedPacket: Codable, Sendable, Equatable {
    var packet: MeshPacket
    var enqueueTime: Date
    var retryCount: Int
    var nextRetry: Date
}

/// Persistent store-and-forward queue.
///
/// Packets that cannot be delivered yet (no route, peer offline) stay in the
/// queue until a route appears, the packet expires, or the retry budget is
/// exhausted. The queue is written to disk so that a message survives an
/// app restart and is resumed automatically once the device reconnects.
actor RelayQueue {
    private var queue: [QueuedPacket] = []
    private let maxLength: Int
    private let maxBytes: Int
    private let persistence = PersistenceController.shared
    private let fileName = "relay_queue.json"

    init(maxLength: Int = ResilixConstants.maxQueueSize, maxBytes: Int = ResilixConstants.maxQueueBytes) {
        self.maxLength = maxLength
        self.maxBytes = maxBytes
    }

    var count: Int { queue.count }
    var totalBytes: Int { queue.reduce(0) { $0 + $1.packet.payloadEnvelope.count } }

    func enqueue(_ packet: MeshPacket) throws {
        guard queue.count < maxLength else { throw ResilixError.queueFull }
        guard totalBytes + packet.payloadEnvelope.count <= maxBytes else { throw ResilixError.queueFull }
        if queue.contains(where: { $0.packet.id == packet.id }) { return }
        let qp = QueuedPacket(packet: packet, enqueueTime: Date(), retryCount: 0, nextRetry: Date())
        if packet.priority == .sos {
            if let idx = queue.firstIndex(where: { $0.packet.priority != .sos }) {
                queue.insert(qp, at: idx)
            } else {
                queue.append(qp)
            }
        } else {
            queue.append(qp)
            queue.sort {
                $0.packet.priority.rawValue > $1.packet.priority.rawValue
                    || ($0.packet.priority == $1.packet.priority && $0.enqueueTime < $1.enqueueTime)
            }
        }
        await persist()
    }

    func dequeue() -> QueuedPacket? {
        guard !queue.isEmpty else { return nil }
        let item = queue.removeFirst()
        await persist()
        return item
    }

    func peek() -> QueuedPacket? { queue.first }

    /// Removes a packet from the queue (after it was delivered).
    func dequeueMatching(id: String) {
        let before = queue.count
        queue.removeAll { $0.packet.id == id }
        if before != queue.count { await persist() }
    }

    @discardableResult
    func removeExpired(now: Date = Date()) -> Int {
        let before = queue.count
        queue.removeAll { $0.packet.isExpired || now > $0.packet.expiresAt }
        if before != queue.count { await persist() }
        return before - queue.count
    }

    func incrementRetry(for id: String) {
        if let i = queue.firstIndex(where: { $0.packet.id == id }) {
            queue[i].retryCount += 1
            queue[i].nextRetry = Date().addingTimeInterval(pow(2.0, Double(queue[i].retryCount)) * 2)
        }
    }

    func all() -> [QueuedPacket] { queue }
    func clear() { queue.removeAll() }

    /// Items whose backoff timer elapsed.
    func ready(now: Date = Date()) -> [QueuedPacket] {
        queue.filter { $0.nextRetry <= now }
    }

    // MARK: - Persistence

    func persist() async {
        let trimmed = Array(queue.prefix(ResilixConstants.maxPersistedQueueSize))
        try? await persistence.save(trimmed, to: fileName)
    }

    /// Restores the queue from disk (called on launch).
    @discardableResult
    func restore() async -> Int {
        let stored: [QueuedPacket] = await persistence.loadIfExists([QueuedPacket].self, from: fileName) ?? []
        queue = stored.filter { !$0.packet.isExpired }
        if queue.count != stored.count { await persist() }
        return queue.count
    }
}
