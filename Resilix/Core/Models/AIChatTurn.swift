import Foundation

/// One turn of a local AI conversation (persisted on device only).
struct AIChatTurn: Codable, Sendable, Equatable, Identifiable {
    enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    var id: String
    var role: Role
    var text: String
    var timestamp: Date
    /// Which engine produced the answer (model id or "Knowledge base").
    var source: String?

    init(id: String = UUID().uuidString,
         role: Role,
         text: String,
         timestamp: Date = Date(),
         source: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.source = source
    }
}
