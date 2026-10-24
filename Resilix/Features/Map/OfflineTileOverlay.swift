import Foundation
import MapKit

/// Renders a locally stored map pack instead of the online Apple tiles.
///
/// The overlay completely replaces the map content (`canReplaceMapContent`
/// is `true`), therefore the map keeps working in airplane mode once a pack
/// was imported.
final class OfflineTileOverlay: MKTileOverlay {
    private let reader: MBTilesReader?
    private let directory: URL?
    private let cache = NSCache<NSString, NSData>()

    init(reader: MBTilesReader) {
        self.reader = reader
        self.directory = nil
        super.init(urlTemplate: "http://resilix.local/{z}/{x}/{y}.png")
        canReplaceMapContent = true
        minimumZ = max(0, reader.minimumZoom)
        maximumZ = max(minimumZ, reader.maximumZoom)
        tileSize = CGSize(width: 256, height: 256)
    }

    init(directory: URL) {
        self.reader = nil
        self.directory = directory
        super.init(urlTemplate: "http://resilix.local/{z}/{x}/{y}.png")
        canReplaceMapContent = true
        minimumZ = 0
        maximumZ = 16
        tileSize = CGSize(width: 256, height: 256)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let key = "\(path.z)-\(path.x)-\(path.y)" as NSString
        if let cached = cache.object(forKey: key) {
            result(cached as Data, nil)
            return
        }

        if let reader {
            guard let data = reader.tileData(zoom: path.z, x: path.x, y: path.y) else {
                result(nil, nil)
                return
            }
            cache.setObject(data as NSData, forKey: key)
            result(data, nil)
            return
        }

        if let directory {
            let fileURL = directory
                .appendingPathComponent(String(path.z))
                .appendingPathComponent(String(path.x))
                .appendingPathComponent("\(path.y).png")
            guard let data = try? Data(contentsOf: fileURL) else {
                result(nil, nil)
                return
            }
            cache.setObject(data as NSData, forKey: key)
            result(data, nil)
            return
        }

        result(nil, nil)
    }
}
