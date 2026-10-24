import Foundation

/// Description of an offline map pack that is stored on the device.
struct MapPackDescriptor: Codable, Sendable, Equatable, Identifiable {
    enum Format: String, Codable, Sendable {
        /// Standard MBTiles container (a SQLite database with a `tiles` table).
        case mbtiles
        /// Directory with `<z>/<x>/<y>.png` tiles.
        case directory
    }

    var id: String
    var name: String
    /// Path of the pack relative to the application support directory.
    var relativePath: String
    var format: Format
    var byteCount: Int
    var minZoom: Int
    var maxZoom: Int
    var minLatitude: Double
    var maxLatitude: Double
    var minLongitude: Double
    var maxLongitude: Double
    var importedAt: Date
    var sha256: String?
    /// Names of the places contained in the pack (offline search index).
    var placeNames: [String]

    var centerLatitude: Double { (minLatitude + maxLatitude) / 2 }
    var centerLongitude: Double { (minLongitude + maxLongitude) / 2 }

    var coordinateText: String {
        String(format: "%.3f, %.3f", centerLatitude, centerLongitude)
    }
}
