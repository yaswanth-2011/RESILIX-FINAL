import XCTest
@testable import Resilix

final class PersistenceTests: XCTestCase {
    func testSaveLoadMessages() async throws {
        let ctrl = PersistenceController()
        let msgs = [MeshMessage(id:"1", packetID:nil, threadID:"C", sourceNodeID:"A", destinationNodeID:"C", text:"hi", createdAt:Date(), deliveryState:.queued, expirySeconds:nil, lastRoute:nil, priority:.normal)]
        try await ctrl.saveMessages(msgs)
        let loaded = await ctrl.loadMessages()
        XCTAssertEqual(loaded.first?.text, "hi")
    }
    func testCorruptRecovery() async throws {
        let ctrl = PersistenceController()
        try await ctrl.save(["bad"] as [String], to: "test_corrupt.json")
        // corrupt by writing invalid json
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Resilix/test_corrupt.json")
        try "not json".write(to: url, atomically:true, encoding:.utf8)
        do { _ = try await ctrl.load([String].self, from: "test_corrupt.json"); XCTFail() } catch { XCTAssertTrue(true) }
    }
    func testContactPersistence() async throws {
        let ctrl = PersistenceController()
        let c = [ResilixContact(id:"A", displayName:"Alice", alias:"Node 1", lastSeen:Date(), isTrusted:true, isReachable:true, isRelayReachable:false)]
        try await ctrl.saveContacts(c)
        XCTAssertEqual(await ctrl.loadContacts().first?.displayName, "Alice")
    }
}
