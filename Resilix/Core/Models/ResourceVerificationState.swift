import Foundation
enum ResourceVerificationState: String, Codable, Sendable, CaseIterable {
    case unverified, communityReported = "community_reported", verified
    var label: String {
        switch self {
        case .unverified: return L("resource.verification.unverified")
        case .communityReported: return L("resource.verification.communityReported")
        case .verified: return L("resource.verification.verified")
        }
    }
}
