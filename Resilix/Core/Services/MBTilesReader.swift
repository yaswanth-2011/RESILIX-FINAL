import Foundation
import SQLite3

/// Minimal read-only reader for MBTiles containers.
///
/// MBTiles is a SQLite database with a `tiles` table
/// (`zoom_level`, `tile_column`, `tile_row`, `tile_data`) and a `metadata`
/// table. Rows are stored in TMS orientation, therefore the row index is
/// flipped when a tile is requested.
final class MBTilesReader {
    private var database: OpaquePointer?
    private var tileStatement: OpaquePointer?
    private var placesStatement: OpaquePointer?
    private(set) var metadata: [String: String] = [:]

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init?(url: URL) {
        let flags = SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK else {
            database = nil
            return nil
        }
        readMetadata()
        prepareStatements()
    }

    deinit {
        if let tileStatement { sqlite3_finalize(tileStatement) }
        if let placesStatement { sqlite3_finalize(placesStatement) }
        if let database { sqlite3_close(database) }
    }

    private func readMetadata() {
        guard let database else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database,
                                "SELECT name, value FROM metadata",
                                -1,
                                &statement,
                                nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let namePointer = sqlite3_column_text(statement, 0),
                  let valuePointer = sqlite3_column_text(statement, 1) else { continue }
            let name = String(cString: namePointer)
            let value = String(cString: valuePointer)
            metadata[name] = value
        }
    }

    private func prepareStatements() {
        guard let database else { return }
        var tile: OpaquePointer?
        if sqlite3_prepare_v2(database,
                              "SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?",
                              -1,
                              &tile,
                              nil) == SQLITE_OK {
            tileStatement = tile
        }
        var places: OpaquePointer?
        if sqlite3_prepare_v2(database,
                              "SELECT name FROM places",
                              -1,
                              &places,
                              nil) == SQLITE_OK {
            placesStatement = places
        }
    }

    /// Returns the PNG/JPEG bytes of a tile (or `nil` when it is missing).
    func tileData(zoom: Int, x: Int, y: Int) -> Data? {
        guard let tileStatement else { return nil }
        let flippedRow = (1 << zoom) - 1 - y
        sqlite3_reset(tileStatement)
        sqlite3_clear_bindings(tileStatement)
        sqlite3_bind_int(tileStatement, 1, Int32(zoom))
        sqlite3_bind_int(tileStatement, 2, Int32(x))
        sqlite3_bind_int(tileStatement, 3, Int32(flippedRow))
        guard sqlite3_step(tileStatement) == SQLITE_ROW else { return nil }
        let count = Int(sqlite3_column_bytes(tileStatement, 0))
        guard count > 0, let bytes = sqlite3_column_blob(tileStatement, 0) else { return nil }
        return Data(bytes: bytes, count: count)
    }

    /// Reads the place names stored in the pack (offline search index).
    func placeNames(limit: Int = 500) -> [String] {
        guard let placesStatement else { return [] }
        sqlite3_reset(placesStatement)
        var names: [String] = []
        while names.count < limit, sqlite3_step(placesStatement) == SQLITE_ROW {
            guard let pointer = sqlite3_column_text(placesStatement, 0) else { continue }
            names.append(String(cString: pointer))
        }
        sqlite3_reset(placesStatement)
        return names
    }

    var minimumZoom: Int { Int(metadata["minzoom"] ?? "") ?? 0 }
    var maximumZoom: Int { Int(metadata["maxzoom"] ?? "") ?? 0 }
    var minimumLatitude: Double { Double(metadata["minlat"] ?? "") ?? -90 }
    var maximumLatitude: Double { Double(metadata["maxlat"] ?? "") ?? 90 }
    var minimumLongitude: Double { Double(metadata["minlon"] ?? "") ?? -180 }
    var maximumLongitude: Double { Double(metadata["maxlon"] ?? "") ?? 180 }
}
