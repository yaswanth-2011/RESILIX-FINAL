import Foundation
import SQLite3
#if canImport(UIKit)
import UIKit
#endif

/// Creates a minimal, self-contained offline map pack (MBTiles) that ships
/// with the app so the map works offline from the very first launch — no
/// import or download required.
///
/// The pack contains a single zoom-0 tile covering the whole world. It is
/// intentionally small (a solid background tile) so that the app is usable
/// offline immediately; users can import richer .mbtiles packs later.
enum DefaultMapPackCreator {
    /// Returns the bytes of a ready-to-import MBTiles file, or `nil` if it
    /// could not be created.
    static func createStarterPackBytes() -> Data? {
        guard let tilePNG = makeTilePNG() else { return nil }

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("resilix_starter_\(UUID().uuidString).mbtiles")
        try? FileManager.default.removeItem(at: tmp)

        var db: OpaquePointer?
        guard sqlite3_open(tmp.path, &db) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        func exec(_ sql: String) -> Bool {
            var err: UnsafeMutablePointer<Int8>?
            return sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK
        }

        guard
            exec("CREATE TABLE IF NOT EXISTS metadata (name TEXT, value TEXT)"),
            exec("CREATE TABLE IF NOT EXISTS tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB, PRIMARY KEY (zoom_level, tile_column, tile_row))"),
            exec("CREATE TABLE IF NOT EXISTS grids (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, grid BLOB)"),
            exec("CREATE TABLE IF NOT EXISTS grid_data (grid_id INTEGER, zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER)"),
            exec("CREATE UNIQUE INDEX IF NOT EXISTS name_idx ON metadata (name)"),
            exec("CREATE UNIQUE INDEX IF NOT EXISTS tile_idx ON tiles (zoom_level, tile_column, tile_row)")
        else { return nil }

        func insertMetadata(name: String, value: String) {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                                     "INSERT INTO metadata (name, value) VALUES (?, ?)",
                                     -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, value, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }

        func insertTile(zoom: Int, col: Int, row: Int, data: Data) {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                                     "INSERT INTO tiles (zoom_level, tile_column, tile_row, tile_data) VALUES (?, ?, ?, ?)",
                                     -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(zoom))
            sqlite3_bind_int(stmt, 2, Int32(col))
            sqlite3_bind_int(stmt, 3, Int32(row))
            data.withUnsafeBytes {
                sqlite3_bind_blob(stmt, 4, $0.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
            }
            sqlite3_step(stmt)
        }

        // World bounds (approx) and a starter center (Greenwich/UK area so
        // the pack is usable worldwide at zoom 0).
        insertMetadata(name: "name", value: "Resilix Starter Map")
        insertMetadata(name: "description", value:
            "Preinstalled offline starter map. Import your own .mbtiles pack for detailed local maps.")
        insertMetadata(name: "type", value: "baselayer")
        insertMetadata(name: "version", value: "1")
        insertMetadata(name: "minzoom", value: "0")
        insertMetadata(name: "maxzoom", value: "0")
        insertMetadata(name: "bounds", value: "-180,-85,180,85")
        insertMetadata(name: "center", value: "0,45,0")
        insertMetadata(name: "format", value: "png")

        // Single zoom-0 tile (TMS row 0).
        insertTile(zoom: 0, col: 0, row: 0, data: tilePNG)

        guard sqlite3_exec(db, nil, nil, nil, nil) == SQLITE_OK || true else { return nil }

        let result = try? Data(contentsOf: tmp)
        try? FileManager.default.removeItem(at: tmp)
        return result
    }

    /// A tiny valid PNG (256×256, solid light background) used as the
    /// starter zoom-0 tile.
    private static func makeTilePNG() -> Data? {
#if canImport(UIKit)
        let size = CGSize(width: 256, height: 256)
        UIGraphicsBeginImageContextWithOptions(size, false, 1)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        ctx.setFillColor(red: 0.90, green: 0.92, blue: 0.94, alpha: 1)
        ctx.fill(CGRect(origin: .zero, size: size))
        // A subtle grid so the tile is visibly a map tile, not blank.
        ctx.setStrokeColor(red: 0.75, green: 0.80, blue: 0.85, alpha: 1)
        ctx.setLineWidth(1)
        for i in stride(from: 0, through: 256, by: 32) {
            ctx.move(to: CGPoint(x: i, y: 0))
            ctx.addLine(to: CGPoint(x: i, y: 256))
            ctx.move(to: CGPoint(x: 0, y: i))
            ctx.addLine(to: CGPoint(x: 256, y: i))
        }
        ctx.strokePath()
        return UIGraphicsGetImageFromCurrentImageContext()?.pngData()
#else
        return nil
#endif
    }
}
