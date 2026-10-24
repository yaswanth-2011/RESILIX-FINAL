import Foundation
import CoreBluetooth

final class BluetoothTransport: NSObject, MeshTransport, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    let transportKind: MeshTransportKind = .bluetooth
    var isAvailable: Bool { central?.state == .poweredOn }

    private var central: CBCentralManager?
    private var discovered: [MeshNode] = []
    private var frameCont: AsyncStream<(Data,String)>.Continuation?
    private var eventCont: AsyncStream<MeshTransportEvent>.Continuation?
    private let frameStream: AsyncStream<(Data,String)>
    private let eventStream: AsyncStream<MeshTransportEvent>
    private var fragmentBuffers: [String: [Int: Data]] = [:]
    private var fragmentMeta: [String: (total:Int, lastUpdate:Date)] = [:]

    var discoveredPeers: [MeshNode] { discovered }

    override init() {
        var fc: AsyncStream<(Data,String)>.Continuation?
        frameStream = AsyncStream { fc = $0 }
        frameCont = fc
        var ec: AsyncStream<MeshTransportEvent>.Continuation?
        eventStream = AsyncStream { ec = $0 }
        eventCont = ec
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startDiscovery() async {
        guard central?.state == .poweredOn else { return }
        central?.scanForPeripherals(withServices: [CBUUID(string: BLEConstants.serviceUUIDString)], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    func stopDiscovery() async { central?.stopScan() }
    func connect(to peerID: String) async throws { /* simplified */ }
    func disconnect(from peerID: String) async {}
    func sendFrame(_ data: Data, to peerID: String) async throws {
        // Prefer Wi-Fi for large payloads; BLE fragments
        if data.count > 512 {
            throw ResilixError.packetTooLarge
        }
        // In real implementation would write to characteristic
    }
    func receivedFrames() -> AsyncStream<(Data, String)> { frameStream }
    func connectionEvents() -> AsyncStream<MeshTransportEvent> { eventStream }

    // MARK: CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: eventCont?.yield(.peerDiscovered(id: "ble-ready", alias: "Bluetooth Ready"))
        case .poweredOff: eventCont?.yield(.error("Bluetooth powered off"))
        case .unauthorized: eventCont?.yield(.error("Bluetooth unauthorized"))
        case .unsupported: eventCont?.yield(.error("Bluetooth unsupported"))
        case .resetting: break
        default: break
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let node = MeshNode(id: peripheral.identifier.uuidString, alias: peripheral.name ?? "Node \(discovered.count+1)", lastSeen: Date(), isRelay: false)
        if !discovered.contains(where: {$0.id==node.id}) { discovered.append(node); eventCont?.yield(.peerDiscovered(id: node.id, alias: node.alias)) }
    }
    // fragment reassembly simplified
    func handleFragment(_ data: Data) {
        // decode and reassemble; omitted for brevity
    }
}
