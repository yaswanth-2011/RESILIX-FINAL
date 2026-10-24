import Foundation

@MainActor
class SOSService: ObservableObject {
    @Published var activeSOS: SOSPacket?
    @Published var incidents: [Incident] = []
    private let persistence = PersistenceController.shared
    private let meshController: MeshController

    init(meshController: MeshController) { self.meshController = meshController; Task { await load() } }
    func load() async { incidents = await persistence.loadIncidents() }

    func dispatch(category: SOSCategory, severity: SOSSeverity, note: String?, lat: Double?, lon: Double?, source: String) async throws {
        let sos = SOSPacket(id: UUID().uuidString, category: category, severity: severity, note: note, latitude: lat, longitude: lon, createdAt: Date(), sourceNodeID: source)
        activeSOS = sos
        var incident = Incident(id: sos.id, category: category, severity: severity, status: .active, createdAt: sos.createdAt, lastUpdateAt: Date(), sourceNodeID: source, note: note, latitude: lat, longitude: lon, routeSummary: nil, hops: nil, acknowledged: false, version: 1, expiry: Date().addingTimeInterval(3600))
        incidents.insert(incident, at: 0)
        try? await persistence.saveIncidents(incidents)
        let payload = try JSONEncoder().encode(sos)
        let packet = PacketBuilder.makePacket(type: .sos, source: source, destination: "", payload: payload, priority: .sos)
        try await meshController.send(packet: packet)
    }

    func acknowledge(_ id: String) async {
        if let idx = incidents.firstIndex(where: {$0.id==id}) { incidents[idx].acknowledged = true; incidents[idx].status = .acknowledged; try? await persistence.saveIncidents(incidents) }
    }
}
