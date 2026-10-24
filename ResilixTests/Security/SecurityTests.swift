import XCTest
@testable import Resilix

final class SecurityTests: XCTestCase {
    func testEncryptDecrypt() async throws {
        let mgr = SecurityManager()
        try await mgr.setupIdentityIfNeeded(nodeID:"test")
        let plain = Data("secret message".utf8)
        let (cipher, _) = try await mgr.encrypt(plain)
        let decrypted = try await mgr.decrypt(cipher)
        XCTAssertEqual(plain, decrypted)
    }
    func testAlteredCiphertextFails() async throws {
        let mgr = SecurityManager()
        try await mgr.setupIdentityIfNeeded(nodeID:"test")
        let (cipher, _) = try await mgr.encrypt(Data("hello".utf8))
        var altered = cipher; if !altered.isEmpty { altered[0] ^= 0xFF }
        XCTAssertThrowsError(try await mgr.decrypt(altered))
    }
    func testExpiredPacketRejected() throws {
        var p = PacketBuilder.makePacket(type:.chat, source:"A", destination:"B", payload:Data(), priority:.normal)
        p.expiresAt = Date().addingTimeInterval(-5)
        XCTAssertThrowsError(try PacketValidator.validate(p))
    }
}
