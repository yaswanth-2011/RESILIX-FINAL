import XCTest
@testable import Resilix

final class FrameCodecTests: XCTestCase {
    func testFragmentationAndReassembly() {
        let payload = Data((0..<1000).map { UInt8($0 % 251) })
        let frames = FrameCodec.frames(for: payload, mtu: 180, transferID: "transfer-1")
        XCTAssertGreaterThan(frames.count, 1, "A payload larger than the MTU must be fragmented")

        var buffer = StreamFrameBuffer()
        var parsed: [FrameCodec.ParsedFrame] = []
        for frame in frames {
            parsed.append(contentsOf: buffer.append(frame))
        }
        let reassembled = FrameCodec.reassemble(parsed)
        XCTAssertEqual(reassembled, payload)
    }

    func testSingleFrameForSmallPayload() {
        let payload = Data("small".utf8)
        let frames = FrameCodec.frames(for: payload, mtu: 180, transferID: "transfer-2")
        XCTAssertEqual(frames.count, 1)
        var buffer = StreamFrameBuffer()
        let parsed = buffer.append(frames[0])
        XCTAssertEqual(FrameCodec.reassemble(parsed), payload)
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(FrameCodec.parse(Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF])))
    }

    func testParseRejectsEmptyData() {
        XCTAssertNil(FrameCodec.parse(Data()))
    }

    func testHandshakeFrameRoundTrip() throws {
        let hello = PeerHello(nodeID: "node-1",
                              alias: "Node 1",
                              agreementPublicKey: Data(repeating: 1, count: 32),
                              signingPublicKey: Data(repeating: 2, count: 64),
                              supportsRelay: true,
                              protocolVersion: ResilixConstants.protocolVersion)
        guard let frame = FrameCodec.handshakeFrame(hello) else {
            return XCTFail("The handshake frame could not be created")
        }
        let parsed = FrameCodec.parse(frame)
        XCTAssertEqual(parsed?.kind, .handshake)
        guard let parsed, let payload = parsed.payload else {
            return XCTFail("The handshake frame has no payload")
        }
        let decoded = try JSONDecoder().decode(PeerHello.self, from: payload)
        XCTAssertEqual(decoded.nodeID, hello.nodeID)
        XCTAssertEqual(decoded.signingPublicKey, hello.signingPublicKey)
    }

    func testOversizedPacketIsRejectedByValidator() {
        let packet = makePacket(payload: Data(repeating: 7, count: ResilixConstants.maxPacketSizeBytes + 10))
        XCTAssertThrowsError(try PacketValidator.validate(packet))
    }
}
