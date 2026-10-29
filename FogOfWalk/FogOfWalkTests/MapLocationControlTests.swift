import XCTest
import MapKit
@testable import FogOfWalk

/// The map's tracking button and stats-sheet navigation. Study gating of the button is
/// covered with the rest of the Study map control in `StudyTrackingControlTests`.
///
/// Tests are `async` + `await MainActor.run { }` like the other MapKit tests.
final class MapLocationControlTests: XCTestCase {

    func testRepeatedRecenterTapsOnlyRequestFollowWithoutChangingCameraHeading() async {
        await MainActor.run {
            let mapView = TrackingModeRecordingMapView()
            mapView.showsUserLocation = true
            let button = MapContainerView.makeTrackingButton(for: mapView)
            let originalHeading = mapView.camera.heading

            for _ in 0..<3 {
                button.sendActions(for: .touchUpInside)
            }

            XCTAssertEqual(mapView.requestedTrackingModes, [.follow, .follow, .follow])
            XCTAssertEqual(mapView.camera.heading, originalHeading)
            XCTAssertEqual(button.accessibilityLabel, "Recenter on my location")
            mapView.setUserTrackingMode(.none, animated: false) // Panning leaves follow.
            button.sendActions(for: .touchUpInside)
            XCTAssertEqual(mapView.requestedTrackingModes.suffix(2), [.none, .follow])
        }
    }

    func testRecenterDoesNothingWhenMapLocationIsDisabled() async {
        await MainActor.run {
            let mapView = TrackingModeRecordingMapView()
            let button = MapContainerView.makeTrackingButton(for: mapView)
            button.sendActions(for: .touchUpInside)
            XCTAssertTrue(mapView.requestedTrackingModes.isEmpty)
        }
    }

    func testNormalAppShowsTrackingButton() async {
        await MainActor.run {
            let mapView = MKMapView()
            let button  = MapContainerView.makeTrackingButton(for: mapView)

            MapContainerView.applyLocationDisplay(to: mapView, trackingButton: button, enabled: true)

            XCTAssertFalse(button.isHidden)
            XCTAssertTrue(mapView.showsUserLocation)
        }
    }

    /// A stats-sheet jump must stay where it was sent rather than snap back to the user.
    func testNavigationLeavesFollowMode() async {
        await MainActor.run {
            let mapView = TrackingModeRecordingMapView()
            let target = MapNavigationTarget(
                center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))

            MapContainerView.navigate(mapView, to: target)

            // MapKit can decline follow modes in the simulator without an authorized fix, so
            // check the mode requested before the jump rather than starting from .follow.
            XCTAssertEqual(mapView.requestedTrackingModes, [.none])
            XCTAssertEqual(mapView.userTrackingMode, .none)
        }
    }
}

private final class TrackingModeRecordingMapView: MKMapView {
    private(set) var requestedTrackingModes: [MKUserTrackingMode] = []
    override func setUserTrackingMode(_ mode: MKUserTrackingMode, animated: Bool) {
        requestedTrackingModes.append(mode)
        super.setUserTrackingMode(mode, animated: animated)
    }
}
