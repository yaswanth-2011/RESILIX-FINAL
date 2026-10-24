import Foundation

enum MeshTransportEvent: Sendable, Equatable {
    case peerDiscovered(id: String, alias: String)
    case peerLost(id: String)
    case connected(id: String)
    case disconnected(id: String)
    case error(String)
}

/// A radio that can exchange packets with other Resilix installations.
///
/// Implementations are responsible for framing (see `FrameCodec`),
/// fragmentation and reassembly; the mesh layer above only ever deals with
/// complete packets.
protocol MeshTransport: AnyObject, Sendable {
    var transportKind: MeshTransportKind { get }
    var isAvailable: Bool { get }
    var discoveredPeers: [MeshNode] { get }
    /// Peers that currently have an open connection on this transport.
    var connectedPeerIDs: Set<String> { get }
    /// Identity of the local node, handed to the transport so that it can
    /// answer the handshake of a peer.
    func configure(nodeID: String, alias: String, hello: PeerHello) async
    /// Identity of a connected peer (public keys are needed to encrypt).
    func peerHello(for peerID: String) -> PeerHello?
    func startDiscovery() async
    func stopDiscovery() async
    func connect(to peerID: String) async throws
    func disconnect(from peerID: String) async
    /// Sends one complete packet (already encoded) to a peer.
    func sendFrame(_ data: Data, to peerID: String) async throws
    func receivedFrames() -> AsyncStream<(Data, String)>
    func connectionEvents() -> AsyncStream<MeshTransportEvent>
}

/// Identity information exchanged right after a connection is established.
///
/// The handshake carries the node identifier and the long term public keys
/// so that the mesh can encrypt traffic end-to-end and verify the origin of
/// every packet.
struct PeerHello: Codable, Sendable, Equatable {
    var nodeID: String
    var alias: String
    var agreementPublicKey: Data
    var signingPublicKey: Data
    var supportsRelay: Bool
    var protocolVersion: UInt8
}
