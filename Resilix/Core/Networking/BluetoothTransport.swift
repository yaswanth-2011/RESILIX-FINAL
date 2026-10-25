import Foundation
import CoreBluetooth

/// Bluetooth LE transport.
///
/// The implementation runs both roles at the same time:
///
/// * **central** – scans for other Resilix nodes, connects to them and
///   writes packets to their characteristic;
/// * **peripheral** – advertises the Resilix service so that other nodes
///   can find this device and pushes packets to subscribed centrals.
///
/// Every connection starts with a `PeerHello` handshake which exchanges the
/// node identifier and the long term public keys. Packets larger than the
/// negotiated MTU are split into frames by `FrameCodec` and reassembled on
/// the receiving side.
final class BluetoothTransport: NSObject, MeshTransport, @unchecked Sendable {
    let transportKind: MeshTransportKind = .bluetooth

    // MARK: - State
    private let queue = DispatchQueue(label: "com.resilix.bluetooth")
    private var central: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?

    private var nodeID: String = ""
    private var alias: String = ResilixConstants.defaultAlias
    private var localHello: PeerHello?

    /// Peers indexed by the transport level identifier (CB UUID until the
    /// handshake revealed the real node identifier).
    private var nodes: [String: MeshNode] = [:]
    private var peripherals: [String: CBPeripheral] = [:]
    private var characteristics: [String: CBCharacteristic] = [:]
    private var subscribedCentrals: [String: CBCentral] = [:]
    /// GATT objects published by the peripheral role.
    /// `updateValue(_:for:onSubscribedCentrals:)` needs the concrete
    /// characteristic, not its UUID.
    private var outboundCharacteristic: CBMutableCharacteristic?
    private var publishedService: CBMutableService?
    /// Centrals seen by the peripheral role, keyed by their Bluetooth UUID.
    private var nodeIDByCentralUUID: [UUID: String] = [:]
    /// Frames the transmit queue could not accept yet.
    private var pendingNotifications: [(data: Data, central: CBCentral)] = []
    private var hellos: [String: PeerHello] = [:]
    private var transportIDByNodeID: [String: String] = [:]
    private var nodeIDByTransportID: [String: String] = [:]

    private var connected: Set<String> = []
    private var reconnectAttempts: [String: Int] = [:]
    private var connectContinuations: [String: CheckedContinuation<Void, Error>] = [:]
    private var buffers: [String: (count: Int, chunks: [Int: Data], updated: Date)] = [:]

    private var frameCont: AsyncStream<(Data, String)>.Continuation?
    private var eventCont: AsyncStream<MeshTransportEvent>.Continuation?
    private let frameStream: AsyncStream<(Data, String)>
    private let eventStream: AsyncStream<MeshTransportEvent>

    private let characteristicUUID = CBUUID(string: BLEConstants.characteristicUUIDString)
    private let serviceUUID = CBUUID(string: BLEConstants.serviceUUIDString)

    // MARK: - Init
    override init() {
        var fc: AsyncStream<(Data, String)>.Continuation?
        frameStream = AsyncStream { fc = $0 }
        frameCont = fc
        var ec: AsyncStream<MeshTransportEvent>.Continuation?
        eventStream = AsyncStream { ec = $0 }
        eventCont = ec
        super.init()
        queue.async { [weak self] in
            guard let self else { return }
            self.central = CBCentralManager(delegate: self, queue: self.queue,
                                           options: [CBCentralManagerOptionShowPowerAlertKey: false])
            self.peripheralManager = CBPeripheralManager(delegate: self, queue: self.queue,
                                                        options: [CBPeripheralManagerOptionShowPowerAlertKey: false])
        }
    }

    deinit {
        frameCont?.finish()
        eventCont?.finish()
    }

    // MARK: - MeshTransport

    var isAvailable: Bool { central?.state == .poweredOn }

    var discoveredPeers: [MeshNode] {
        queue.sync { Array(nodes.values) }
    }

    var connectedPeerIDs: Set<String> {
        queue.sync { Set(connected) }
    }

    func configure(nodeID: String, alias: String, hello: PeerHello) async {
        queue.async { [weak self] in
            guard let self else { return }
            self.nodeID = nodeID
            self.alias = alias
            self.localHello = hello
            self.startAdvertisingIfPossible()
        }
    }

    func peerHello(for peerID: String) -> PeerHello? {
        queue.sync { hellos[peerID] }
    }

    func startDiscovery() async {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.central?.state == .poweredOn else { return }
            self.central?.scanForPeripherals(withServices: [self.serviceUUID],
                                             options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            self.startAdvertisingIfPossible()
        }
    }

    func stopDiscovery() async {
        queue.async { [weak self] in
            self?.central?.stopScan()
        }
    }

    func connect(to peerID: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: ResilixError.transportUnavailable(L("Bluetooth transport stopped")))
                    return
                }
                let transportID = self.transportIDByNodeID[peerID] ?? peerID
                guard let peripheral = self.peripherals[transportID] else {
                    continuation.resume(throwing: ResilixError.transportUnavailable(String(format: L("Unknown peer %@"), peerID)))
                    return
                }
                if self.connected.contains(peerID) {
                    continuation.resume()
                    return
                }
                self.connectContinuations[transportID] = continuation
                self.central?.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
                DispatchQueue.global().asyncAfter(deadline: .now() + 8) { [weak self] in
                    guard let self else { return }
                    self.queue.async {
                        guard let pending = self.connectContinuations.removeValue(forKey: transportID) else { return }
                        pending.resume(throwing: ResilixError.transportUnavailable(String(format: L("Could not connect to %@"), peerID)))
                    }
                }
            }
        }
    }

    func disconnect(from peerID: String) async {
        queue.async { [weak self] in
            guard let self else { return }
            let transportID = self.transportIDByNodeID[peerID] ?? peerID
            if let peripheral = self.peripherals[transportID] {
                self.central?.cancelPeripheralConnection(peripheral)
            }
            self.connected.remove(peerID)
            if let pending = self.connectContinuations.removeValue(forKey: transportID) {
                pending.resume(throwing: ResilixError.transportUnavailable(L("Connection cancelled")))
            }
        }
    }

    func sendFrame(_ data: Data, to peerID: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: ResilixError.transportUnavailable(L("Bluetooth transport stopped")))
                    return
                }
                let transportID = self.transportIDByNodeID[peerID] ?? peerID
                let frames = FrameCodec.frames(for: data, mtu: ResilixConstants.bleMTU, transferID: UUID().uuidString)

                if let peripheral = self.peripherals[transportID], let characteristic = self.characteristics[transportID] {
                    for frame in frames {
                        peripheral.writeValue(frame, for: characteristic, type: .withResponse)
                    }
                    continuation.resume()
                    return
                }
                if let central = self.subscribedCentrals[transportID] {
                    guard self.enqueueNotifications(frames, to: central) else {
                        continuation.resume(throwing: ResilixError.transportUnavailable(
                            String(format: L("Bluetooth send queue is full for %@"), peerID)))
                        return
                    }
                    continuation.resume()
                    return
                }
                continuation.resume(throwing: ResilixError.transportUnavailable(String(format: L("No Bluetooth link to %@"), peerID)))
            }
        }
    }

    func receivedFrames() -> AsyncStream<(Data, String)> { frameStream }
    func connectionEvents() -> AsyncStream<MeshTransportEvent> { eventStream }

    // MARK: - Peripheral (advertising) side

    private func startAdvertisingIfPossible() {
        guard let peripheralManager, peripheralManager.state == .poweredOn, !nodeID.isEmpty else { return }
        // The GATT service has to exist before advertising. Otherwise a central
        // finds the service UUID in the advertisement, connects and discovers
        // no characteristic at all - the link would never carry a frame.
        // `peripheralManager(_:didAdd:error:)` re-enters this method once the
        // stack confirmed the service.
        guard publishedService != nil else {
            publishServiceIfNeeded(peripheralManager)
            return
        }
        guard !peripheralManager.isAdvertising else { return }
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: BluetoothTransport.advertisedName(nodeID: nodeID)
        ])
    }

    /// Creates and publishes the writable/notifying characteristic exactly once.
    private func publishServiceIfNeeded(_ peripheralManager: CBPeripheralManager) {
        guard publishedService == nil else { return }
        let characteristic = CBMutableCharacteristic(type: characteristicUUID,
                                                     properties: [.write, .notify],
                                                     value: nil,
                                                     permissions: [.writeable])
        let service = CBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]
        outboundCharacteristic = characteristic
        publishedService = service
        peripheralManager.add(service)
    }

    /// Hands frames to the Bluetooth stack, buffering whatever it cannot take
    /// right now (the stack returns `false` when its transmit queue is full).
    @discardableResult
    private func enqueueNotifications(_ frames: [Data], to central: CBCentral) -> Bool {
        guard let characteristic = outboundCharacteristic else { return false }
        for frame in frames {
            if let manager = peripheralManager,
               manager.updateValue(frame, for: characteristic, onSubscribedCentrals: [central]) {
                continue
            }
            guard pendingNotifications.count < 64 else { return false }
            pendingNotifications.append((frame, central))
        }
        return true
    }

    /// Called by the stack when the transmit queue has room again.
    private func flushPendingNotifications() {
        guard let characteristic = outboundCharacteristic, let manager = peripheralManager else { return }
        while let next = pendingNotifications.first {
            guard manager.updateValue(next.data, for: characteristic, onSubscribedCentrals: [next.central]) else { return }
            pendingNotifications.removeFirst()
        }
    }

    static func advertisedName(nodeID: String) -> String { "Resilix:\(nodeID)" }

    static func nodeID(fromAdvertisedName name: String?) -> String? {
        guard let name, name.hasPrefix("Resilix:") else { return nil }
        let id = String(name.dropFirst("Resilix:".count))
        return id.isEmpty ? nil : id
    }

    // MARK: - Identifier helpers

    private func nodeID(for transportID: String) -> String { nodeIDByTransportID[transportID] ?? transportID }
    private func transportID(for nodeID: String) -> String { transportIDByNodeID[nodeID] ?? nodeID }

    // MARK: - Frame handling

    private func handleFrameData(_ data: Data, transportID: String) {
        guard let frame = FrameCodec.parse(data) else {
            eventCont?.yield(.error(L("Dropped malformed frame")))
            return
        }
        switch frame.kind {
        case .handshake:
            guard let hello = try? JSONDecoder().decode(PeerHello.self, from: frame.payload) else { return }
            applyHello(hello, transportID: transportID)
        case .single:
            frameCont?.yield((frame.payload, nodeID(for: transportID)))
        case .fragment:
            guard let transferID = frame.transferID else { return }
            var buffer = buffers[transferID] ?? (count: frame.count, chunks: [:], updated: Date())
            buffer.chunks[frame.index] = frame.payload
            buffer.updated = Date()
            buffers[transferID] = buffer
            if buffer.chunks.count == buffer.count {
                let frames = buffer.chunks.map { index, payload in
                    FrameCodec.ParsedFrame(kind: .fragment, index: index, count: buffer.count, transferID: nil, payload: payload)
                }
                buffers.removeValue(forKey: transferID)
                if let assembled = FrameCodec.reassemble(frames) {
                    frameCont?.yield((assembled, nodeID(for: transportID)))
                }
            } else {
                purgeStaleBuffers()
            }
        }
    }

    private func purgeStaleBuffers() {
        let cutoff = Date().addingTimeInterval(-60)
        for (key, value) in buffers where value.updated < cutoff {
            buffers.removeValue(forKey: key)
        }
    }

    private func applyHello(_ hello: PeerHello, transportID: String) {
        let resolved = hello.nodeID
        nodeIDByTransportID[transportID] = resolved
        transportIDByNodeID[resolved] = transportID
        hellos[resolved] = hello

        let node = MeshNode(id: resolved,
                            alias: hello.alias,
                            displayName: hello.alias,
                            lastSeen: Date(),
                            isRelay: hello.supportsRelay,
                            transportHint: MeshTransportKind.bluetooth.rawValue)
        nodes[resolved] = node

        if !connected.contains(resolved) {
            connected.insert(resolved)
            reconnectAttempts[resolved] = 0
            if let pending = connectContinuations.removeValue(forKey: transportID) {
                pending.resume()
            }
            eventCont?.yield(.connected(id: resolved))
        }
        eventCont?.yield(.peerDiscovered(id: resolved, alias: hello.alias))
        sendHandshake(to: transportID)
    }

    private func sendHandshake(to transportID: String) {
        guard let hello = localHello, let frame = FrameCodec.handshakeFrame(hello) else { return }
        if let peripheral = peripherals[transportID], let characteristic = characteristics[transportID] {
            peripheral.writeValue(frame, for: characteristic, type: .withResponse)
        } else if let central = subscribedCentrals[transportID] {
            enqueueNotifications([frame], to: central)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothTransport: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(withServices: [serviceUUID],
                                       options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            startAdvertisingIfPossible()
        case .poweredOff:
            eventCont?.yield(.error(L("Bluetooth is switched off")))
        case .unauthorized:
            eventCont?.yield(.error(L("Bluetooth permission denied")))
        case .unsupported:
            eventCont?.yield(.error(L("Bluetooth LE is not supported on this device")))
        case .resetting:
            eventCont?.yield(.error(L("Bluetooth is resetting")))
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertised = BluetoothTransport.nodeID(fromAdvertisedName: advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? BluetoothTransport.nodeID(fromAdvertisedName: peripheral.name)
        let transportID = advertised ?? peripheral.identifier.uuidString
        peripherals[transportID] = peripheral
        let resolved = nodeID(for: transportID)
        let alias = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Resilix Node"
        let node = MeshNode(id: resolved,
                            alias: alias.replacingOccurrences(of: "Resilix:", with: ""),
                            displayName: alias,
                            lastSeen: Date(),
                            isRelay: false,
                            transportHint: MeshTransportKind.bluetooth.rawValue)
        nodes[resolved] = node
        eventCont?.yield(.peerDiscovered(id: resolved, alias: node.alias))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = nodeIDByPeripheralCache[peripheral.identifier] ?? peripheral.identifier.uuidString
        peripherals[id] = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let id = nodeIDByPeripheralCache[peripheral.identifier] ?? peripheral.identifier.uuidString
        if let pending = connectContinuations.removeValue(forKey: id) {
            pending.resume(throwing: ResilixError.transportUnavailable(L("Connection failed")))
        }
        scheduleReconnect(for: id)
        eventCont?.yield(.error(L("Connection failed")))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let id = nodeIDByPeripheralCache[peripheral.identifier] ?? peripheral.identifier.uuidString
        let resolved = nodeID(for: id)
        connected.remove(resolved)
        characteristics.removeValue(forKey: id)
        eventCont?.yield(.disconnected(id: resolved))
        if error != nil { scheduleReconnect(for: id) }
    }

    private func scheduleReconnect(for transportID: String) {
        let key = nodeID(for: transportID)
        let next = (reconnectAttempts[key] ?? 0) + 1
        reconnectAttempts[key] = next
        guard next <= 5, let peripheral = peripherals[transportID] else { return }
        let delay = min(30.0, pow(2.0, Double(next)))
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.central?.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
        }
    }

    /// Maps a CoreBluetooth peripheral to the transport level identifier.
    private var nodeIDByPeripheralCache: [UUID: String] {
        var result: [UUID: String] = [:]
        for (transportID, peripheral) in peripherals {
            result[peripheral.identifier] = transportID
        }
        return result
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothTransport: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let found = service.characteristics else { return }
        let transportID = nodeIDByPeripheralCache[peripheral.identifier] ?? peripheral.identifier.uuidString
        for characteristic in found where characteristic.uuid == characteristicUUID {
            characteristics[transportID] = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
            sendHandshake(to: transportID)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        let transportID = nodeIDByPeripheralCache[peripheral.identifier] ?? peripheral.identifier.uuidString
        handleFrameData(data, transportID: transportID)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            eventCont?.yield(.error(String(format: L("Bluetooth write failed: %@"), error.localizedDescription)))
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BluetoothTransport: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheralManager: CBPeripheralManager) {
        switch peripheralManager.state {
        case .poweredOn:
            startAdvertisingIfPossible()
        case .poweredOff:
            eventCont?.yield(.error(L("Bluetooth is switched off")))
        case .unauthorized:
            eventCont?.yield(.error(L("Bluetooth permission denied")))
        case .unsupported:
            eventCont?.yield(.error(L("Bluetooth LE is not supported on this device")))
        case .resetting:
            eventCont?.yield(.error(L("Bluetooth is resetting")))
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheralManager: CBPeripheralManager, error: Error?) {
        if let error {
            eventCont?.yield(.error(String(format: L("Could not advertise: %@"), error.localizedDescription)))
        }
    }

    /// The service is published asynchronously. Advertising only starts once
    /// the stack confirmed it, so a scanning central never sees a service UUID
    /// that has no characteristic behind it.
    func peripheralManager(_ peripheralManager: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            publishedService = nil
            outboundCharacteristic = nil
            eventCont?.yield(.error(String(format: L("Could not publish the Bluetooth service: %@"),
                                           error.localizedDescription)))
            return
        }
        startAdvertisingIfPossible()
    }

    func peripheralManager(_ peripheralManager: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard request.characteristic.uuid == characteristicUUID else {
                peripheralManager.respond(to: request, withResult: .attributeNotFound)
                continue
            }
            if let data = request.value {
                let transportID = centralTransportID(for: request.central.identifier)
                handleFrameData(data, transportID: transportID)
            }
            peripheralManager.respond(to: request, withResult: .success)
        }
    }

    func peripheralManager(_ peripheralManager: CBPeripheralManager,
                           central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        guard characteristic.uuid == characteristicUUID else { return }
        let transportID = centralTransportID(for: central.identifier)
        subscribedCentrals[transportID] = central
        if let hello = localHello, let frame = FrameCodec.handshakeFrame(hello) {
            enqueueNotifications([frame], to: central)
        }
    }

    func peripheralManager(_ peripheralManager: CBPeripheralManager,
                           central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        let transportID = centralTransportID(for: central.identifier)
        subscribedCentrals.removeValue(forKey: transportID)
    }

    /// The transmit queue has room again: flush what was buffered.
    func peripheralManagerIsReady(toUpdateSubscribers peripheralManager: CBPeripheralManager) {
        flushPendingNotifications()
    }

    /// Central UUIDs are not known before the handshake, therefore they are
    /// mapped lazily through the node identifier carried by the hello frame.
    private func centralTransportID(for uuid: UUID) -> String {
        if let existing = nodeIDByCentralUUID[uuid] { return existing }
        let fallback = uuid.uuidString
        nodeIDByCentralUUID[uuid] = fallback
        return fallback
    }
}
