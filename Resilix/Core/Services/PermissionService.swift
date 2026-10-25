import Foundation
import CoreLocation
import CoreBluetooth
import Network
#if canImport(UIKit)
import UIKit
import Combine
#endif

@MainActor
class PermissionService: ObservableObject {
    @Published var bluetoothState: PermissionState = .notDetermined
    @Published var localNetworkState: PermissionState = .notDetermined
    @Published var locationState: PermissionState = .notDetermined
    
    private let locationManager = CLLocationManager()
    private var bluetoothManager: CBCentralManager?
    
    init() {
        setupBluetoothObserver()
        refresh()
    }
    
    private func setupBluetoothObserver() {
        bluetoothManager = CBCentralManager(delegate: nil, queue: .main)
    }
    
    func refresh() {
        // Bluetooth
        if let mgr = bluetoothManager {
            switch mgr.state {
            case .poweredOn: bluetoothState = .authorized
            case .poweredOff: bluetoothState = .denied
            case .unauthorized: bluetoothState = .denied
            case .unsupported: bluetoothState = .unsupported
            case .resetting: bluetoothState = .notDetermined
            case .unknown: bluetoothState = .notDetermined
            @unknown default: bluetoothState = .notDetermined
            }
        }
        
        // Local Network - check by attempting Bonjour browse
        checkLocalNetworkPermission()
        
        // Location
        // `CLLocationManager.authorizationStatus()` (a class method) was
        // deprecated in iOS 14; the instance property is the current API.
        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: locationState = .authorized
        case .denied: locationState = .denied
        case .restricted: locationState = .restricted
        case .notDetermined: locationState = .notDetermined
        @unknown default: locationState = .notDetermined
        }
    }
    
    private func checkLocalNetworkPermission() {
        // Use NWBrowser to test local network access
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_resilix._tcp", domain: "local."), using: params)
        // The handler and the timeout below race; the first outcome wins and
        // the other stands down. A captured `var` cannot be mutated from a
        // concurrently executing closure under Swift 6.
        let gate = OnceGate()

        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                guard gate.claim() else { return }
                Task { @MainActor in self?.localNetworkState = .authorized }
                browser.cancel()
            case .failed(let error):
                guard gate.claim() else { return }
                let nsError = error as NSError
                let outcome: PermissionState = nsError.code == 1 ? .denied : .authorized
                Task { @MainActor in self?.localNetworkState = outcome }
                browser.cancel()
            case .cancelled:
                guard gate.claim() else { return }
                Task { @MainActor in self?.localNetworkState = .notDetermined }
            default:
                break
            }
        }
        browser.start(queue: .main)

        // Timeout after 2 seconds
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if gate.claim() {
                browser.cancel()
                await MainActor.run { self.localNetworkState = .notDetermined }
            }
        }
    }
    
    func requestBluetooth() {
        // Trigger Bluetooth permission by creating a new manager
        let mgr = CBCentralManager(delegate: nil, queue: .main)
        _ = mgr.state
        bluetoothManager = mgr
        refresh()
    }
    
    func requestLocalNetwork() {
        checkLocalNetworkPermission()
    }
    
    func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
        // Refresh after a short delay to let user respond
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run { self.refresh() }
        }
    }
    
    func openSettings() {
#if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
#endif
    }
}
