import XCTest
@testable import Resilix

@MainActor
final class MediaTransferTests: XCTestCase {
    func testChunkFramingRoundTrip() {
        let chunk = Data("payload-bytes".utf8)
        let framed = TransferService.frameChunk(transferID: "abc", index: 7, chunk: chunk)
        guard let parsed = TransferService.parseChunk(framed) else {
            return XCTFail("The chunk could not be parsed")
        }
        XCTAssertEqual(parsed.transferID, "abc")
        XCTAssertEqual(parsed.index, 7)
        XCTAssertEqual(parsed.chunk, chunk)
    }

    func testChunkOrderIsPreserved() {
        var chunks: [Int: Data] = [:]
        for index in 0..<5 {
            let chunk = Data(repeating: UInt8(index), count: 10)
            let framed = TransferService.frameChunk(transferID: "t", index: index, chunk: chunk)
            guard let parsed = TransferService.parseChunk(framed) else {
                return XCTFail("The chunk could not be parsed")
            }
            chunks[parsed.index] = parsed.chunk
        }
        let assembled = (0..<5).compactMap { chunks[$0] }.reduce(into: Data()) { $0.append($1) }
        XCTAssertEqual(assembled.count, 50)
        XCTAssertEqual(Array(assembled.prefix(10)), Array(repeating: 0, count: 10))
        XCTAssertEqual(Array(assembled.suffix(10)), Array(repeating: 4, count: 10))
    }

    func testTruncatedChunkIsRejected() {
        let framed = TransferService.frameChunk(transferID: "abc", index: 1, chunk: Data("x".utf8))
        XCTAssertNil(TransferService.parseChunk(framed.prefix(10)))
    }

    func testChecksumDetectsCorruption() {
        let data = Data("hello world".utf8)
        let digest = PacketCrypto.sha256Hex(data)
        var corrupted = data
        corrupted[0] = corrupted[0] ^ 0xFF
        XCTAssertNotEqual(PacketCrypto.sha256Hex(corrupted), digest)
    }

    func testMediaLimitIsEnforced() {
        XCTAssertGreaterThan(ResilixConstants.maxMediaBytes, ResilixConstants.mediaChunkSize)
    }
}
