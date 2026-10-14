import CoreLocation
import Observation
import os

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
    private let diagnostics: LocationDiagnosticRecording
    private var sessionStartedAt: Date?
    private let defaults: UserDefaults
    let isStudyApp: Bool
    private(set) var isStudyTrackingDisabled: Bool
    static let studyTrackingDisabledKey = "locationStudy.trackingDisabled"
    private var studyResumeStartedAt: Date?
    private var applyMapLocation: ((Bool) -> Void)?
    // Delegate callbacks can arrive before a mode switch and execute afterward.
    // An epoch captured at receipt prevents those callbacks crossing either switch.
    nonisolated private let callbackEpoch = OSAllocatedUnfairLock(initialState: UInt64(0))

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var currentLocation: CLLocation?
    private(set) var isPaused: Bool = false
    /// True when the user has denied or restricted location permission.
    /// The UI can observe this to show an actionable prompt.
    private(set) var isPermissionDenied: Bool = false
    /// True when the user granted "While Using" but not "Always".
    /// The UI can observe this to prompt the user to upgrade in Settings.
    var needsAlwaysUpgrade: Bool {
        #if os(iOS)
        return authorizationStatus == .authorizedWhenInUse
        #else
        return false
        #endif
    }

    /// Called on the main actor on every significant location update.
    var onLocationUpdate: ((CLLocation) -> Void)?

    init(
        manager: LocationManagerProtocol = CLLocationManager(),
        diagnostics: LocationDiagnosticRecording? = nil,
        isStudyApp: Bool? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.manager = manager
        self.diagnostics = diagnostics ?? LocationStudyDiagnostics.shared
        self.defaults = defaults
        self.isStudyApp = isStudyApp ?? (Bundle.main.bundleIdentifier == LocationStudyDiagnostics.studyBundleID)
        self.isStudyTrackingDisabled = self.isStudyApp && defaults.bool(forKey: Self.studyTrackingDisabledKey)
        super.init()
        manager.delegate                           = self
        manager.desiredAccuracy                    = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter                     = 15   // metres
        // Auto-pause combined with `.fitness` lets iOS pause standard location updates
        // whenever it decides the user is stationary, and doesn't reliably resume delivery
        // while the app is backgrounded — updates only restart once the user reopens the
        // app. Disable auto-pause so tracking keeps running continuously in the background.
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType                       = .fitness
        manager.enableBackgroundLocationIndicator()
        authorizationStatus                        = manager.authorizationStatus
        if isStudyTrackingDisabled { stopStudyConsumers() }
    }

    /// Internal stationary diagnostic control. It is unavailable in the normal app
    /// and cannot change arms during a capture. Stop Capture only stops logging.
    @discardableResult
    func setStudyTrackingDisabled(_ disabled: Bool) -> Bool {
        guard isStudyApp, !diagnostics.isCapturing else { return false }
        guard disabled != isStudyTrackingDisabled else { return true }
        callbackEpoch.withLock { $0 &+= 1 }
        isStudyTrackingDisabled = disabled
        defaults.set(disabled, forKey: Self.studyTrackingDisabledKey)
        sessionStartedAt = nil
        currentLocation = nil
        studyResumeStartedAt = disabled ? nil : Date()
        if disabled {
            stopStudyConsumers()
        } else {
            applyMapLocation?(true)
            restartIfAuthorized()
        }
        recordStudyTrackingState()
        return true
    }

    /// The map consumer is changed synchronously with the manager, including
    /// maps created/recreated while the persisted control is off.
    func installStudyMapControl(_ apply: @escaping (Bool) -> Void) {
        guard isStudyApp else { return }
        applyMapLocation = apply
        apply(!isStudyTrackingDisabled)
    }

    func recordStudyTrackingState() {
        guard isStudyApp else { return }
        diagnostics.recordLifecycle("study_tracking_state", detail: isStudyTrackingDisabled ? "off" : "on")
    }

    private func stopStudyConsumers() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
        applyMapLocation?(false)
        isPaused = true
    }

    func requestPermissionAndStart() {
        guard !isStudyTrackingDisabled else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            diagnostics.recordLifecycle("permission_request", detail: "always")
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            startTracking()
        #if os(iOS)
        case .authorizedWhenInUse:
            // Request upgrade to Always. Do NOT call startTracking() here — background
            // location updates require Always permission, which isn't granted yet at this
            // point. startTracking() is called from locationManagerDidChangeAuthorization
            // once the user responds to the upgrade prompt.
            diagnostics.recordLifecycle("permission_upgrade_request", detail: "always")
            manager.requestAlwaysAuthorization()
        #endif
        default:
            isPermissionDenied = true
            diagnostics.recordLifecycle("permission_unavailable", detail: "\(manager.authorizationStatus.rawValue)")
        }
    }

    private func startTracking() {
        guard !isStudyTrackingDisabled else { return }
        if sessionStartedAt == nil { sessionStartedAt = Date() }
        diagnostics.recordLifecycle("tracking_start_or_rearm", detail: "legacy")
        manager.allowsBackgroundLocationUpdates = true
        manager.startMonitoringSignificantLocationChanges()
        manager.startUpdatingLocation()
    }

    /// Re-arms tracking when the app returns to the foreground. This is a safety net for
    /// cases where location updates silently stopped while backgrounded (e.g. a transient
    /// `didFailWithError`) without an authorization change to trigger a restart. Does
    /// nothing beyond re-asserting existing "Always" tracking — never requests permission.
    func restartIfAuthorized() {
        guard !isStudyTrackingDisabled else { return }
        guard manager.authorizationStatus == .authorizedAlways else { return }
        diagnostics.recordLifecycle("foreground_rearm", detail: "legacy")
        startTracking()
    }

    // MARK: - CLLocationManagerDelegate
    // Delegate methods are called by the system from any thread, so they must be
    // `nonisolated`. They dispatch back to the main actor to mutate state.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Read from self.manager (which may be a mock in tests) so the status
            // reflects the injected manager, not the CLLocationManager delegate argument.
            let status = self.manager.authorizationStatus
            self.authorizationStatus = status
            self.diagnostics.recordLifecycle("authorization_change", detail: "\(status.rawValue)")
            guard !self.isStudyTrackingDisabled else {
                self.isPermissionDenied = status == .denied || status == .restricted
                self.stopStudyConsumers()
                return
            }
            switch status {
            case .authorizedAlways:
                self.isPermissionDenied = false
                self.startTracking()
            #if os(iOS)
            case .authorizedWhenInUse:
                // Foreground-only permission: start updates for now, but do not set
                // allowsBackgroundLocationUpdates (requires Always auth).
                self.isPermissionDenied = false
                if self.sessionStartedAt == nil { self.sessionStartedAt = Date() }
                self.manager.startUpdatingLocation()
                self.manager.startMonitoringSignificantLocationChanges()
                // Request upgrade to Always so iOS shows the "Change to Always Allow?" prompt.
                self.manager.requestAlwaysAuthorization()
            #endif
            case .denied, .restricted:
                self.isPermissionDenied = true
                self.sessionStartedAt = nil
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let receivedAt = Date()
        let epoch = callbackEpoch.withLock { $0 }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard !self.isStudyTrackingDisabled,
                  epoch == self.callbackEpoch.withLock({ $0 }) else {
                self.diagnostics.recordLifecycle("study_callback_suppressed", detail: "off_or_previous_arm")
                return
            }
            if let start = self.studyResumeStartedAt,
               let last = locations.last, last.timestamp < start {
                self.diagnostics.recordLifecycle("study_callback_suppressed", detail: "before_resume")
                return
            }
            self.diagnostics.recordBatch(locations, receivedAt: receivedAt,
                                         sessionStartedAt: self.sessionStartedAt)
            guard let location = locations.last else { return }
            self.currentLocation = location
            self.isPaused = false
            self.onLocationUpdate?(location)
        }
    }

    nonisolated func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard self?.isStudyTrackingDisabled == false else { return }
            self?.isPaused = true
            self?.diagnostics.recordLifecycle("location_paused", detail: nil)
        }
    }

    nonisolated func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard self?.isStudyTrackingDisabled == false else { return }
            self?.isPaused = false
            self?.diagnostics.recordLifecycle("location_resumed", detail: nil)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationService: \(error.localizedDescription)")
        Task { @MainActor [weak self] in
            let nsError = error as NSError
            self?.diagnostics.recordLifecycle(
                "location_error", detail: "\(nsError.domain):\(nsError.code)"
            )
        }
    }
}
