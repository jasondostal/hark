import CoreLocation

/// Best-effort location for tagging detections. When-in-use only; nil if denied.
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var last: CLLocation?
    /// The system's last fix, even when Hark isn't updating (Settings, selections after stopping).
    var lastKnown: CLLocation? { manager.location }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    /// background: keep tagging detections while the screen is locked (walk mode). When-in-use authorization
    /// is enough because updates start in the foreground; iOS shows the blue location pill meanwhile.
    /// precise: a survey's route wants the best fix; everything else is fine at 100 m (and easier on the battery).
    func start(background: Bool = false, precise: Bool = false) {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.desiredAccuracy = precise ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
        manager.allowsBackgroundLocationUpdates = background
        manager.showsBackgroundLocationIndicator = background
        manager.startUpdatingLocation()
    }
    func stop() { manager.stopUpdatingLocation(); manager.allowsBackgroundLocationUpdates = false }
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) { last = locs.last }
    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        if m.authorizationStatus == .authorizedWhenInUse || m.authorizationStatus == .authorizedAlways { m.startUpdatingLocation() }
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}
}
