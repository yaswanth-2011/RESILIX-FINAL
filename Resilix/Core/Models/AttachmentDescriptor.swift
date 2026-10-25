import Foundation

/// Kind of payload carried by a mesh message.
///
/// The enum is stored as a raw string so persisted messages stay readable
/// and so unknown (newer) kinds can be ignored by older builds instead of
/// failing to decode.
enum MessageKind: String, Codable, Sendable, CaseIterable {
    case text
    case voice
    case image
    case video
    case file

    var label: String {
        switch self {
        case .text: return L("message.kind.text")
        case .voice: return L("message.kind.voice")
        case .image: return L("message.kind.image")
        case .video: return L("message.kind.video")
        case .file: return L("message.kind.file")
        }
    }

    var systemImage: String {
        switch self {
        case .text: return "text.bubble"
        case .voice: return "waveform"
        case .image: return "photo"
        case .video: return "film"
        case .file: return "doc"
        }
    }
}

/// Metadata describing a media/voice payload that travels over the mesh.
///
/// Only lightweight metadata is stored inside the JSON message body; the
/// bytes themselves live in the application support directory and are
/// transferred with the chunked media protocol (see `TransferService`).
struct AttachmentDescriptor: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var fileName: String
    var mimeType: String
    var byteCount: Int
    /// File name inside the `Media` directory (application support).
    var localFileName: String?
    /// Hex encoded SHA-256 of the payload, verified after a transfer.
    var sha256: String?
    /// Duration for voice notes.
    var durationSeconds: Double?
    /// Thumbnail file name for image/video previews.
    var thumbnailFileName: String?
    /// Identifier of the transfer that carries the bytes.
    var transferID: String?

    init(id: String = UUID().uuidString,
         fileName: String,
         mimeType: String,
         byteCount: Int,
         localFileName: String? = nil,
         sha256: String? = nil,
         durationSeconds: Double? = nil,
         thumbnailFileName: String? = nil,
         transferID: String? = nil) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.localFileName = localFileName
        self.sha256 = sha256
        self.durationSeconds = durationSeconds
        self.thumbnailFileName = thumbnailFileName
        self.transferID = transferID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? "attachment"
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType) ?? "application/octet-stream"
        byteCount = try container.decodeIfPresent(Int.self, forKey: .byteCount) ?? 0
        localFileName = try container.decodeIfPresent(String.self, forKey: .localFileName)
        sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        thumbnailFileName = try container.decodeIfPresent(String.self, forKey: .thumbnailFileName)
        transferID = try container.decodeIfPresent(String.self, forKey: .transferID)
    }
}

/// Progress of a chunked media transfer.
struct TransferProgress: Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable {
        case none
        case preparing
        case transferring
        case completed
        case failed
        case cancelled
    }

    var status: Status = .none
    var sentBytes: Int = 0
    var totalBytes: Int = 0
    var errorMessage: String?

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(sentBytes) / Double(totalBytes))
    }

    var isActive: Bool { status == .preparing || status == .transferring }
}
