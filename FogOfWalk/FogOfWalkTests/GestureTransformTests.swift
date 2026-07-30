import XCTest
import MapKit
import CoreData
import CoreLocation
@testable import FogOfWalk

/// Tests for Coordinator.gestureTransform — the pure-math function that converts
/// a (referenceRegion → currentRegion) delta into a CATransform3D for the overlay
/// layers. No MKMapView is needed because the reference-center screen point is
/// passed in directly.
final class GestureTransformTests: XCTestCase {

    let viewCenter = CGPoint(x: 200, y: 200)
    let baseSpan   = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)

    // MARK: - Helpers

    /// Applies t to a point, treating the CATransform3D as a 2-D affine.
    func apply(_ t: CATransform3D, to point: CGPoint) -> CGPoint {
        // CATransform3D: m11,m12,m21,m22 are the 2-D linear part; m41,m42 are tx,ty.
        let x = Double(point.x) * t.m11 + Double(point.y) * t.m21 + t.m41
        let y = Double(point.x) * t.m12 + Double(point.y) * t.m22 + t.m42
        return CGPoint(x: x, y: y)
    }

    // MARK: - Pure pan (same span, shifted center)

    func testPurePanProducesTranslationOnly() {
        // Reference center was at viewCenter. Now the reference center appears 30 pts
        // to the right and 20 pts down on screen (map panned left-up).
        let refCenterNow = CGPoint(x: viewCenter.x + 30, y: viewCenter.y + 20)

        let t = MapContainerView.Coordinator.gestureTransform(
            referenceCenterScreen: refCenterNow,
            viewCenter: viewCenter,
            referenceSpan: baseSpan,
            currentSpan: baseSpan   // same span → scale = 1
        )

        // Scale should be 1×1.
        XCTAssertEqual(t.m11, 1.0, accuracy: 1e-6, "No-zoom: x scale must be 1")
        XCTAssertEqual(t.m22, 1.0, accuracy: 1e-6, "No-zoom: y scale must be 1")

        // Translation should match the shift.
        XCTAssertEqual(t.m41, 30.0, accuracy: 1e-6, "tx should equal the x shift")
        XCTAssertEqual(t.m42, 20.0, accuracy: 1e-6, "ty should equal the y shift")
    }

    func testZeroPanProducesIdentity() {
        // Reference center hasn't moved — should produce identity.
        let t = MapContainerView.Coordinator.gestureTransform(
            referenceCenterScreen: viewCenter,  // same as viewCenter
            viewCenter: viewCenter,
            referenceSpan: baseSpan,
            currentSpan: baseSpan
        )

        XCTAssertEqual(t.m11, 1.0, accuracy: 1e-6)
        XCTAssertEqual(t.m22, 1.0, accuracy: 1e-6)
        XCTAssertEqual(t.m41, 0.0, accuracy: 1e-6)
        XCTAssertEqual(t.m42, 0.0, accuracy: 1e-6)
    }

    // MARK: - Pure zoom (same center, different span)

    func testZoomInProducesScaleGreaterThanOne() {
        // Zooming in halves the span → scale should be 2×.
        let zoomedSpan = MKCoordinateSpan(
            latitudeDelta:  baseSpan.latitudeDelta  / 2,
            longitudeDelta: baseSpan.longitudeDelta / 2
        )

        let t = MapContainerView.Coordinator.gestureTransform(
            referenceCenterScreen: viewCenter,  // no pan
            viewCenter: viewCenter,
            referenceSpan: baseSpan,
            currentSpan: zoomedSpan
        )

        XCTAssertEqual(t.m11, 2.0, accuracy: 1e-6, "Zoom-in 2×: x scale must be 2")
        XCTAssertEqual(t.m22, 2.0, accuracy: 1e-6, "Zoom-in 2×: y scale must be 2")
        XCTAssertEqual(t.m41, 0.0, accuracy: 1e-6, "No pan: tx must be 0")
        XCTAssertEqual(t.m42, 0.0, accuracy: 1e-6, "No pan: ty must be 0")
    }

    func testZoomOutProducesScaleLessThanOne() {
        // Zooming out doubles the span → scale should be 0.5×.
        let zoomedSpan = MKCoordinateSpan(
            latitudeDelta:  baseSpan.latitudeDelta  * 2,
            longitudeDelta: baseSpan.longitudeDelta * 2
        )

        let t = MapContainerView.Coordinator.gestureTransform(
            referenceCenterScreen: viewCenter,
            viewCenter: viewCenter,
            referenceSpan: baseSpan,
            currentSpan: zoomedSpan
        )

        XCTAssertEqual(t.m11, 0.5, accuracy: 1e-6, "Zoom-out 0.5×: x scale must be 0.5")
        XCTAssertEqual(t.m22, 0.5, accuracy: 1e-6, "Zoom-out 0.5×: y scale must be 0.5")
    }

    // MARK: - Combined pan + zoom

    func testCombinedPanAndZoom() {
        // Pan by (50, -30) and zoom in 2×.
        let refCenterNow = CGPoint(x: viewCenter.x + 50, y: viewCenter.y - 30)
        let zoomedSpan = MKCoordinateSpan(
            latitudeDelta:  baseSpan.latitudeDelta  / 2,
            longitudeDelta: baseSpan.longitudeDelta / 2
        )

        let t = MapContainerView.Coordinator.gestureTransform(
            referenceCenterScreen: refCenterNow,
            viewCenter: viewCenter,
            referenceSpan: baseSpan,
            currentSpan: zoomedSpan
        )

        XCTAssertEqual(t.m11, 2.0, accuracy: 1e-6, "Combined: x scale must be 2")
        XCTAssertEqual(t.m22, 2.0, accuracy: 1e-6, "Combined: y scale must be 2")
        XCTAssertEqual(t.m41, 50.0,  accuracy: 1e-6, "Combined: tx must be 50")
        XCTAssertEqual(t.m42, -30.0, accuracy: 1e-6, "Combined: ty must be -30")
    }
}

// MARK: - refreshLandmarks zoom gating

/// `Coordinator.refreshLandmarks` decides whether landmark pins are drawn at all. The
/// `mapView` argument is unused by its body, so the decision is testable without driving a
/// real pinch gesture.
///
/// Tests are `async` + `await MainActor.run { }` rather than a `@MainActor` class with sync
/// tests, because they construct `@MainActor @Observable` stores — see the note in
/// `LandmarkStoreTests`. The sync form crashes in the Swift runtime when those stores
/// deallocate outside a Task context.
final class RefreshLandmarksZoomTests: XCTestCase {

    var overlayView: LandmarkOverlayView!

    @MainActor
    func makeCoordinator() -> (MapContainerView.Coordinator, LandmarkStore) {
        let exploration = ExplorationStore()
        let container   = NSPersistentContainer(name: "FogOfWalk")
        let desc        = NSPersistentStoreDescription()
        desc.type       = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        container.loadPersistentStores { _, _ in }
        let landmarkStore = LandmarkStore(container: container)

        let coordinator = MapContainerView.Coordinator(
            store: exploration,
            gridSettings: GridSettings(),
            landmarkStore: landmarkStore,
            searchService: LandmarkSearchService()
        )
        // `landmarkOverlayView` is weak — the test must hold the strong reference.
        overlayView = LandmarkOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        coordinator.landmarkOverlayView = overlayView
        return (coordinator, landmarkStore)
    }

    override func tearDown() {
        overlayView = nil
        super.tearDown()
    }

    func region(span: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
    }

    func testWalkingZoomPopulatesPins() async {
        await MainActor.run {
            let (coordinator, store) = makeCoordinator()
            store.addLandmarks([WikidataLandmark(id: "Q1", name: "Museum", description: nil,
                                                lat: 40.7128, lon: -74.0060,
                                                category: "museum", imageURL: nil)],
                               visitedCells: [])
            let mapView = MKMapView()

            coordinator.refreshLandmarks(in: region(span: 0.01), mapView: mapView)
            XCTAssertEqual(overlayView.pins.count, 1)
        }
    }

    func testWideZoomClearsPins() async {
        // Stale pins from the previous region must stop drawing, not linger at their old
        // geographic positions while the user is looking at a whole continent.
        await MainActor.run {
            let (coordinator, store) = makeCoordinator()
            store.addLandmarks([WikidataLandmark(id: "Q1", name: "Museum", description: nil,
                                                lat: 40.7128, lon: -74.0060,
                                                category: "museum", imageURL: nil)],
                               visitedCells: [])
            let mapView = MKMapView()

            coordinator.refreshLandmarks(in: region(span: 0.01), mapView: mapView)
            XCTAssertEqual(overlayView.pins.count, 1,
                           "Precondition: pins populated at walking zoom")

            coordinator.refreshLandmarks(in: region(span: 30), mapView: mapView)
            XCTAssertEqual(overlayView.pins.count, 0, "World zoom must clear the pin array")

            // And zooming back in must repopulate — the clear must not be sticky.
            coordinator.refreshLandmarks(in: region(span: 0.01), mapView: mapView)
            XCTAssertEqual(overlayView.pins.count, 1, "Zooming back in must restore pins")
        }
    }
}
