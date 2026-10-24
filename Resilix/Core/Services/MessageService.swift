import Foundation

@MainActor
class MessageService: ObservableObject {
    @Published var messages: [MeshMessage] = []
    private let persistence = PersistenceController.shared
    private let security = SecurityManager()
    private let meshController: MeshController

    init(meshController: MeshController) { self.meshController = meshController; Task { await load() } }

    func load() async { messages = await persistence.loadMessages() }

    func send(text: String, to destination: String, from source: String) async throws -> MeshMessage {
        let msg = MeshMessage(id: UUID().uuidString, packetID: nil, threadID: destination, sourceNodeID: source, destinationNodeID: destination, text: text, createdAt: Date(), deliveryState: .queued, expirySeconds: 300, lastRoute: nil, priority: .normal)
        messages.append(msg)
        try? await persistence.saveMessages(messages)
        // build packet
        let payload = try JSONEncoder().encode(msg)
        let packet = PacketBuilder.makePacket(type: .chat, source: source, destination: destination, payload: payload, priority: .normal)
        try await meshController.send(packet: packet)
        if let idx = messages.firstIndex(where: {$0.id==msg.id}) { messages[idx].deliveryState = .sending; messages[idx].packetID = packet.id }
        try? await persistence.saveMessages(messages)
        return msg
    }

    func delete(id: String) async {
        messages.removeAll{ $0.id==id }
        try? await persistence.saveMessages(messages)
    }
    func updateDelivery(packetID: String, state: DeliveryState) async {
        if let idx = messages.firstIndex(where: {$0.packetID==packetID}) { messages[idx].deliveryState = state; try? await persistence.saveMessages(messages) }
    }
}
