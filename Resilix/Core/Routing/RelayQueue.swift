import Foundation

struct QueuedPacket: Codable, Sendable, Equatable {
    var packet: MeshPacket
    var enqueueTime: Date
    var retryCount: Int
    var nextRetry: Date
}

actor RelayQueue {
    private var queue: [QueuedPacket] = []
    private let maxLength: Int
    private let maxBytes: Int
    init(maxLength: Int = ResilixConstants.maxQueueSize, maxBytes: Int = ResilixConstants.maxQueueBytes) {
        self.maxLength = maxLength; self.maxBytes = maxBytes
    }
    var count: Int { queue.count }
    var totalBytes: Int { queue.reduce(0){$0 + $1.packet.payloadEnvelope.count } }

    func enqueue(_ packet: MeshPacket) throws {
        guard queue.count < maxLength else { throw ResilixError.queueFull }
        guard totalBytes + packet.payloadEnvelope.count <= maxBytes else { throw ResilixError.queueFull }
        // priority insert: SOS first
        let qp = QueuedPacket(packet: packet, enqueueTime: Date(), retryCount: 0, nextRetry: Date())
        if packet.priority == .sos {
            if let idx = queue.firstIndex(where: {$0.packet.priority != .sos}) { queue.insert(qp, at: idx) }
            else { queue.append(qp) }
        } else {
            queue.append(qp)
            queue.sort { $0.packet.priority.rawValue > $1.packet.priority.rawValue || ($0.packet.priority==$1.packet.priority && $0.enqueueTime < $1.enqueueTime) }
        }
    }
    func dequeue() -> QueuedPacket? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }
    func peek() -> QueuedPacket? { queue.first }
    func removeExpired(now: Date = Date()) -> Int {
        let before = queue.count
        queue.removeAll { $0.packet.isExpired || now > $0.packet.expiresAt }
        return before - queue.count
    }
    func incrementRetry(for id: String) {
        if let i = queue.firstIndex(where: {$0.packet.id==id}) {
            queue[i].retryCount += 1
            queue[i].nextRetry = Date().addingTimeInterval(pow(2.0, Double(queue[i].retryCount))*2)
        }
    }
    func all() -> [QueuedPacket] { queue }
    func clear() { queue.removeAll() }
}
