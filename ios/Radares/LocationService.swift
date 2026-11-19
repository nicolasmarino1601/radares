import CoreLocation

/// GPS que sigue funcionando con la app en segundo plano o el teléfono bloqueado
/// (modo "location" en UIBackgroundModes + indicador azul de ubicación).
final class LocationService: NSObject, CLLocationManagerDelegate {
    var onLocation: ((CLLocation) -> Void)?
    var onError: ((String) -> Void)?

    private let manager = CLLocationManager()
    private var wantRunning = false
    private var backgroundSession: AnyObject?

    static let deniedText = "La app no tiene permiso de ubicación. Activalo en Ajustes del iPhone › Radares › Ubicación › «Mientras se usa la app»."

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        wantRunning = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            onError?(LocationService.deniedText)
        default:
            begin()
        }
    }

    func stop() {
        wantRunning = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        if #available(iOS 17.0, *) {
            (backgroundSession as? CLBackgroundActivitySession)?.invalidate()
        }
        backgroundSession = nil
    }

    private func begin() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        if #available(iOS 17.0, *), backgroundSession == nil {
            backgroundSession = CLBackgroundActivitySession()
        }
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard wantRunning else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            begin()
        case .denied, .restricted:
            onError?(LocationService.deniedText)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for l in locations { onLocation?(l) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let e = error as? CLError, e.code == .denied {
            onError?(LocationService.deniedText)
        }
    }
}
