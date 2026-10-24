import Foundation
import CoreLocation

/// Owns the GPS position of the device.
///
/// The position is only shared with the mesh when the user enables the
/// location sharing in the settings, and it is rounded to roughly 100
/// metres before it leaves the device.
@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var lastErrorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        authorization = manager.authorizationStatus
    }

    // MARK: - Permissions

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    var isAuthorized: Bool {
        authorization == .authorizedAlways || authorization == .authorizedWhenInUse
    }

    // MARK: - Updates

    func startUpdates() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let location else { return nil }
        return location.coordinate
    }

    /// Distance in metres to another coordinate (nil without a fix).
    func distance(to coordinate: CLLocationCoordinate2D) -> Double? {
        guard let location else { return nil }
        return location.distance(from: CLLocation(latitude: coordinate.latitude,
                                                  longitude: coordinate.longitude))
    }

    /// Human readable distance, e.g. "120 m" or "1.4 km".
    func formattedDistance(to coordinate: CLLocationCoordinate2D) -> String? {
        guard let metres = distance(to: coordinate) else { return nil }
        if metres < 1000 {
            return "\(Int(metres.rounded())) m"
        }
        return String(format: "%.1f km", metres / 1000)
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            self.location = last
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastErrorMessage = error.localizedDescription
        }
    }
}
