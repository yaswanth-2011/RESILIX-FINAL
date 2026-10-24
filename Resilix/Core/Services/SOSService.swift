import Foundation

/// Sends and receives SOS alerts over the mesh.
///
/// The alert is encrypted for every known peer and broadcast with the
/// highest priority, so relays forward it first. The incident is stored
/// locally, therefore the history survives a restart.
@MainActor
final class SOSService: ObservableObject {
    @Published private(set) var activeSOS: SOSPacket?
    @Published private(set) var incidents: [Incident] = []
    @Published private(set) var lastErrorMessage: String?

    private let persistence = PersistenceController.shared
    private let meshController: MeshController

    init(meshController: MeshController) {
        self.meshController = meshController
        Task { await load() }
    }

    func load() async {
        incidents = await persistence.loadIncidents()
    }

    /// Broadcasts an SOS alert.
    func dispatch(category: SOSCategory,
                  severity: SOSSeverity,
                  note: String?,
                  lat: Double?,
                  lon: Double?,
                  source: String) async throws {
        let sos = SOSPacket(id: UUID().uuidString,
                            category: category,
                            severity: severity,
                            note: note,
                            latitude: lat,
                            longitude: lon,
                            createdAt: Date(),
                            sourceNodeID: source)
        activeSOS = sos
        let incident = Incident(id: sos.id,
                                category: category,
                                severity: severity,
                                status: .active,
                                createdAt: sos.createdAt,
                                lastUpdateAt: Date(),
                                sourceNodeID: source,
                                note: note,
                                latitude: lat,
                                longitude: lon,
                                routeSummary: nil,
                                hops: nil,
                                acknowledged: false,
                                version: 1,
                                expiry: Date().addingTimeInterval(3600))
        incidents.insert(incident, at: 0)
        try? await persistence.saveIncidents(incidents)

        let payload = try JSONEncoder().encode(sos)
        do {
            _ = try await meshController.sendSecurePacket(type: .sos,
                                                          plaintext: payload,
                                                          destination: "",
                                                          priority: .sos)
            lastErrorMessage = nil
        } catch {
            // No peer could be reached: the alert stays in the local history
            // and is retried by the user.
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Stores an SOS alert that was received over the mesh.
    func handleIncoming(_ delivered: DeliveredPayload) async {
        guard let sos = try? JSONDecoder().decode(SOSPacket.self, from: delivered.plaintext) else {
            lastErrorMessage = "A received SOS alert could not be read."
            return
        }
        if !incidents.contains(where: { $0.id == sos.id }) {
            let incident = Incident(id: sos.id,
                                    category: sos.category,
                                    severity: sos.severity,
                                    status: .active,
                                    createdAt: sos.createdAt,
                                    lastUpdateAt: Date(),
                                    sourceNodeID: sos.sourceNodeID,
                                    note: sos.note,
                                    latitude: sos.latitude,
                                    longitude: sos.longitude,
                                    routeSummary: delivered.route,
                                    hops: delivered.packet.hopCount,
                                    acknowledged: false,
                                    version: 1,
                                    expiry: sos.createdAt.addingTimeInterval(3600))
            incidents.insert(incident, at: 0)
            try? await persistence.saveIncidents(incidents)
        }
        if activeSOS == nil || activeSOS?.id != sos.id {
            activeSOS = sos
        }
    }

    func acknowledge(_ id: String) async {
        guard let index = incidents.firstIndex(where: { $0.id == id }) else { return }
        incidents[index].acknowledged = true
        incidents[index].status = .acknowledged
        try? await persistence.saveIncidents(incidents)
    }
}
