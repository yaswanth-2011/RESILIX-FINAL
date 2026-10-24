import Foundation

/// A single chat message stored on the device.
///
/// The struct is persisted as JSON inside `messages.json`, therefore the
/// decoding initialiser is written by hand: it tolerates documents written
/// by older builds (missing keys) so that upgrading the app never loses
/// conversation history.
struct MeshMessage: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var packetID: String?
    var threadID: String // destination node or group
    var sourceNodeID: String
    var destinationNodeID: String
    var text: String
    var createdAt: Date
    var deliveryState: DeliveryState
    var expirySeconds: TimeInterval?
    var lastRoute: String? // e.g. "A -> B -> C"
    var priority: PacketPriority

    // MARK: - Added by the functional implementation
    /// Payload kind (text / voice / image / video / file).
    var kind: MessageKind = .text
    /// Media metadata for non-text payloads.
    var attachment: AttachmentDescriptor?
    /// Display name of the sender (peer alias / contact name).
    var senderAlias: String?
    /// True when this device created the message.
    var isOutgoing: Bool = true
    /// Live progress for media transfers.
    var transferProgress: TransferProgress?
    /// Identifier of the message this one replies to.
    var replyToID: String?

    init(id: String,
         packetID: String?,
         threadID: String,
         sourceNodeID: String,
         destinationNodeID: String,
         text: String,
         createdAt: Date,
         deliveryState: DeliveryState,
         expirySeconds: TimeInterval?,
         lastRoute: String?,
         priority: PacketPriority,
         kind: MessageKind = .text,
         attachment: AttachmentDescriptor? = nil,
         senderAlias: String? = nil,
         isOutgoing: Bool = true,
         transferProgress: TransferProgress? = nil,
         replyToID: String? = nil) {
        self.id = id
        self.packetID = packetID
        self.threadID = threadID
        self.sourceNodeID = sourceNodeID
        self.destinationNodeID = destinationNodeID
        self.text = text
        self.createdAt = createdAt
        self.deliveryState = deliveryState
        self.expirySeconds = expirySeconds
        self.lastRoute = lastRoute
        self.priority = priority
        self.kind = kind
        self.attachment = attachment
        self.senderAlias = senderAlias
        self.isOutgoing = isOutgoing
        self.transferProgress = transferProgress
        self.replyToID = replyToID
    }

    // MARK: - Backwards compatible decoding
    private enum CodingKeys: String, CodingKey {
        case id, packetID, threadID, sourceNodeID, destinationNodeID, text
        case createdAt, deliveryState, expirySeconds, lastRoute, priority
        case kind, attachment, senderAlias, isOutgoing, transferProgress, replyToID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        packetID = try container.decodeIfPresent(String.self, forKey: .packetID)
        threadID = try container.decodeIfPresent(String.self, forKey: .threadID) ?? ""
        sourceNodeID = try container.decodeIfPresent(String.self, forKey: .sourceNodeID) ?? ""
        destinationNodeID = try container.decodeIfPresent(String.self, forKey: .destinationNodeID) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        deliveryState = try container.decodeIfPresent(DeliveryState.self, forKey: .deliveryState) ?? .queued
        expirySeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .expirySeconds)
        lastRoute = try container.decodeIfPresent(String.self, forKey: .lastRoute)
        priority = try container.decodeIfPresent(PacketPriority.self, forKey: .priority) ?? .normal
        kind = try container.decodeIfPresent(MessageKind.self, forKey: .kind) ?? .text
        attachment = try container.decodeIfPresent(AttachmentDescriptor.self, forKey: .attachment)
        senderAlias = try container.decodeIfPresent(String.self, forKey: .senderAlias)
        isOutgoing = try container.decodeIfPresent(Bool.self, forKey: .isOutgoing) ?? true
        transferProgress = try container.decodeIfPresent(TransferProgress.self, forKey: .transferProgress)
        replyToID = try container.decodeIfPresent(String.self, forKey: .replyToID)
    }

    /// Short preview used by conversation lists.
    var previewText: String {
        switch kind {
        case .text:
            return text
        case .voice:
            return "🎤 Voice message"
        case .image:
            return "🖼 \(attachment?.fileName ?? "Photo")"
        case .video:
            return "🎬 \(attachment?.fileName ?? "Video")"
        case .file:
            return "📎 \(attachment?.fileName ?? "File")"
        }
    }
}
