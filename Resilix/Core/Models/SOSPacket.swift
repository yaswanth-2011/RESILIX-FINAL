import Foundation

struct SOSPacket: Codable, Sendable, Equatable {
    var id: String
    var category: SOSCategory
    var severity: SOSSeverity
    var note: String?
    var latitude: Double?
    var longitude: Double?
    var createdAt: Date
    var sourceNodeID: String
    var priority: PacketPriority { severity == .critical ? .sos : .high }
}
