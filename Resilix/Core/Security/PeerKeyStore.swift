import Foundation

/// Public identity of a peer as seen by this installation.
struct PeerIdentity: Codable, Sendable, Equatable, Identifiable {
    var id: String            // node identifier
    var agreementPublicKey: Data
    var signingPublicKey: Data
    var alias: String
    var firstSeen: Date
    var lastSeen: Date
    var isTrusted: Bool
}

/// Persistent store of the public keys of every peer this device has met.
///
/// Keys are *pinned*: the first public key seen for a node identifier is
/// remembered forever. If a peer later presents a different key it is
/// treated as an impersonation attempt and rejected, which is what stops a
/// relay (or a hostile node) from silently taking over somebody's identity.
actor PeerKeyStore {
    private var peers: [String: PeerIdentity] = [:]
    private let persistence = PersistenceController.shared
    private var loaded = false

    func load() async {
        guard !loaded else { return }
        loaded = true
        let stored: [PeerIdentity] = await persistence.loadIfExists([PeerIdentity].self, from: "peer_keys.json") ?? []
        for peer in stored { peers[peer.id] = peer }
    }

    /// Returns the pinned identity of a peer (nil when unknown).
    func identity(for peerID: String) async -> PeerIdentity? {
        await load()
        return peers[peerID]
    }

    /// Registers (or refreshes) a peer identity.
    ///
    /// - Throws: `ResilixError.securityInvalidSignature` when the peer
    ///   presents a key that differs from the pinned one.
    @discardableResult
    func register(peerID: String,
                  agreementPublicKey: Data,
                  signingPublicKey: Data,
                  alias: String) async throws -> PeerIdentity {
        await load()
        if let existing = peers[peerID] {
            guard existing.agreementPublicKey == agreementPublicKey,
                  existing.signingPublicKey == signingPublicKey else {
                throw ResilixError.securityInvalidSignature
            }
            var updated = existing
            updated.lastSeen = Date()
            if !alias.isEmpty && existing.alias != alias { updated.alias = alias }
            peers[peerID] = updated
            await persist()
            return updated
        }
        let identity = PeerIdentity(id: peerID,
                                    agreementPublicKey: agreementPublicKey,
                                    signingPublicKey: signingPublicKey,
                                    alias: alias,
                                    firstSeen: Date(),
                                    lastSeen: Date(),
                                    isTrusted: false)
        peers[peerID] = identity
        await persist()
        return identity
    }

    func markSeen(peerID: String) async {
        await load()
        guard var peer = peers[peerID] else { return }
        peer.lastSeen = Date()
        peers[peerID] = peer
        await persist()
    }

    func setTrusted(_ trusted: Bool, peerID: String) async {
        await load()
        guard var peer = peers[peerID] else { return }
        peer.isTrusted = trusted
        peers[peerID] = peer
        await persist()
    }

    func remove(peerID: String) async {
        await load()
        peers.removeValue(forKey: peerID)
        await persist()
    }

    func allIdentities() async -> [PeerIdentity] {
        await load()
        return Array(peers.values).sorted { $0.lastSeen > $1.lastSeen }
    }

    private func persist() async {
        try? await persistence.save(Array(peers.values), to: "peer_keys.json")
    }
}
