import Foundation

/// Stores the conversations and moves the chat payloads through the mesh.
///
/// The service owns the message list, the delivery bookkeeping and the
/// persistence. It never fabricates a delivery: a message is only marked
/// as *delivered* when the peer acknowledged the packet.
@MainActor
final class MessageService: ObservableObject {
    @Published private(set) var messages: [MeshMessage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastErrorMessage: String?

    private let persistence = PersistenceController.shared
    private let meshController: MeshController
    private let transferService: TransferService

    init(meshController: MeshController, transferService: TransferService) {
        self.meshController = meshController
        self.transferService = transferService
        Task { await load() }
    }

    // MARK: - Persistence

    func load() async {
        isLoading = true
        messages = await persistence.loadMessages()
        isLoading = false
    }

    private func persist() async {
        try? await persistence.saveMessages(messages)
    }

    // MARK: - Reading

    /// All messages of one conversation, newest last.
    func messages(in threadID: String) -> [MeshMessage] {
        messages.filter { $0.threadID == threadID }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Distinct conversations, newest first.
    var conversations: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for message in messages.sorted(by: { $0.createdAt > $1.createdAt }) {
            if seen.insert(message.threadID).inserted { result.append(message.threadID) }
        }
        return result
    }

    // MARK: - Sending

    /// Sends a text message to a peer (or to everybody when the destination
    /// is empty).
    @discardableResult
    func send(text: String,
              to destination: String,
              from source: String,
              expiry: TimeInterval? = nil,
              priority: PacketPriority = .normal) async throws -> MeshMessage {
        let message = MeshMessage(id: UUID().uuidString,
                                  packetID: nil,
                                  threadID: destination.isEmpty ? "broadcast" : destination,
                                  sourceNodeID: source,
                                  destinationNodeID: destination,
                                  text: text,
                                  createdAt: Date(),
                                  deliveryState: .queued,
                                  expirySeconds: expiry,
                                  lastRoute: nil,
                                  priority: priority,
                                  kind: .text,
                                  senderAlias: nil,
                                  isOutgoing: true)
        messages.append(message)
        await persist()
        try await transmit(message)
        return message
    }

    /// Sends a message that carries media metadata. The bytes themselves are
    /// transferred with the chunked media protocol.
    @discardableResult
    func sendMedia(kind: MessageKind,
                   attachment: AttachmentDescriptor,
                   text: String,
                   to destination: String,
                   from source: String) async throws -> MeshMessage {
        let message = MeshMessage(id: UUID().uuidString,
                                  packetID: nil,
                                  threadID: destination.isEmpty ? "broadcast" : destination,
                                  sourceNodeID: source,
                                  destinationNodeID: destination,
                                  text: text,
                                  createdAt: Date(),
                                  deliveryState: .queued,
                                  expirySeconds: ResilixConstants.packetExpirySeconds,
                                  lastRoute: nil,
                                  priority: .high,
                                  kind: kind,
                                  attachment: attachment,
                                  senderAlias: nil,
                                  isOutgoing: true,
                                  transferProgress: TransferProgress(status: .preparing,
                                                                    sentBytes: 0,
                                                                    totalBytes: attachment.byteCount,
                                                                    errorMessage: nil))
        messages.append(message)
        await persist()
        try await transmit(message)
        return message
    }

    /// Sends the already prepared message through the mesh.
    private func transmit(_ message: MeshMessage) async throws {
        let payload = try JSONEncoder().encode(message)
        let packet = try await meshController.sendSecurePacket(type: .chat,
                                                              plaintext: payload,
                                                              destination: message.destinationNodeID,
                                                              priority: message.priority,
                                                              expiry: message.expirySeconds ?? ResilixConstants.packetExpirySeconds)
        update(messageID: message.id) { stored in
            stored.packetID = packet.id
            if stored.deliveryState == .queued { stored.deliveryState = .sending }
        }
    }

    /// Retries a failed message (used by the "retry" action).
    func retry(id: String) async {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let message = messages[index]
        update(messageID: id) { $0.deliveryState = .queued }
        do {
            try await transmit(message)
        } catch {
            update(messageID: id) { $0.deliveryState = .failed }
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Receiving

    /// Handles a payload that was decrypted by the mesh controller.
    func handleIncoming(_ delivered: DeliveredPayload) async {
        guard let message = try? JSONDecoder().decode(MeshMessage.self, from: delivered.plaintext) else {
            lastErrorMessage = "A received message could not be read."
            return
        }
        // Ignore our own echo.
        guard message.sourceNodeID != meshController.localNodeID else { return }

        if let existingIndex = messages.firstIndex(where: { $0.id == message.id }) {
            messages[existingIndex] = message
        } else {
            messages.append(message)
        }
        await persist()
    }

    // MARK: - Delivery bookkeeping

    /// Called by the mesh controller whenever the delivery state changes.
    func updateDelivery(packetID: String, state: DeliveryState) async {
        guard let index = messages.firstIndex(where: { $0.packetID == packetID }) else { return }
        messages[index].deliveryState = state
        if state == .delivered, messages[index].lastRoute == nil {
            messages[index].lastRoute = "direct"
        }
        await persist()
    }

    private func update(messageID: String, _ change: (inout MeshMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        change(&messages[index])
        Task { await persist() }
    }

    func delete(id: String) async {
        messages.removeAll { $0.id == id }
        await persist()
    }

    func deleteThread(_ threadID: String) async {
        messages.removeAll { $0.threadID == threadID }
        await persist()
    }
}
