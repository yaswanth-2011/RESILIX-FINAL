import Foundation

struct ResourcePacket: Codable, Sendable, Equatable {
    var resourceID: String
    var category: ResourceCategory
    var latitude: Double
    var longitude: Double
    var createdAt: Date
    var lastVerifiedAt: Date?
    var verification: ResourceVerificationState
    var sourceNodeID: String?
    var version: Int
}
