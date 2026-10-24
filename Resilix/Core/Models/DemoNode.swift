import Foundation

struct DemoNode: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var label: String // Source, Relay, Destination
    var alias: String
}
