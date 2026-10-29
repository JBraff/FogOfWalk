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
            controller.receive(trueHeading: 90, magneticHeading: 80, accuracy: 5, timestamp: Date())
            XCTAssertEqual(controller.heading, 90)

            controller.update(enabled: false, active: true, visible: true) // Study OFF/live source
            XCTAssertEqual(manager.stops, 1)
            XCTAssertNil(controller.heading)
            controller.receive(trueHeading: 180, magneticHeading: 170, accuracy: 5, timestamp: Date())
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
            let staleDate = Date().addingTimeInterval(-10)
            controller.update(enabled: true, active: true, visible: true)
            controller.receive(trueHeading: -1, magneticHeading: 270, accuracy: 5, timestamp: Date())
            XCTAssertEqual(controller.heading, 270)
            controller.receive(trueHeading: 90, magneticHeading: 80, accuracy: -1, timestamp: Date())
            XCTAssertNil(controller.heading)
            controller.receive(trueHeading: .nan, magneticHeading: .nan, accuracy: 5, timestamp: Date())
            XCTAssertNil(controller.heading)
            controller.update(enabled: false, active: true, visible: true)
            controller.update(enabled: true, active: true, visible: true)
            controller.receive(trueHeading: 90, magneticHeading: 80, accuracy: 5, timestamp: staleDate)
            XCTAssertNil(controller.heading)
            controller.update(enabled: false, active: true, visible: true)
        }
    }

    func testPointerRotatesRelativeToMapWithoutTurningMap() async {
        await MainActor.run {
            let map = MKMapView()
            let marker = HeadingUserLocationView(annotation: map.userLocation, reuseIdentifier: nil)
            let originalHeading = map.camera.heading
            for heading in [0.0, 90, 180, 270] {
                marker.setHeading(heading, mapHeading: map.camera.heading)
                XCTAssertEqual(marker.displayedAngle ?? .nan, CGFloat(heading * .pi / 180), accuracy: 0.001)
                XCTAssertEqual(map.camera.heading, originalHeading)
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
    private(set) var starts = 0
    private(set) var stops = 0
    override func startUpdatingHeading() { starts += 1 }
    override func stopUpdatingHeading() { stops += 1 }
}
