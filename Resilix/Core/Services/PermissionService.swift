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
            @unknown default: bluetoothState = .notDetermined
            }
        }
        
        // Local Network - check by attempting Bonjour browse
        checkLocalNetworkPermission()
        
        // Location
        let status = CLLocationManager.authorizationStatus()
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
        var didComplete = false
        
        browser.stateUpdateHandler = { [weak self] state in
            guard !didComplete else { return }
            switch state {
            case .ready:
                didComplete = true
                Task { @MainActor in self?.localNetworkState = .authorized }
                browser.cancel()
            case .failed(let error):
                didComplete = true
                let nsError = error as NSError
                if nsError.code == 1 { // Permission denied
                    Task { @MainActor in self?.localNetworkState = .denied }
                } else {
                    Task { @MainActor in self?.localNetworkState = .authorized }
                }
                browser.cancel()
            case .cancelled:
                if !didComplete {
                    didComplete = true
                    Task { @MainActor in self?.localNetworkState = .notDetermined }
                }
            default: break
            }
        }
        browser.start(queue: .main)
        
        // Timeout after 2 seconds
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !didComplete {
                didComplete = true
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
