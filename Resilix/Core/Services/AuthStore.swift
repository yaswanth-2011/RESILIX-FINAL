import Foundation
import CryptoKit

/// Local-only authentication store.
///
/// Accounts are stored on this device only — there is no server. The password
/// is hashed with SHA-256 before being persisted, so the raw value never sits
/// in UserDefaults. This is appropriate for an offline-first app where the
/// "account" is really just a local identity.
enum AuthStore {
    private static let usersKey = "resilix.users"
    private static let sessionKey = "resilix.session"

    struct User: Codable {
        let username: String
        let passwordHash: String
        let createdAt: Date
    }

    /// Returns the username of the current session, or nil if not signed in.
    static func currentUsername() -> String? {
        UserDefaults.standard.string(forKey: sessionKey)
    }

    /// Registers a new account. Returns false if the username is taken.
    @discardableResult
    static func register(username: String, password: String) -> Bool {
        let users = loadUsers()
        guard !users.contains(where: { $0.username.lowercased() == username.lowercased() }) else {
            return false
        }
        let user = User(username: username,
                       passwordHash: hash(password),
                       createdAt: Date())
        users.append(user)
        saveUsers(users)
        return true
    }

    /// Validates a login attempt against the stored accounts.
    static func validate(username: String, password: String) -> Bool {
        let users = loadUsers()
        guard let user = users.first(where: { $0.username.lowercased() == username.lowercased() }) else {
            return false
        }
        return user.passwordHash == hash(password)
    }

    /// Saves the current session so the user stays signed in across launches.
    static func saveSession(username: String) {
        UserDefaults.standard.set(username, forKey: sessionKey)
    }

    /// Clears the current session (sign out).
    static func clearSession() {
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    // MARK: - Private

    private static func loadUsers() -> [User] {
        guard let data = UserDefaults.standard.data(forKey: usersKey),
              let users = try? JSONDecoder().decode([User].self, from: data) else {
            return []
        }
        return users
    }

    private static func saveUsers(_ users: [User]) {
        guard let data = try? JSONEncoder().encode(users) else { return }
        UserDefaults.standard.set(data, forKey: usersKey)
    }

    private static func hash(_ password: String) -> String {
        let data = Data(password.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
