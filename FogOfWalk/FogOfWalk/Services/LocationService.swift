import CoreLocation
import Observation

// MARK: - LocationManagerProtocol

protocol LocationManagerProtocol: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var distanceFilter: CLLocationDistance { get set }
    var pausesLocationUpdatesAutomatically: Bool { get set }
    var activityType: CLActivityType { get set }
    var allowsBackgroundLocationUpdates: Bool { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestAlwaysAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func startMonitoringSignificantLocationChanges()
    func stopMonitoringSignificantLocationChanges()
    /// Shows the blue status-bar indicator while tracking in the background (iOS only).
    func enableBackgroundLocationIndicator()
}

// Default no-op so mocks and non-iOS builds don't need to implement this.
extension LocationManagerProtocol {
    func enableBackgroundLocationIndicator() {}
}

extension CLLocationManager: LocationManagerProtocol {
    func enableBackgroundLocationIndicator() {
        #if os(iOS)
        showsBackgroundLocationIndicator = true
        #endif
    }
}

// MARK: - LocationService

@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager: LocationManagerProtocol

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var currentLocation: CLLocation?
    private(set) var isPaused: Bool = false

    /// Called on the main actor on every significant location update.
    var onLocationUpdate: ((CLLocation) -> Void)?

    init(manager: LocationManagerProtocol = CLLocationManager()) {
        self.manager = manager
        super.init()
        manager.delegate                           = self
        manager.desiredAccuracy                    = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter                     = 15   // metres
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType                       = .fitness
        manager.enableBackgroundLocationIndicator()
        authorizationStatus                        = manager.authorizationStatus
    }

    func requestPermissionAndStart() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            startTracking()
        #if os(iOS)
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
            startTracking()
        #endif
        default:
            break
        }
    }

    private func startTracking() {
        manager.allowsBackgroundLocationUpdates = true
        manager.startMonitoringSignificantLocationChanges()
        manager.startUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate
    // Delegate methods are called by the system from any thread, so they must be
    // `nonisolated`. They dispatch back to the main actor to mutate state.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.authorizationStatus = status
            let authorized: Bool
            #if os(iOS)
            authorized = status == .authorizedAlways || status == .authorizedWhenInUse
            #else
            authorized = status == .authorizedAlways
            #endif
            if authorized {
                self?.startTracking()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.currentLocation = location
            self?.isPaused        = false
            self?.onLocationUpdate?(location)
        }
    }

    nonisolated func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.isPaused = true
        }
    }

    nonisolated func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.isPaused = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationService: \(error.localizedDescription)")
    }
}
