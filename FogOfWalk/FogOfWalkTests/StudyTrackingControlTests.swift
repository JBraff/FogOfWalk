import XCTest
import CoreLocation
import MapKit
@testable import FogOfWalk

final class StudyTrackingControlTests: XCTestCase {
    func testNormalAppIgnoresPersistedAndRequestedControlChanges() async {
        await MainActor.run {
            let defaults = makeDefaults()
            defaults.set(true, forKey: LocationService.studyTrackingDisabledKey)
            let manager = ControlTestLocationManager(status: .authorizedAlways)
            let service = LocationService(manager: manager, isStudyApp: false, defaults: defaults)

            XCTAssertFalse(service.isStudyTrackingDisabled)
            XCTAssertFalse(service.setStudyTrackingDisabled(true))
            service.requestPermissionAndStart()

            XCTAssertFalse(service.isStudyTrackingDisabled)
            XCTAssertEqual(manager.standardStarts, 1)
            XCTAssertEqual(manager.significantStarts, 1)
            XCTAssertEqual(manager.standardStops, 0)
        }
    }

    func testPersistedOffSuppressesStartupAuthorizationAndForegroundRearm() async {
        var managers: [ControlTestLocationManager] = []
        var services: [LocationService] = []
        await MainActor.run {
            for status in [CLAuthorizationStatus.authorizedAlways, .authorizedWhenInUse] {
                let defaults = makeDefaults()
                defaults.set(true, forKey: LocationService.studyTrackingDisabledKey)
                let manager = ControlTestLocationManager(status: status)
                let service = LocationService(manager: manager, isStudyApp: true, defaults: defaults)
                managers.append(manager)
                services.append(service)

                service.requestPermissionAndStart()
                service.locationManagerDidChangeAuthorization(CLLocationManager())
                service.restartIfAuthorized()

                XCTAssertTrue(service.isStudyTrackingDisabled)
                XCTAssertGreaterThanOrEqual(manager.standardStops, 1)
                XCTAssertGreaterThanOrEqual(manager.significantStops, 1)
            }
        }
        try? await Task.sleep(for: .milliseconds(30))
        await MainActor.run {
            XCTAssertEqual(services.count, 2)
            XCTAssertEqual(managers.map(\.standardStarts), [0, 0])
            XCTAssertEqual(managers.map(\.significantStarts), [0, 0])
        }
    }

    func testTurningOffStopsBothConsumersAndSuppressesLocationCallbacks() async {
        let (forwarded, diagnostics) = await MainActor.run {
            (MainActorForwardCounter(), ControlTestDiagnostics())
        }
        let manager = ControlTestLocationManager(status: .authorizedAlways)
        let service = await MainActor.run { () -> LocationService in
            let service = LocationService(
                manager: manager, diagnostics: diagnostics, isStudyApp: true,
                defaults: makeDefaults()
            )
            service.requestPermissionAndStart()
            service.onLocationUpdate = { _ in forwarded.count += 1 }

            XCTAssertTrue(service.setStudyTrackingDisabled(true))
            service.locationManager(CLLocationManager(), didUpdateLocations: [sample()])

            XCTAssertEqual(manager.standardStops, 1)
            XCTAssertEqual(manager.significantStops, 1)
            XCTAssertFalse(manager.allowsBackgroundLocationUpdates)
            return service
        }
        try? await Task.sleep(for: .milliseconds(30))
        await MainActor.run {
            XCTAssertTrue(service.isStudyTrackingDisabled)
            XCTAssertEqual(forwarded.count, 0)
            XCTAssertEqual(diagnostics.batchCount, 0)
        }
    }

    func testCallbackQueuedBeforeModeSwitchIsDiscardedAfterSwitch() async {
        let forwarded = await MainActor.run { MainActorForwardCounter() }
        let service = await MainActor.run { () -> LocationService in
            let service = LocationService(
                manager: ControlTestLocationManager(status: .authorizedAlways),
                isStudyApp: true, defaults: makeDefaults()
            )
            service.onLocationUpdate = { _ in forwarded.count += 1 }
            service.locationManager(CLLocationManager(), didUpdateLocations: [sample()])
            XCTAssertTrue(service.setStudyTrackingDisabled(true))
            XCTAssertTrue(service.setStudyTrackingDisabled(false))
            return service
        }
        try? await Task.sleep(for: .milliseconds(30))
        await MainActor.run {
            XCTAssertFalse(service.isStudyTrackingDisabled)
            XCTAssertEqual(forwarded.count, 0)
            service.locationManager(CLLocationManager(), didUpdateLocations: [sample(time: Date().addingTimeInterval(5))])
        }
        try? await Task.sleep(for: .milliseconds(30))
        await MainActor.run {
            XCTAssertFalse(service.isStudyTrackingDisabled)
            XCTAssertEqual(forwarded.count, 1)
        }
    }

    func testCachedPreResumeLocationIsDiscarded() async {
        let forwarded = await MainActor.run { MainActorForwardCounter() }
        let service = await MainActor.run { () -> LocationService in
            let manager = ControlTestLocationManager(status: .authorizedAlways)
            let service = LocationService(manager: manager, isStudyApp: true, defaults: makeDefaults())
            service.setStudyTrackingDisabled(true)
            service.setStudyTrackingDisabled(false)
            service.onLocationUpdate = { _ in forwarded.count += 1 }
            service.locationManager(
                CLLocationManager(), didUpdateLocations: [sample(time: Date().addingTimeInterval(-10))]
            )
            return service
        }
        try? await Task.sleep(for: .milliseconds(30))
        await MainActor.run {
            XCTAssertFalse(service.isStudyTrackingDisabled)
            XCTAssertEqual(forwarded.count, 0)
            service.locationManager(
                CLLocationManager(), didUpdateLocations: [sample(time: Date().addingTimeInterval(5))]
            )
        }
        try? await Task.sleep(for: .milliseconds(30))
        await MainActor.run {
            XCTAssertFalse(service.isStudyTrackingDisabled)
            XCTAssertEqual(forwarded.count, 1)
        }
    }

    func testMapControlChangesActualMapLocationDisplayAndTrackingMode() async {
        await MainActor.run {
            let defaults = makeDefaults()
            defaults.set(true, forKey: LocationService.studyTrackingDisabledKey)
            let service = LocationService(
                manager: ControlTestLocationManager(status: .authorizedAlways),
                isStudyApp: true, defaults: defaults
            )
            let map = ControlTestMapView()
            let button = MapContainerView.makeTrackingButton(for: map)
            MapContainerView.applyLocationDisplay(to: map, trackingButton: button, enabled: true)
            service.installStudyMapControl { enabled in
                MapContainerView.applyLocationDisplay(to: map, trackingButton: button, enabled: enabled)
            }
            XCTAssertFalse(map.showsUserLocation)
            XCTAssertEqual(map.userTrackingMode, .none)
            XCTAssertTrue(button.isHidden, "Tracking OFF leaves the button nothing to follow")

            XCTAssertTrue(service.setStudyTrackingDisabled(false))
            XCTAssertTrue(map.showsUserLocation)
            XCTAssertFalse(button.isHidden)
            // MapKit can decline .follow when the simulator has no authorized fix.
            // Verify our request, while checking the real OFF flags below.
            XCTAssertEqual(map.lastRequestedTrackingMode, .follow)

            XCTAssertTrue(service.setStudyTrackingDisabled(true))
            XCTAssertFalse(map.showsUserLocation)
            XCTAssertEqual(map.userTrackingMode, .none)
            XCTAssertTrue(button.isHidden)
        }
    }

    func testCaptureRejectsModeChangesAndLogsModeAtStartAndRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fog-study-control-\(UUID().uuidString)")
        let defaults = makeDefaults()
        defer { try? FileManager.default.removeItem(at: directory) }

        try await MainActor.run {
            let diagnostics = LocationStudyDiagnostics(
                isStudyApp: true, directoryURL: directory, defaults: defaults
            )
            let service = LocationService(
                manager: ControlTestLocationManager(status: .authorizedAlways),
                diagnostics: diagnostics, isStudyApp: true, defaults: defaults
            )
            try diagnostics.startCapture()
            XCTAssertFalse(service.setStudyTrackingDisabled(true))
            XCTAssertFalse(service.isStudyTrackingDisabled)
            diagnostics.stopCapture()

            let filename = diagnostics.currentFileURL!.lastPathComponent
            defaults.set(filename, forKey: "locationStudy.fileName")
            defaults.set(Date(), forKey: "locationStudy.startedAt")
            defaults.set(true, forKey: "locationStudy.active")
            defaults.set(true, forKey: LocationService.studyTrackingDisabledKey)
            let relaunched = LocationStudyDiagnostics(
                isStudyApp: true, directoryURL: directory, defaults: defaults
            )
            XCTAssertTrue(relaunched.isCapturing)
            relaunched.stopCapture()

            let data = try Data(contentsOf: diagnostics.currentFileURL!)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let events = try data.split(separator: 0x0A).map {
                try decoder.decode(LocationStudyDiagnostics.Event.self, from: Data($0))
            }
            XCTAssertTrue(events.contains { $0.kind == "capture_start" })
            XCTAssertTrue(events.contains { $0.kind == "study_tracking_state" && $0.detail == "on" })
            XCTAssertTrue(events.contains { $0.kind == "process_relaunch" })
            XCTAssertTrue(events.contains { $0.kind == "study_tracking_state" && $0.detail == "off" })
        }
    }

    func testTurningBackOnStartsOnlyWithAlwaysAuthorization() async {
        await MainActor.run {
            let alwaysManager = ControlTestLocationManager(status: .authorizedAlways)
            let always = LocationService(manager: alwaysManager, isStudyApp: true, defaults: makeDefaults())
            always.setStudyTrackingDisabled(true)
            XCTAssertTrue(always.setStudyTrackingDisabled(false))
            XCTAssertEqual(alwaysManager.standardStarts, 1)
            XCTAssertEqual(alwaysManager.significantStarts, 1)

            let deniedManager = ControlTestLocationManager(status: .denied)
            let denied = LocationService(manager: deniedManager, isStudyApp: true, defaults: makeDefaults())
            denied.setStudyTrackingDisabled(true)
            XCTAssertTrue(denied.setStudyTrackingDisabled(false))
            XCTAssertEqual(deniedManager.standardStarts, 0)
            XCTAssertEqual(deniedManager.significantStarts, 0)
        }
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "fog-study-control-\(UUID().uuidString)")!
    }

    private func sample(time: Date = Date()) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40, longitude: -74),
                   altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                   timestamp: time)
    }
}

@MainActor
private final class ControlTestMapView: MKMapView {
    private(set) var lastRequestedTrackingMode: MKUserTrackingMode?
    override var userTrackingMode: MKUserTrackingMode {
        get { super.userTrackingMode }
        set {
            lastRequestedTrackingMode = newValue
            super.userTrackingMode = newValue
        }
    }
}

@MainActor
private final class MainActorForwardCounter {
    var count = 0
}

@MainActor
private final class ControlTestDiagnostics: LocationDiagnosticRecording {
    var isCapturing = false
    private(set) var batchCount = 0
    func recordLifecycle(_ name: String, detail: String?) {}
    func recordBatch(_ locations: [CLLocation], receivedAt: Date, sessionStartedAt: Date?) {
        batchCount += 1
    }
    func recordDownstream(cell: CellID, isNew: Bool, discoveries: Int, dayRollover: Bool) {}
}

private final class ControlTestLocationManager: LocationManagerProtocol, @unchecked Sendable {
    var delegate: CLLocationManagerDelegate?
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var distanceFilter: CLLocationDistance = kCLDistanceFilterNone
    var pausesLocationUpdatesAutomatically = true
    var activityType: CLActivityType = .other
    var allowsBackgroundLocationUpdates = false
    var authorizationStatus: CLAuthorizationStatus
    private(set) var standardStarts = 0
    private(set) var standardStops = 0
    private(set) var significantStarts = 0
    private(set) var significantStops = 0

    init(status: CLAuthorizationStatus) { authorizationStatus = status }
    func requestAlwaysAuthorization() {}
    func startUpdatingLocation() { standardStarts += 1 }
    func stopUpdatingLocation() { standardStops += 1 }
    func startMonitoringSignificantLocationChanges() { significantStarts += 1 }
    func stopMonitoringSignificantLocationChanges() { significantStops += 1 }
    func enableBackgroundLocationIndicator() {}
}
