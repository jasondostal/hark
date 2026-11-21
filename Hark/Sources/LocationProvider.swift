import CoreLocation

/// Best-effort location for tagging detections. When-in-use only; nil if denied.
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var last: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    func start() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
    }
    func stop() { manager.stopUpdatingLocation() }
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) { last = locs.last }
    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        if m.authorizationStatus == .authorizedWhenInUse || m.authorizationStatus == .authorizedAlways { m.startUpdatingLocation() }
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}
}
