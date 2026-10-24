import Foundation
import CoreLocation

struct MapResource: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var category: ResourceCategory
    var title: String
    var notes: String?
    var latitude: Double
    var longitude: Double
    var createdAt: Date
    var lastVerifiedAt: Date?
    var verification: ResourceVerificationState
    var sourceNodeID: String?
    var isDemo: Bool

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var isStale: Bool { Date().timeIntervalSince(lastVerifiedAt ?? createdAt) > 3600*24 }
}
