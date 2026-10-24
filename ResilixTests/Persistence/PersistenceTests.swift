import XCTest
@testable import Resilix

final class PersistenceTests: XCTestCase {
    func testSaveLoadMessages() async throws {
        let controller = PersistenceController()
        let messages = [MeshMessage(id: "1",
                                    packetID: nil,
                                    threadID: "C",
                                    sourceNodeID: "A",
                                    destinationNodeID: "C",
                                    text: "hi",
                                    createdAt: Date(),
                                    deliveryState: .queued,
                                    expirySeconds: nil,
                                    lastRoute: nil,
                                    priority: .normal)]
        try await controller.saveMessages(messages)
        let loaded = await controller.loadMessages()
        XCTAssertEqual(loaded.first?.text, "hi")
    }

    func testCorruptRecovery() async throws {
        let controller = PersistenceController()
        try await controller.save(["bad"] as [String], to: "test_corrupt.json")
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Resilix/test_corrupt.json")
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        do {
            _ = try await controller.load([String].self, from: "test_corrupt.json")
            XCTFail("Corrupt data must not be returned")
        } catch {
            XCTAssertTrue(error is ResilixError)
        }
    }

    func testContactPersistence() async throws {
        let controller = PersistenceController()
        let contacts = [ResilixContact(id: "A",
                                       displayName: "Alice",
                                       alias: "Node 1",
                                       lastSeen: Date(),
                                       isTrusted: true,
                                       isReachable: true,
                                       isRelayReachable: false)]
        try await controller.saveContacts(contacts)
        let loaded = await controller.loadContacts()
        XCTAssertEqual(loaded.first?.displayName, "Alice")
    }

    func testSettingsSurviveRestart() async throws {
        let controller = PersistenceController()
        var settings = AppSettings()
        settings.language = "Urdu"
        settings.appearance = .dark
        settings.profilePhotoFileName = "profile.jpg"
        try await controller.saveSettings(settings)

        let loaded = await controller.loadSettings()
        XCTAssertEqual(loaded.language, "Urdu")
        XCTAssertEqual(loaded.appearance, .dark)
        XCTAssertEqual(loaded.profilePhotoFileName, "profile.jpg")
    }

    func testBinaryFileRoundTrip() async throws {
        let controller = PersistenceController()
        let payload = Data("media-bytes".utf8)
        try await controller.write(payload, to: "Media/test.bin")
        let read = try await controller.read(from: "Media/test.bin")
        XCTAssertEqual(read, payload)
        XCTAssertTrue(await controller.fileExists(at: "Media/test.bin"))
        await controller.removeFile(at: "Media/test.bin")
        XCTAssertFalse(await controller.fileExists(at: "Media/test.bin"))
    }

    func testStorageLimitRemovesOldestFiles() async throws {
        let controller = PersistenceController()
        try await controller.write(Data(repeating: 1, count: 512), to: "Media/limit-a.bin")
        try await controller.write(Data(repeating: 2, count: 512), to: "Media/limit-b.bin")
        let removed = await controller.enforceStorageLimit(named: ResilixConstants.mediaDirectoryName,
                                                          limitBytes: 600)
        XCTAssertGreaterThan(removed, 0)
    }

    func testMapPackMetadataRoundTrip() async throws {
        let controller = PersistenceController()
        let pack = MapPackDescriptor(id: "pack",
                                     name: "Test pack",
                                     relativePath: "Maps/pack.mbtiles",
                                     format: .mbtiles,
                                     byteCount: 10,
                                     minZoom: 4,
                                     maxZoom: 16,
                                     minLatitude: 1,
                                     maxLatitude: 2,
                                     minLongitude: 3,
                                     maxLongitude: 4,
                                     importedAt: Date(),
                                     sha256: "abc",
                                     placeNames: ["Shelter"])
        try await controller.saveMapPacks([pack])
        let loaded = await controller.loadMapPacks()
        XCTAssertEqual(loaded.first?.name, "Test pack")
        XCTAssertEqual(loaded.first?.placeNames, ["Shelter"])
    }
}
