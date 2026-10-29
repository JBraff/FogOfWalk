import XCTest
import MapKit
@testable import FogOfWalk

final class MapHeadingTests: XCTestCase {
    func testHeadingRunsOnlyForActiveVisibleMapWithLocationEnabled() async {
        await MainActor.run {
            let manager = HeadingTestManager()
            let controller = MapHeadingController(manager: manager, headingAvailable: true)
            controller.update(enabled: true, active: true, visible: true)
            controller.update(enabled: true, active: true, visible: true)
            XCTAssertEqual(manager.starts, 1)
            controller.receive(trueHeading: 90, magneticHeading: 80, accuracy: 5, sessionID: controller.sessionID)
            XCTAssertEqual(controller.heading, 90)

            controller.update(enabled: false, active: true, visible: true) // Study OFF/live source
            XCTAssertEqual(manager.stops, 1)
            XCTAssertNil(controller.heading)
            controller.receive(trueHeading: 180, magneticHeading: 170, accuracy: 5, sessionID: controller.sessionID)
            XCTAssertNil(controller.heading, "Late callbacks cannot restore the Study pointer")
            controller.update(enabled: true, active: false, visible: true)
            controller.update(enabled: true, active: true, visible: false)
            XCTAssertEqual(manager.starts, 1)

            controller.update(enabled: true, active: true, visible: true)
            controller.update(enabled: true, active: false, visible: true) // Background
            XCTAssertEqual(manager.starts, 2)
            XCTAssertEqual(manager.stops, 2)
            controller.update(enabled: true, active: true, visible: true)
            controller.update(enabled: true, active: true, visible: false) // Map removed
            XCTAssertEqual(manager.starts, 3)
            XCTAssertEqual(manager.stops, 3)
        }
    }

    func testHeadingNeedsHardwareAndPermission() async {
        await MainActor.run {
            for status in [CLAuthorizationStatus.denied, .restricted, .notDetermined] {
                let manager = HeadingTestManager()
                manager.status = status
                let controller = MapHeadingController(manager: manager, headingAvailable: true)
                controller.update(enabled: true, active: true, visible: true)
                XCTAssertEqual(manager.starts, 0)
            }
            let manager = HeadingTestManager()
            let controller = MapHeadingController(manager: manager, headingAvailable: false)
            controller.update(enabled: true, active: true, visible: true)
            XCTAssertEqual(manager.starts, 0)
        }
    }

    func testHeadingFallbackInvalidSamplesAndPreviousSessionCallbacks() async {
        await MainActor.run {
            let manager = HeadingTestManager()
            let controller = MapHeadingController(manager: manager, headingAvailable: true)
            let previousSession: UUID?
            controller.update(enabled: true, active: true, visible: true)
            controller.receive(trueHeading: -1, magneticHeading: 270, accuracy: 5, sessionID: controller.sessionID)
            XCTAssertEqual(controller.heading, 270)
            controller.receive(trueHeading: 90, magneticHeading: 80, accuracy: -1, sessionID: controller.sessionID)
            XCTAssertNil(controller.heading)
            controller.receive(trueHeading: .nan, magneticHeading: .nan, accuracy: 5, sessionID: controller.sessionID)
            XCTAssertNil(controller.heading)
            previousSession = controller.sessionID
            controller.update(enabled: false, active: true, visible: true)
            controller.update(enabled: true, active: true, visible: true)
            controller.receive(trueHeading: 90, magneticHeading: 80, accuracy: 5, sessionID: previousSession)
            XCTAssertNil(controller.heading)
            controller.update(enabled: false, active: true, visible: true)
        }
    }

    func testCachedFirstReadingIsAcceptedButQueuedPreviousSessionCallbackIsRejected() async {
        let received = expectation(description: "New session cached heading")
        let cleanup: @MainActor () -> Void = await MainActor.run {
            let manager = HeadingTestManager()
            let controller = MapHeadingController(manager: manager, headingAvailable: true)
            controller.update(enabled: true, active: true, visible: true)
            // This delegate call queues its main-actor work with the old session ID.
            controller.locationManager(manager, didUpdateHeading: CachedTestHeading(value: 90))
            controller.update(enabled: false, active: true, visible: true)
            controller.update(enabled: true, active: true, visible: true)
            controller.onChange = {
                guard let heading = controller.heading else { return }
                XCTAssertEqual(heading, 180, "Queued callbacks must not cross a stop/restart")
                received.fulfill()
            }
            // A still phone may deliver a cached timestamp before the new start time.
            controller.locationManager(manager, didUpdateHeading: CachedTestHeading(value: 180))
            return {
                controller.onChange = nil
                controller.update(enabled: false, active: true, visible: true)
            }
        }
        await fulfillment(of: [received], timeout: 2)
        await cleanup()
    }

    func testSceneGeometryNotificationUpdatesOrientationWithoutLayout() async throws {
        // Hosted tests can start before SwiftUI connects its first scene. Yield to app
        // launch instead of force-unwrapping a scene that does not exist yet.
        for _ in 0..<50 {
            if await MainActor.run(body: { !UIApplication.shared.connectedScenes.isEmpty }) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let updated = expectation(description: "Geometry observation updates compass orientation")
        let cleanup: @MainActor () -> Void = try await MainActor.run {
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let manager = HeadingTestManager()
            let controller = MapHeadingController(manager: manager, headingAvailable: false)
            let map = HeadingMapView(frame: .zero, headingController: controller)
            let window = UIWindow(windowScene: scene)
            let root = UIViewController()
            window.rootViewController = root
            window.isHidden = false
            root.view.addSubview(map)
            XCTAssertTrue(map.window === window, "The map must be attached before observing scene geometry")
            manager.headingOrientation = .unknown
            manager.onOrientationChange = {
                XCTAssertNotEqual(manager.headingOrientation, .unknown)
                updated.fulfill()
            }
            // Emit only the observed geometry event: no bounds change or layout pass.
            scene.willChangeValue(forKey: "effectiveGeometry")
            scene.didChangeValue(forKey: "effectiveGeometry")
            return {
                manager.onOrientationChange = nil
                map.removeFromSuperview()
                window.isHidden = true
                window.rootViewController = nil
            }
        }
        await fulfillment(of: [updated], timeout: 2)
        await cleanup()
    }

    func testPointerAngleAccountsForMapHeading() async {
        await MainActor.run {
            let map = MKMapView()
            let marker = HeadingUserLocationView(annotation: map.userLocation, reuseIdentifier: nil)
            for heading in [0.0, 90, 180, 270] {
                marker.setHeading(heading, mapHeading: 0)
                XCTAssertEqual(marker.displayedAngle ?? .nan, CGFloat(heading * .pi / 180), accuracy: 0.001)
            }
            marker.setHeading(90, mapHeading: 45) // User manually rotates map.
            XCTAssertEqual(marker.displayedAngle ?? .nan, .pi / 4, accuracy: 0.001)
            marker.setHeading(nil, mapHeading: 0)
            XCTAssertNil(marker.displayedAngle)
        }
    }

    func testOrientationUsesScreenOrientation() async {
        await MainActor.run {
            let manager = HeadingTestManager()
            let controller = MapHeadingController(manager: manager, headingAvailable: true)
            controller.setOrientation(.landscapeLeft)
            XCTAssertEqual(manager.headingOrientation, .landscapeRight)
            controller.setOrientation(.landscapeRight)
            XCTAssertEqual(manager.headingOrientation, .landscapeLeft)
            controller.setOrientation(.portrait)
            XCTAssertEqual(manager.headingOrientation, .portrait)
        }
    }
}

private final class HeadingTestManager: CLLocationManager {
    var status: CLAuthorizationStatus = .authorizedWhenInUse
    override var authorizationStatus: CLAuthorizationStatus { status }
    var onOrientationChange: (() -> Void)?
    override var headingOrientation: CLDeviceOrientation {
        didSet { onOrientationChange?() }
    }
    private(set) var starts = 0
    private(set) var stops = 0
    override func startUpdatingHeading() { starts += 1 }
    override func stopUpdatingHeading() { stops += 1 }
}

private final class CachedTestHeading: CLHeading {
    private let value: Double
    init(value: Double) { self.value = value; super.init() }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var trueHeading: CLLocationDirection { value }
    override var magneticHeading: CLLocationDirection { value }
    override var headingAccuracy: CLLocationDirection { 5 }
    override var timestamp: Date { Date().addingTimeInterval(-60) }
}
