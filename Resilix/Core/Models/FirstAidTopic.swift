import Foundation

struct FirstAidTopic: Codable, Sendable, Equatable, Identifiable, Hashable {
    var id: String
    var category: String
    var title: String
    var steps: [String]
    var caution: String?
    var whenToSeekHelp: String
}
