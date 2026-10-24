import XCTest
@testable import Resilix

@MainActor
final class MapPackTests: XCTestCase {
    func testDescriptorComputesTheCoverageCentre() {
        let pack = MapPackDescriptor(id: "p",
                                     name: "Region",
                                     relativePath: "Maps/p.mbtiles",
                                     format: .mbtiles,
                                     byteCount: 100,
                                     minZoom: 4,
                                     maxZoom: 16,
                                     minLatitude: 10,
                                     maxLatitude: 20,
                                     minLongitude: 30,
                                     maxLongitude: 40,
                                     importedAt: Date(),
                                     sha256: nil,
                                     placeNames: [])
        XCTAssertEqual(pack.centerLatitude, 15, accuracy: 0.0001)
        XCTAssertEqual(pack.centerLongitude, 35, accuracy: 0.0001)
        XCTAssertFalse(pack.coordinateText.isEmpty)
    }

    func testMissingFileCannotBeImported() async {
        let service = MapPackService()
        let missing = URL(fileURLWithPath: "/tmp/resilix-missing-\(UUID().uuidString).mbtiles")
        do {
            _ = try await service.importPack(from: missing)
            XCTFail("A missing file must not be imported")
        } catch {
            XCTAssertTrue(error is ResilixError)
        }
    }

    func testInvalidContainerIsRejected() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("resilix-invalid-\(UUID().uuidString).mbtiles")
        try Data("this is not a sqlite database".utf8).write(to: url)
        let service = MapPackService()
        do {
            _ = try await service.importPack(from: url)
            XCTFail("A broken container must be rejected")
        } catch {
            XCTAssertTrue(error is ResilixError)
        }
        try? FileManager.default.removeItem(at: url)
    }

    func testPackStateIsConsistent() async {
        let service = MapPackService()
        await service.load()
        for pack in service.packs {
            XCTAssertFalse(pack.name.isEmpty)
            XCTAssertGreaterThan(pack.byteCount, 0)
            XCTAssertFalse(pack.relativePath.isEmpty)
        }
    }

    func testSearchOnlyReturnsMatches() async {
        let service = MapPackService()
        await service.load()
        let results = service.search("shelter")
        XCTAssertTrue(results.allSatisfy { $0.lowercased().contains("shelter") })
    }
}
