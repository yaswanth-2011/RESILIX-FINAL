import Foundation

/// An encrypted payload that can be opened by one or more peers.
///
/// The envelope is sealed once per recipient with a key derived from an
/// ephemeral-static ECDH agreement between the two devices. Relays only
/// ever see this opaque blob, never the plaintext.
struct SecureEnvelope: Codable, Sendable, Equatable {
    struct Seal: Codable, Sendable, Equatable {
        var peerID: String
        var box: Data
    }

    var version: UInt8 = 1
    /// Public key of the sender (used to derive the shared secret).
    var senderPublicKey: Data
    /// One sealed copy per recipient.
    var seals: [Seal]

    func seal(for peerID: String) -> Data? {
        seals.first(where: { $0.peerID == peerID })?.box
    }

    var recipientIDs: [String] { seals.map(\.peerID) }
}
