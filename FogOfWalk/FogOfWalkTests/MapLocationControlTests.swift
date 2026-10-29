import XCTest
import MapKit
import CoreData
@testable import FogOfWalk

/// The map's tracking button and stats-sheet navigation. Study gating of the button is
/// covered with the rest of the Study map control in `StudyTrackingControlTests`.
///
/// Tests are `async` + `await MainActor.run { }` like the other MapKit tests.
final class MapLocationControlTests: XCTestCase {

    func testRepeatedRecenterTapsOnlyRequestFollow() async {
        await MainActor.run {
            let mapView = TrackingModeRecordingMapView()
            mapView.showsUserLocation = true
            let button = MapContainerView.makeTrackingButton(for: mapView)

            for _ in 0..<3 {
                button.sendActions(for: .touchUpInside)
            }

            XCTAssertEqual(mapView.requestedTrackingModes, [.follow, .follow, .follow])
            XCTAssertEqual(button.accessibilityLabel, "Recenter on my location")
            mapView.setUserTrackingMode(.none, animated: false) // Panning leaves follow.
            button.sendActions(for: .touchUpInside)
            XCTAssertEqual(mapView.requestedTrackingModes.suffix(2), [.none, .follow])
        }
    }

    func testButtonTracksFollowChangesFromRecenterPanningAndStatsNavigation() async {
        await MainActor.run {
            let container = NSPersistentContainer(name: "FogOfWalk")
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
            container.loadPersistentStores { _, error in XCTAssertNil(error) }
            let coordinator = MapContainerView.Coordinator(
                store: ExplorationStore(container: container), gridSettings: GridSettings(),
                landmarkStore: LandmarkStore(container: container), searchService: LandmarkSearchService())
            let map = FollowStateMapView()
            map.showsUserLocation = true
            let button = MapContainerView.makeTrackingButton(for: map)
            coordinator.trackingButton = button
            map.delegate = coordinator

            @MainActor func assertButton(following: Bool) {
                XCTAssertEqual(button.image(for: .normal),
                               UIImage(systemName: following ? "location.fill" : "location"))
                XCTAssertEqual(button.accessibilityValue,
                               following ? "Following location" : "Not following location")
            }
            assertButton(following: false)
            button.sendActions(for: .touchUpInside)
            XCTAssertEqual(map.userTrackingMode, .follow)
            assertButton(following: true)
            map.setUserTrackingMode(.none, animated: false) // MapKit's pan transition.
            assertButton(following: false)
            button.sendActions(for: .touchUpInside)
            assertButton(following: true)
            MapContainerView.navigate(map, to: MapNavigationTarget(
                center: CLLocationCoordinate2D(latitude: 40, longitude: -74),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
            assertButton(following: false)
            map.delegate = nil
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

/// MapKit can decline follow without an authorized location in the simulator. Model its
/// tracking transition and delegate callback explicitly, without relying on a GPS fix.
private final class FollowStateMapView: MKMapView {
    private var mode: MKUserTrackingMode = .none
    override var userTrackingMode: MKUserTrackingMode {
        get { mode }
        set { setUserTrackingMode(newValue, animated: false) }
    }
    override func setUserTrackingMode(_ mode: MKUserTrackingMode, animated: Bool) {
        self.mode = mode
        delegate?.mapView?(self, didChange: mode, animated: animated)
    }
}
