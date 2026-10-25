import Foundation
import Combine

// OfflineFirstAidStore: curated, versioned, fully offline knowledge base.
// Content is shipped with the app bundle; no network content is downloaded.

enum OfflineFirstAidStore {
    static let version = "1.0.0"

    static var allTopics: [FirstAidTopic] { [
        FirstAidTopic(
            id: "bleeding", category: L("Bleeding"), title: L("Severe bleeding"),
            steps: [
                L("Wash or cover your hands if possible."),
                L("Apply firm, direct pressure with a clean cloth or bandage."),
                L("Maintain continuous pressure for at least 10 minutes without lifting the cloth."),
                L("If blood soaks through, add more cloth on top — do not remove the first layer."),
                L("Elevate the limb above heart level if possible and no fracture is suspected.")
            ],
            caution: L("Do not remove embedded objects. Stabilize them in place."),
            whenToSeekHelp: L("Seek professional help immediately if bleeding is heavy, spurting, or does not slow after 10 minutes of pressure.")),

        FirstAidTopic(
            id: "cpr", category: L("Cardiac"), title: L("CPR basics (adults)"),
            steps: [
                L("Check responsiveness: tap shoulders and shout."),
                L("Call for help or send someone to fetch an AED if available."),
                L("Begin chest compressions in center of the chest, 100–120 per minute, 5–6 cm deep."),
                L("Give 2 rescue breaths after 30 compressions if you are trained."),
                L("Continue until professional help arrives or the person responds.")
            ],
            caution: L("Compression-only CPR is acceptable if you are untrained in rescue breaths."),
            whenToSeekHelp: L("Always seek professional help for any cardiac event.")),

        FirstAidTopic(
            id: "burn", category: L("Burns"), title: L("Burn care"),
            steps: [
                L("Cool the burn with clean, cool running water for at least 10 minutes."),
                L("Remove rings or tight clothing near the burn before swelling starts."),
                L("Cover loosely with a sterile, non-stick dressing or clean cloth."),
                L("Do not apply ice, toothpaste, butter, or creams."),
                L("Monitor the person for signs of shock.")
            ],
            caution: nil,
            whenToSeekHelp: L("Seek care for burns that are large, deep, blistered, on the face/hands/joints, or caused by electricity or chemicals.")),

        FirstAidTopic(
            id: "fracture", category: L("Injury"), title: L("Suspected fracture"),
            steps: [
                L("Keep the limb still; do not try to straighten it."),
                L("Apply a splint in the position found, padding around it."),
                L("Apply a cold pack wrapped in cloth to reduce swelling."),
                L("Elevate the limb if possible without moving the injury site.")
            ],
            caution: nil,
            whenToSeekHelp: L("Seek professional help for any suspected fracture, especially with deformity, numbness, or open wounds.")),

        FirstAidTopic(
            id: "choking", category: L("Airway"), title: L("Choking (conscious adult)"),
            steps: [
                L("Ask whether the person is choking and can speak."),
                L("Give 5 firm back blows between the shoulder blades."),
                L("Give 5 abdominal thrusts (Heimlich maneuver)."),
                L("Alternate back blows and abdominal thrusts until the object clears.")
            ],
            caution: nil,
            whenToSeekHelp: L("If the obstruction does not clear and the person becomes unresponsive, begin CPR and seek emergency help.")),

        FirstAidTopic(
            id: "hypothermia", category: L("Exposure"), title: L("Hypothermia response"),
            steps: [
                L("Move the person to a warm, dry, sheltered place."),
                L("Remove wet clothing and replace with dry layers, covering the head."),
                L("Warm the center of the body first — chest, neck, head, groin."),
                L("Give warm (not hot) sweet drinks if fully conscious.")
            ],
            caution: L("Handle gently; rough movement can trigger irregular heartbeat."),
            whenToSeekHelp: L("Seek help immediately for confusion, slurred speech, or loss of coordination — these signal moderate to severe hypothermia.")),
    ] }
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
