import Foundation

/// Payload of an `acknowledgement` packet.
struct MeshAcknowledgement: Codable, Sendable, Equatable {
    /// Identifier of the packet that is acknowledged.
    var packetID: String
    /// Number of hops the acknowledged packet travelled.
    var hopCount: Int
    /// Human readable route, e.g. "A -> B -> C".
    var route: String
    /// True when the acknowledgement was produced by the final recipient.
    var delivered: Bool
}

/// Control block of the chunked media transfer protocol.
struct MediaTransferControl: Codable, Sendable, Equatable {
    enum Action: String, Codable, Sendable {
        case offer      // sender announces a transfer
        case accept     // receiver is ready
        case reject     // receiver refuses (storage / size)
        case cancel     // transfer aborted
        case complete   // all chunks received and verified
    }

    var action: Action
    var transferID: String
    var fileName: String
    var mimeType: String
    var byteCount: Int
    var chunkSize: Int
    var chunkIndex: Int
    var sha256: String?
    var messageID: String?
}
