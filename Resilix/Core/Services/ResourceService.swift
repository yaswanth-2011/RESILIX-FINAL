import Foundation

@MainActor
class ResourceService: ObservableObject {
    @Published var resources: [MapResource] = []
    private let persistence = PersistenceController.shared
    init() { Task { await load() } }
    func load() async { resources = await persistence.loadResources() }
    func add(_ r: MapResource) async {
        resources.append(r)
        try? await persistence.saveResources(resources)
        // broadcast via mesh would happen here
    }
    func flagStale(_ id: String) async {
        if let idx = resources.firstIndex(where: {$0.id==id}) { resources[idx].verification = .unverified; try? await persistence.saveResources(resources) }
    }
    func deduplicate(_ incoming: MapResource) async {
        if let idx = resources.firstIndex(where: {$0.id==incoming.id}) {
            if incoming.lastVerifiedAt ?? incoming.createdAt > resources[idx].lastVerifiedAt ?? resources[idx].createdAt { resources[idx] = incoming }
        } else { resources.append(incoming) }
        try? await persistence.saveResources(resources)
    }
}
