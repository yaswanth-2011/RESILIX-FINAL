import Foundation

/// Wire framing used by every Resilix transport.
///
/// A *frame* is the smallest unit that is written to a radio. It carries a
/// slice of a packet together with the information needed to reassemble it
/// (`index` / `count` / transfer id). Transports with a small MTU (BLE)
/// split a packet into many frames, transports with a large MTU (Wi-Fi) send
/// a single frame. The receiving side always works with whole packets.
enum FrameCodec {
    static let magic: [UInt8] = [0x52, 0x58] // "RX"
    static let version: UInt8 = 1
    static let headerSize = 14

    enum FrameKind: UInt8, Sendable {
        case single = 0
        case fragment = 1
        case handshake = 2
    }

    struct ParsedFrame: Sendable, Equatable {
        var kind: FrameKind
        var index: Int
        var count: Int
        var transferID: String?
        var payload: Data
    }

    // MARK: - Packet (de)serialisation

    static func encode(_ packet: MeshPacket) throws -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(packet)
        guard data.count <= ResilixConstants.maxPacketSizeBytes else { throw ResilixError.packetTooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> MeshPacket {
        guard data.count <= ResilixConstants.maxPacketSizeBytes else { throw ResilixError.packetTooLarge }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(MeshPacket.self, from: data)
    }

    // MARK: - Framing

    /// Splits `payload` into frames that fit into `mtu` bytes.
    static func frames(for payload: Data, mtu: Int, transferID: String) -> [Data] {
        let usable = max(32, mtu - headerSize)
        if payload.count <= usable {
            return [makeFrame(kind: .single, index: 0, count: 1, payload: payload)]
        }
        let count = Int(ceil(Double(payload.count) / Double(usable)))
        var result: [Data] = []
        result.reserveCapacity(count)
        let idBytes = Data(transferID.utf8)
        for index in 0..<count {
            let start = index * usable
            let end = min(start + usable, payload.count)
            let chunk = payload.subdata(in: start..<end)
            var framed = Data()
            framed.append(idBytes)
            framed.append(chunk)
            result.append(makeFrame(kind: .fragment, index: index, count: count, payload: framed))
        }
        return result
    }

    static func makeFrame(kind: FrameKind, index: Int, count: Int, payload: Data) -> Data {
        var data = Data()
        data.append(contentsOf: magic)
        data.append(version)
        data.append(kind.rawValue)
        data.append(contentsOf: beUInt32(UInt32(max(0, index))))
        data.append(contentsOf: beUInt32(UInt32(max(1, count))))
        data.append(contentsOf: beUInt16(UInt16(min(Int(UInt16.max), payload.count))))
        data.append(payload)
        return data
    }

    /// Builds a frame that carries a connection handshake.
    static func handshakeFrame(_ hello: PeerHello) -> Data? {
        guard let json = try? JSONEncoder().encode(hello) else { return nil }
        return makeFrame(kind: .handshake, index: 0, count: 1, payload: json)
    }

    /// Parses a frame. Returns `nil` for malformed data (never throws, so a
    /// hostile peer cannot crash the node).
    static func parse(_ data: Data) -> ParsedFrame? {
        guard data.count >= headerSize else { return nil }
        let bytes = [UInt8](data)
        guard bytes[0] == magic[0], bytes[1] == magic[1] else { return nil }
        guard bytes[2] == version else { return nil }
        guard let kind = FrameKind(rawValue: bytes[3]) else { return nil }
        let index = Int(readUInt32(bytes, 4))
        let count = Int(readUInt32(bytes, 8))
        let length = Int(readUInt16(bytes, 12))
        guard count > 0, index >= 0, index < count else { return nil }
        let start = headerSize
        let end = start + length
        guard end <= bytes.count else { return nil }
        var payload = data.subdata(in: start..<end)
        var transferID: String?
        if kind == .fragment {
            // Fragment payloads start with the 36 character transfer id.
            guard payload.count >= 36 else { return nil }
            transferID = String(data: payload.prefix(36), encoding: .utf8)
            payload = payload.dropFirst(36)
        }
        return ParsedFrame(kind: kind, index: index, count: count, transferID: transferID, payload: payload)
    }

    /// Reassembles the fragments of one transfer.
    static func reassemble(_ frames: [ParsedFrame]) -> Data? {
        guard let first = frames.first else { return nil }
        guard first.count == frames.count else { return nil }
        var ordered: [Data] = []
        ordered.reserveCapacity(first.count)
        for index in 0..<first.count {
            guard let frame = frames.first(where: { $0.index == index }) else { return nil }
            ordered.append(frame.payload)
        }
        var result = Data()
        for chunk in ordered { result.append(chunk) }
        return result
    }

    // MARK: - Byte helpers

    private static func beUInt32(_ value: UInt32) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func beUInt16(_ value: UInt16) -> [UInt8] {
        [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 3 < bytes.count else { return 0 }
        return (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
    }

    private static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset + 1 < bytes.count else { return 0 }
        return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }
}

/// Reassembles frames from a byte stream (used by the TCP based transport).
struct StreamFrameBuffer {
    private var buffer = Data()

    mutating func append(_ data: Data) -> [FrameCodec.ParsedFrame] {
        buffer.append(data)
        var frames: [FrameCodec.ParsedFrame] = []
        while buffer.count >= FrameCodec.headerSize {
            let length = Int(buffer[12]) << 8 | Int(buffer[13])
            let total = FrameCodec.headerSize + length
            guard buffer.count >= total else { break }
            let frameData = Data(buffer.prefix(total))
            buffer.removeFirst(total)
            if let frame = FrameCodec.parse(frameData) {
                frames.append(frame)
            }
        }
        return frames
    }
}
