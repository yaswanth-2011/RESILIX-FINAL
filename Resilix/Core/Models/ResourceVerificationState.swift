import Foundation
enum ResourceVerificationState: String, Codable, Sendable, CaseIterable {
    case unverified, communityReported = "community_reported", verified
    var label: String {
        switch self {
        case .unverified: return "Unverified"
        case .communityReported: return "Community reported"
        case .verified: return "Verified"
        }
    }
}
