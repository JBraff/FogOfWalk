import XCTest
import CoreLocation
@testable import FogOfWalk

// MARK: - MockLocationManager

final class MockLocationManager: LocationManagerProtocol, @unchecked Sendable {
    var delegate: CLLocationManagerDelegate?
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var distanceFilter: CLLocationDistance = kCLDistanceFilterNone
    var pausesLocationUpdatesAutomatically: Bool = true
    var activityType: CLActivityType = .other
    var allowsBackgroundLocationUpdates: Bool = false
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private(set) var didCallRequestAlwaysAuthorization = false
    private(set) var didCallStartUpdatingLocation = false
    private(set) var didCallStopUpdatingLocation = false
    private(set) var didCallStartMonitoringSignificantLocationChanges = false
    private(set) var didCallStopMonitoringSignificantLocationChanges = false
    private(set) var didCallEnableBackgroundLocationIndicator = false

    func requestAlwaysAuthorization() { didCallRequestAlwaysAuthorization = true }
    func startUpdatingLocation()      { didCallStartUpdatingLocation = true }
    func stopUpdatingLocation()       { didCallStopUpdatingLocation = true }
    func startMonitoringSignificantLocationChanges() { didCallStartMonitoringSignificantLocationChanges = true }
    func stopMonitoringSignificantLocationChanges()  { didCallStopMonitoringSignificantLocationChanges = true }
    func enableBackgroundLocationIndicator()         { didCallEnableBackgroundLocationIndicator = true }
}

// MARK: - Tests

final class LocationServiceTests: XCTestCase {

    // MARK: Initialization

    func testInitConfiguresAutoPauseDisabled() async {
        await MainActor.run {
            let mock = MockLocationManager()
            _ = LocationService(manager: mock)
            XCTAssertFalse(mock.pausesLocationUpdatesAutomatically,
                           "Auto-pause must be disabled so iOS doesn't silently stop background updates")
        }
    }

    func testInitEnablesBackgroundLocationIndicator() async {
        await MainActor.run {
            let mock = MockLocationManager()
            _ = LocationService(manager: mock)
            XCTAssertTrue(mock.didCallEnableBackgroundLocationIndicator,
                          "Background indicator keeps iOS from aggressively suspending the location session")
        }
    }

    func testInitSetsDistanceFilterAndAccuracy() async {
        await MainActor.run {
            let mock = MockLocationManager()
            _ = LocationService(manager: mock)
            XCTAssertEqual(mock.distanceFilter, 15)
            XCTAssertEqual(mock.desiredAccuracy, kCLLocationAccuracyNearestTenMeters)
        }
    }

    func testInitSetsFitnessActivityType() async {
        await MainActor.run {
            let mock = MockLocationManager()
            _ = LocationService(manager: mock)
            XCTAssertEqual(mock.activityType, .fitness)
        }
    }

    // MARK: requestPermissionAndStart — .notDetermined

    func testRequestPermissionRequestsAlwaysAuthWhenNotDetermined() async {
        await MainActor.run {
            let mock = MockLocationManager()
            mock.authorizationStatus = .notDetermined
            let service = LocationService(manager: mock)
            service.requestPermissionAndStart()
            XCTAssertTrue(mock.didCallRequestAlwaysAuthorization)
            XCTAssertFalse(mock.didCallStartUpdatingLocation,
                           "Should not start updates until authorization is granted")
        }
    }

    // MARK: requestPermissionAndStart — .authorizedAlways

    func testRequestPermissionStartsTrackingWhenAlwaysAuthorized() async {
        await MainActor.run {
            let mock = MockLocationManager()
            mock.authorizationStatus = .authorizedAlways
            let service = LocationService(manager: mock)
            service.requestPermissionAndStart()
            XCTAssertTrue(mock.allowsBackgroundLocationUpdates)
            XCTAssertTrue(mock.didCallStartMonitoringSignificantLocationChanges)
            XCTAssertTrue(mock.didCallStartUpdatingLocation)
        }
    }

    func testStartTrackingRegistersSignificantLocationChanges() async {
        await MainActor.run {
            let mock = MockLocationManager()
            mock.authorizationStatus = .authorizedAlways
            let service = LocationService(manager: mock)
            service.requestPermissionAndStart()
            XCTAssertTrue(mock.didCallStartMonitoringSignificantLocationChanges,
                          "Significant location monitoring allows iOS to relaunch the app after termination")
        }
    }

    // MARK: Delegate — isPaused

    func testIsPausedBecomesTrue() async {
        let expectation = XCTestExpectation(description: "isPaused becomes true")
        var service: LocationService?

        await MainActor.run {
            let mock = MockLocationManager()
            service = LocationService(manager: mock)
            service?.locationManagerDidPauseLocationUpdates(CLLocationManager())
        }

        try? await Task.sleep(for: .milliseconds(100))

        await MainActor.run {
            XCTAssertTrue(service?.isPaused == true)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2)
    }

    func testIsPausedClearsOnResume() async {
        let expectation = XCTestExpectation(description: "isPaused becomes false after resume")
        var service: LocationService?

        await MainActor.run {
            let mock = MockLocationManager()
            service = LocationService(manager: mock)
            service?.locationManagerDidPauseLocationUpdates(CLLocationManager())
        }

        try? await Task.sleep(for: .milliseconds(100))

        await MainActor.run {
            service?.locationManagerDidResumeLocationUpdates(CLLocationManager())
        }

        try? await Task.sleep(for: .milliseconds(100))

        await MainActor.run {
            XCTAssertFalse(service?.isPaused == true)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2)
    }

    // MARK: Delegate — onLocationUpdate

    func testLocationUpdateCallsCallback() async {
        let expectation = XCTestExpectation(description: "onLocationUpdate fires")

        await MainActor.run {
            let mock = MockLocationManager()
            let service = LocationService(manager: mock)
            let target = CLLocation(latitude: 37.7749, longitude: -122.4194)
            service.onLocationUpdate = { location in
                XCTAssertEqual(location.coordinate.latitude,  target.coordinate.latitude,  accuracy: 0.0001)
                XCTAssertEqual(location.coordinate.longitude, target.coordinate.longitude, accuracy: 0.0001)
                expectation.fulfill()
            }
            service.locationManager(CLLocationManager(), didUpdateLocations: [target])
        }

        await fulfillment(of: [expectation], timeout: 2)
    }
}
