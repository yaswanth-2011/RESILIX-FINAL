import XCTest
@testable import Resilix

final class SecurityTests: XCTestCase {
    func testEncryptDecrypt() async throws {
        let manager = SecurityManager()
        try await manager.setupIdentityIfNeeded(nodeID: "test")
        let plain = Data("secret message".utf8)
        let (cipher, _) = try await manager.encrypt(plain)
        let decrypted = try await manager.decrypt(cipher)
        XCTAssertEqual(plain, decrypted)
    }

    func testAlteredCiphertextFails() async throws {
        let manager = SecurityManager()
        try await manager.setupIdentityIfNeeded(nodeID: "test")
        let (cipher, _) = try await manager.encrypt(Data("hello".utf8))
        var altered = cipher
        if !altered.isEmpty { altered[0] ^= 0xFF }
        do {
            _ = try await manager.decrypt(altered)
            XCTFail("Altered ciphertext must not be decrypted")
        } catch {
            XCTAssertTrue(error is ResilixError)
        }
    }

    func testSealOpenRoundTrip() async throws {
        let manager = SecurityManager()
        try await manager.setupIdentityIfNeeded(nodeID: "test")
        let publicKey = try await manager.agreementPublicKey()
        let plain = Data("end to end payload".utf8)
        let box = try await manager.seal(plain, for: "peer", peerPublicKey: publicKey)
        let opened = try await manager.open(box, from: "peer", peerPublicKey: publicKey)
        XCTAssertEqual(opened, plain)
    }

    func testSignatureVerifiesAndDetectsTampering() async throws {
        let manager = SecurityManager()
        try await manager.setupIdentityIfNeeded(nodeID: "test")
        let message = Data("sign me".utf8)
        let signature = try await manager.sign(message)
        let publicKey = try await manager.signingPublicKey()
        XCTAssertTrue(await manager.verify(signature, for: message, publicKey: publicKey))

        var tampered = message
        tampered[0] = tampered[0] ^ 0xFF
        XCTAssertFalse(await manager.verify(signature, for: tampered, publicKey: publicKey))
    }

    func testCanonicalBytesIgnoreTTLAndHopCount() {
        var packet = makePacket()
        let original = PacketCrypto.canonicalBytes(packet)
        packet.ttl = packet.ttl > 0 ? packet.ttl - 1 : 1
        packet.hopCount += 1
        XCTAssertEqual(PacketCrypto.canonicalBytes(packet), original,
                       "Relays must be able to forward a signed packet")
    }

    func testCanonicalBytesChangeWithPayload() {
        let packet = makePacket(payload: Data("a".utf8))
        var other = packet
        other.payloadEnvelope = Data("b".utf8)
        XCTAssertNotEqual(PacketCrypto.canonicalBytes(packet), PacketCrypto.canonicalBytes(other))
    }

    func testPeerKeyChangeIsRejected() async throws {
        let store = PeerKeyStore()
        _ = try await store.register(peerID: "peer",
                                     agreementPublicKey: Data(repeating: 1, count: 32),
                                     signingPublicKey: Data(repeating: 2, count: 64),
                                     alias: "Peer")
        do {
            _ = try await store.register(peerID: "peer",
                                         agreementPublicKey: Data(repeating: 3, count: 32),
                                         signingPublicKey: Data(repeating: 4, count: 64),
                                         alias: "Peer")
            XCTFail("A changed key must be rejected")
        } catch {
            XCTAssertTrue(error is ResilixError)
        }
    }

    func testExpiredPacketRejected() throws {
        var packet = makePacket()
        packet.expiresAt = Date().addingTimeInterval(-5)
        XCTAssertThrowsError(try PacketValidator.validate(packet))
    }
}
