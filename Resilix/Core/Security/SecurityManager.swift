import Foundation
import CryptoKit
import Security

/// Device identity, key agreement and message authentication.
///
/// The manager owns two long term keys per installation, both stored in the
/// keychain (never in `UserDefaults` and never in the app container):
///
/// * a **Curve25519 key agreement** key, used to derive a shared secret with
///   every peer so that payloads can be sealed for exactly one recipient;
/// * a **Curve25519 signing** key, used to sign mesh packets so that *any*
///   node in the mesh (including a relay that cannot decrypt the payload)
///   can verify that a packet really originates from the claimed sender and
///   was not modified in transit.
actor SecurityManager {
    private static let keychainService = "com.resilix.identity"

    private let agreementAccount = "agreement"
    private let signingAccount = "signing"
    private let legacyAccount = "symKey"

    private var cachedAgreementKey: Curve25519.KeyAgreement.PrivateKey?
    private var cachedSigningKey: Curve25519.Signing.PrivateKey?
    private var nodeIdentifier: String = ""

    init() {}

    // MARK: - Identity

    /// Creates the long term identity keys if they do not exist yet.
    func setupIdentityIfNeeded(nodeID: String) async throws {
        nodeIdentifier = nodeID
        if cachedAgreementKey == nil { cachedAgreementKey = try loadOrCreateAgreementKey() }
        if cachedSigningKey == nil { cachedSigningKey = try loadOrCreateSigningKey() }
    }

    /// Agreement public key of this installation (safe to hand to peers).
    func agreementPublicKey() throws -> Data {
        let key = try agreementKey()
        return key.publicKey.rawRepresentation
    }

    /// Signing public key of this installation (safe to hand to peers).
    func signingPublicKey() throws -> Data {
        let key = try signingKey()
        return key.publicKey.rawRepresentation
    }

    /// Short, human comparable fingerprint of a public key (used for
    /// out-of-band pairing verification).
    func fingerprint(for publicKey: Data) -> String {
        let digest = Data(SHA256.hash(data: publicKey))
        let hex = digest.prefix(6).map { String(format: "%02X", $0) }.joined()
        return hex.chunked(every: 4).joined(separator: " ")
    }

    // MARK: - Session keys

    /// Derives the symmetric session key shared with a peer.
    ///
    /// The derivation is symmetric: both devices compute the same key from
    /// their own private key and the other device's public key, so no extra
    /// round trip is required before the first message.
    func sessionKey(peerID: String, peerPublicKey: Data) throws -> SymmetricKey {
        let privateKey = try agreementKey()
        let remote = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: remote)
        let orderedIDs = [nodeIdentifier, peerID].sorted().joined(separator: "|")
        let salt = Data(SHA256.hash(data: Data("resilix-session-v1".utf8) + Data(orderedIDs.utf8)))
        return shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: Data("resilix-chat-v1".utf8),
            outputByteCount: 32
        )
    }

    /// Seals `plaintext` for a single recipient.
    func seal(_ plaintext: Data, for peerID: String, peerPublicKey: Data) throws -> Data {
        let key = try sessionKey(peerID: peerID, peerPublicKey: peerPublicKey)
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else { throw ResilixError.securityDecryptionFailed }
        return combined
    }

    /// Opens a box produced by `seal(_:for:peerPublicKey:)`.
    func open(_ box: Data, from peerID: String, peerPublicKey: Data) throws -> Data {
        let key = try sessionKey(peerID: peerID, peerPublicKey: peerPublicKey)
        let sealedBox = try AES.GCM.SealedBox(combined: box)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - Signatures

    /// Signs the canonical bytes of a packet (origin authenticity).
    func sign(_ data: Data) throws -> Data {
        let key = try signingKey()
        return try key.signature(for: data)
    }

    /// Verifies a signature produced by `sign(_:)`.
    func verify(_ signature: Data, for data: Data, publicKey: Data) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else { return false }
        return key.isValidSignature(signature, for: data)
    }

    // MARK: - Device local encryption (legacy API, still used for local data)

    /// Encrypts data with the installation key. The returned ciphertext is a
    /// self contained AES-GCM box (nonce included).
    func encrypt(_ plaintext: Data) throws -> (ciphertext: Data, nonce: Data) {
        let key = try deviceKey()
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else { throw ResilixError.securityDecryptionFailed }
        let nonce = box.nonce
        return (combined, Data(nonce))
    }

    /// Decrypts a box produced by `encrypt(_:)`.
    func decrypt(_ combined: Data) throws -> Data {
        let key = try deviceKey()
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }

    /// HMAC-SHA256 helper used for transport level integrity tags.
    func hmac(_ data: Data, using key: SymmetricKey) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    // MARK: - Keychain plumbing

    private func agreementKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let cached = cachedAgreementKey { return cached }
        let key = try loadOrCreateAgreementKey()
        cachedAgreementKey = key
        return key
    }

    private func signingKey() throws -> Curve25519.Signing.PrivateKey {
        if let cached = cachedSigningKey { return cached }
        let key = try loadOrCreateSigningKey()
        cachedSigningKey = key
        return key
    }

    private func deviceKey() throws -> SymmetricKey {
        if let data = try loadKey(account: legacyAccount) {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        try saveKey(key.withUnsafeBytes { Data($0) }, account: legacyAccount)
        return key
    }

    private func loadOrCreateAgreementKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let data = try loadKey(account: agreementAccount), data.count == 32 {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        try saveKey(key.rawRepresentation, account: agreementAccount)
        return key
    }

    private func loadOrCreateSigningKey() throws -> Curve25519.Signing.PrivateKey {
        if let data = try loadKey(account: signingAccount), data.count == 32 {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        }
        let key = Curve25519.Signing.PrivateKey()
        try saveKey(key.rawRepresentation, account: signingAccount)
        return key
    }

    private func saveKey(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ResilixError.persistenceFailed("keychain save failed (\(status))")
        }
    }

    private func loadKey(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw ResilixError.persistenceFailed("keychain read failed (\(status))")
        }
        guard let data = item as? Data else { return nil }
        return data
    }
}

private extension String {
    /// Splits the string into groups of `size` characters.
    func chunked(every size: Int) -> [String] {
        guard size > 0 else { return [self] }
        var result: [String] = []
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(String(self[index..<next]))
            index = next
        }
        return result
    }
}
