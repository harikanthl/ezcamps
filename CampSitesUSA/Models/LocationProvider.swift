import CoreLocation
import Observation

@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var location: CLLocation?
    private(set) var authorization: CLAuthorizationStatus

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Every view reads `location`; without a filter each GPS tick re-renders them all.
        manager.distanceFilter = 50
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance? {
        location?.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.location = last }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways { self.manager.startUpdatingLocation() }
        }
    }
}
