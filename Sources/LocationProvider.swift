import CoreLocation
import Combine

@MainActor
final class LocationProvider: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var message: String?
    @Published var requesting = false
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            requesting = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            requesting = true
            message = nil
            manager.startUpdatingLocation()
        case .denied, .restricted:
            requesting = false
            message = "Allow GeoSpoof in System Settings → Privacy & Security → Location Services to show your Mac’s location. You can still choose a pin anywhere."
        @unknown default: break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus != .notDetermined { start() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0,
              abs(latest.timestamp.timeIntervalSinceNow) < 120 else { return }
        location = latest
        requesting = false
        message = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        requesting = false
        message = "Your Mac’s location is unavailable. Check Location Services and Wi-Fi, or choose a pin on the map."
    }
}
