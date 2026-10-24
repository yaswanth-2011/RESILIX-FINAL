import Foundation

/// Approximate position of a node, shared with the mesh on request.
///
/// The coordinates are rounded to roughly 100 metres before they are sent,
/// so that the position cannot be used to track a person precisely.
struct LocationAdvertisement: Codable, Sendable, Equatable {
    var nodeID: String
    var latitude: Double
    var longitude: Double
    var accuracy: Double
    var timestamp: Date

    /// Rounds a coordinate to the nearest ~100 m grid cell.
    static func rounded(latitude: Double, longitude: Double) -> (Double, Double) {
        let factor = 1000.0 / 110_574.0 // ~0.009 degrees == ~1000 m
        return ((latitude * factor).rounded() / factor,
                (longitude * factor).rounded() / factor)
    }
}
