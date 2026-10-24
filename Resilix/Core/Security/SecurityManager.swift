import Foundation
import CryptoKit
import Security

actor SecurityManager {
    private let keychainService = "com.resilix.identity"
    private var symmetricKey: SymmetricKey?

    init() {}

    func setupIdentityIfNeeded(nodeID: String) async throws {
        if try loadKey() == nil {
            let key = SymmetricKey(size: .bits256)
            try saveKey(key)
            symmetricKey = key
        } else {
            symmetricKey = try loadKey()
        }
    }

    func encrypt(_ plaintext: Data) throws -> (ciphertext: Data, nonce: Data) {
        let key = try getKey()
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        guard let combined = sealed.combined else { throw ResilixError.securityDecryptionFailed }
        return (combined, Data(nonce))
    }

    func decrypt(_ combined: Data) throws -> Data {
        let key = try getKey()
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }

    func signEnvelope(_ data: Data) -> Data {
        // HMAC placeholder
        let key = try? getKey()
        guard let k = key else { return Data(SHA256.hash(data: data)) }
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: k)
        return Data(mac)
    }

    private func getKey() throws -> SymmetricKey {
        if let k = symmetricKey { return k }
        if let k = try loadKey() { symmetricKey = k; return k }
        throw ResilixError.securityDecryptionFailed
    }

    private func saveKey(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: keychainService,
                                     kSecAttrAccount as String: "symKey",
                                     kSecValueData as String: data]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess { throw ResilixError.persistenceFailed("keychain save \(status)") }
    }
    private func loadKey() throws -> SymmetricKey? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: keychainService,
                                     kSecAttrAccount as String: "symKey",
                                     kSecReturnData as String: true,
                                     kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return SymmetricKey(data: data)
    }
}
