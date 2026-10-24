import Foundation

// OfflineFirstAidStore: curated, versioned, fully offline knowledge base.
// Content is shipped with the app bundle; no network content is downloaded.

enum OfflineFirstAidStore {
    static let version = "1.0.0"

    static let allTopics: [FirstAidTopic] = [
        FirstAidTopic(
            id: "bleeding", category: "Bleeding", title: "Severe bleeding",
            steps: [
                "Wash or cover your hands if possible.",
                "Apply firm, direct pressure with a clean cloth or bandage.",
                "Maintain continuous pressure for at least 10 minutes without lifting the cloth.",
                "If blood soaks through, add more cloth on top — do not remove the first layer.",
                "Elevate the limb above heart level if possible and no fracture is suspected."
            ],
            caution: "Do not remove embedded objects. Stabilize them in place.",
            whenToSeekHelp: "Seek professional help immediately if bleeding is heavy, spurting, or does not slow after 10 minutes of pressure."),

        FirstAidTopic(
            id: "cpr", category: "Cardiac", title: "CPR basics (adults)",
            steps: [
                "Check responsiveness: tap shoulders and shout.",
                "Call for help or send someone to fetch an AED if available.",
                "Begin chest compressions in center of the chest, 100–120 per minute, 5–6 cm deep.",
                "Give 2 rescue breaths after 30 compressions if you are trained.",
                "Continue until professional help arrives or the person responds."
            ],
            caution: "Compression-only CPR is acceptable if you are untrained in rescue breaths.",
            whenToSeekHelp: "Always seek professional help for any cardiac event."),

        FirstAidTopic(
            id: "burn", category: "Burns", title: "Burn care",
            steps: [
                "Cool the burn with clean, cool running water for at least 10 minutes.",
                "Remove rings or tight clothing near the burn before swelling starts.",
                "Cover loosely with a sterile, non-stick dressing or clean cloth.",
                "Do not apply ice, toothpaste, butter, or creams.",
                "Monitor the person for signs of shock."
            ],
            caution: nil,
            whenToSeekHelp: "Seek care for burns that are large, deep, blistered, on the face/hands/joints, or caused by electricity or chemicals."),

        FirstAidTopic(
            id: "fracture", category: "Injury", title: "Suspected fracture",
            steps: [
                "Keep the limb still; do not try to straighten it.",
                "Apply a splint in the position found, padding around it.",
                "Apply a cold pack wrapped in cloth to reduce swelling.",
                "Elevate the limb if possible without moving the injury site."
            ],
            caution: nil,
            whenToSeekHelp: "Seek professional help for any suspected fracture, especially with deformity, numbness, or open wounds."),

        FirstAidTopic(
            id: "choking", category: "Airway", title: "Choking (conscious adult)",
            steps: [
                "Ask whether the person is choking and can speak.",
                "Give 5 firm back blows between the shoulder blades.",
                "Give 5 abdominal thrusts (Heimlich maneuver).",
                "Alternate back blows and abdominal thrusts until the object clears."
            ],
            caution: nil,
            whenToSeekHelp: "If the obstruction does not clear and the person becomes unresponsive, begin CPR and seek emergency help."),

        FirstAidTopic(
            id: "hypothermia", category: "Exposure", title: "Hypothermia response",
            steps: [
                "Move the person to a warm, dry, sheltered place.",
                "Remove wet clothing and replace with dry layers, covering the head.",
                "Warm the center of the body first — chest, neck, head, groin.",
                "Give warm (not hot) sweet drinks if fully conscious."
            ],
            caution: "Handle gently; rough movement can trigger irregular heartbeat.",
            whenToSeekHelp: "Seek help immediately for confusion, slurred speech, or loss of coordination — these signal moderate to severe hypothermia."),
    ]
}

@MainActor
final class OfflineFirstAidService: ObservableObject {
    @Published var topics: [FirstAidTopic] = OfflineFirstAidStore.allTopics
    @Published var searchQuery = ""
    let contentVersion = OfflineFirstAidStore.version

    var categories: [String] {
        var seen = Set<String>()
        return topics.filter { seen.insert($0.category).inserted }.map { $0.category }
    }

    var filtered: [FirstAidTopic] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return topics }
        return topics.filter {
            $0.title.localizedCaseInsensitiveContains(q)
            || $0.category.localizedCaseInsensitiveContains(q)
            || $0.steps.joined(separator: " ").localizedCaseInsensitiveContains(q)
        }
    }
}
