import Foundation

enum FrameCodec {
    static func encode(_ packet: MeshPacket) throws -> Data {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(packet)
        guard data.count <= ResilixConstants.maxPacketSizeBytes else { throw ResilixError.packetTooLarge }
        return data
    }
    static func decode(_ data: Data) throws -> MeshPacket {
        guard data.count <= ResilixConstants.maxPacketSizeBytes else { throw ResilixError.packetTooLarge }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try dec.decode(MeshPacket.self, from: data)
    }
    // BLE fragmentation
    struct Fragment: Codable, Sendable {
        var packetID: String
        var index: Int
        var total: Int
        var payload: Data
    }
    static func fragment(data: Data, packetID: String, mtu: Int = 180) -> [Data] {
        let chunk = mtu - 64
        let total = (data.count + chunk - 1)/chunk
        var out: [Data] = []
        for i in 0..<total {
            let s = i*chunk
            let e = min(s+chunk, data.count)
            let frag = Fragment(packetID: packetID, index: i, total: total, payload: data[s..<e])
            if let d = try? JSONEncoder().encode(frag) { out.append(d) }
        }
        return out
    }
}
