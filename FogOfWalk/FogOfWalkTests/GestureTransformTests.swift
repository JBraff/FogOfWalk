import XCTest
import MapKit
import CoreData
import CoreLocation
@testable import FogOfWalk

/// Tests for Coordinator.gestureTransform — the pure-math function that converts where the
/// reference center and probe coordinates are on screen now into a CATransform3D for the pin
/// overlay. No MKMapView is needed because those screen points are passed in directly.
final class GestureTransformTests: XCTestCase {

    let viewCenter  = CGPoint(x: 200, y: 200)
    let probeOffset = CGVector(dx: 100, dy: 0)

    // MARK: - Helpers

    /// Applies t to a point relative to the layer's center (its anchor point), treating the
    /// CATransform3D as a 2-D affine, and returns the screen point.
    func apply(_ t: CATransform3D, toScreen point: CGPoint) -> CGPoint {
        // CATransform3D: m11,m12,m21,m22 are the 2-D linear part; m41,m42 are tx,ty.
        let x = Double(point.x - viewCenter.x)
        let y = Double(point.y - viewCenter.y)
        return CGPoint(x: x * t.m11 + y * t.m21 + t.m41 + viewCenter.x,
                       y: x * t.m12 + y * t.m22 + t.m42 + viewCenter.y)
    }

    /// The transform for a map whose reference center now appears at `center` and whose
    /// probe point now appears at `probe`.
    func transform(center: CGPoint, probe: CGPoint) -> CATransform3D {
        MapContainerView.Coordinator.gestureTransform(
            referenceCenterScreen: center,
            referenceProbeScreen: probe,
            viewCenter: viewCenter,
            probeOffset: probeOffset
        )
    }

    var referenceProbe: CGPoint {
        CGPoint(x: viewCenter.x + probeOffset.dx, y: viewCenter.y + probeOffset.dy)
    }

    func assertPoint(_ actual: CGPoint, _ expected: CGPoint, _ message: String,
                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 1e-6, message, file: file, line: line)
    }

    // MARK: - Pure pan (same scale, shifted center)

    func testPurePanProducesTranslationOnly() {
        // The reference center now appears 30 pts right and 20 pts down (map panned).
        let t = transform(center: CGPoint(x: 230, y: 220), probe: CGPoint(x: 330, y: 220))

        XCTAssertEqual(t.m11, 1.0, accuracy: 1e-6, "No zoom: x scale must be 1")
        XCTAssertEqual(t.m22, 1.0, accuracy: 1e-6, "No zoom: y scale must be 1")
        XCTAssertEqual(t.m12, 0.0, accuracy: 1e-6, "No rotation")
        XCTAssertEqual(t.m41, 30.0, accuracy: 1e-6, "tx should equal the x shift")
        XCTAssertEqual(t.m42, 20.0, accuracy: 1e-6, "ty should equal the y shift")
    }

    func testZeroPanProducesIdentity() {
        let t = transform(center: viewCenter, probe: referenceProbe)

        XCTAssertEqual(t.m11, 1.0, accuracy: 1e-6)
        XCTAssertEqual(t.m22, 1.0, accuracy: 1e-6)
        XCTAssertEqual(t.m12, 0.0, accuracy: 1e-6)
        XCTAssertEqual(t.m41, 0.0, accuracy: 1e-6)
        XCTAssertEqual(t.m42, 0.0, accuracy: 1e-6)
    }

    // MARK: - Pure zoom (same center, probe moved along its axis)

    func testZoomInProducesScaleGreaterThanOne() {
        let t = transform(center: viewCenter, probe: CGPoint(x: 400, y: 200))

        XCTAssertEqual(t.m11, 2.0, accuracy: 1e-6, "Zoom-in 2×: x scale must be 2")
        XCTAssertEqual(t.m22, 2.0, accuracy: 1e-6, "Zoom-in 2×: y scale must be 2")
        XCTAssertEqual(t.m41, 0.0, accuracy: 1e-6, "No pan: tx must be 0")
        XCTAssertEqual(t.m42, 0.0, accuracy: 1e-6, "No pan: ty must be 0")
    }

    func testZoomOutProducesScaleLessThanOne() {
        let t = transform(center: viewCenter, probe: CGPoint(x: 250, y: 200))

        XCTAssertEqual(t.m11, 0.5, accuracy: 1e-6, "Zoom-out 0.5×: x scale must be 0.5")
        XCTAssertEqual(t.m22, 0.5, accuracy: 1e-6, "Zoom-out 0.5×: y scale must be 0.5")
    }

    // MARK: - Combined pan + zoom

    func testCombinedPanAndZoom() {
        // Pan by (50, -30) and zoom in 2×.
        let t = transform(center: CGPoint(x: 250, y: 170), probe: CGPoint(x: 450, y: 170))

        XCTAssertEqual(t.m11, 2.0, accuracy: 1e-6, "Combined: x scale must be 2")
        XCTAssertEqual(t.m22, 2.0, accuracy: 1e-6, "Combined: y scale must be 2")
        XCTAssertEqual(t.m41, 50.0,  accuracy: 1e-6, "Combined: tx must be 50")
        XCTAssertEqual(t.m42, -30.0, accuracy: 1e-6, "Combined: ty must be -30")
    }

    // MARK: - Rotation

    /// Regression: the transform handled only pan and zoom, so pins drifted off their
    /// landmarks whenever the map rotated, including continuously in heading-up tracking.
    func testRotationKeepsPinsOnTheirCoordinates() {
        // The map turned 90° clockwise on screen about its center: the probe, which was to
        // the right of center, is now below it.
        let t = transform(center: viewCenter, probe: CGPoint(x: 200, y: 300))

        assertPoint(apply(t, toScreen: viewCenter), viewCenter, "Center stays put")
        assertPoint(apply(t, toScreen: referenceProbe), CGPoint(x: 200, y: 300),
                    "A pin drawn at the probe follows it below the center")
        // A pin drawn 50 pts above center ends up 50 pts right of center.
        assertPoint(apply(t, toScreen: CGPoint(x: 200, y: 150)), CGPoint(x: 250, y: 200),
                    "Every pin rotates with the map")
    }

    func testCounterClockwiseRotation() {
        // 45° counter-clockwise on screen: the probe moves up and to the left of its old spot.
        let d = 100 / sqrt(2.0)
        let probe = CGPoint(x: viewCenter.x + d, y: viewCenter.y - d)
        let t = transform(center: viewCenter, probe: probe)

        assertPoint(apply(t, toScreen: referenceProbe), probe, "Probe follows the rotation")
        XCTAssertEqual(t.m11, cos(-Double.pi / 4), accuracy: 1e-6)
        XCTAssertEqual(t.m12, sin(-Double.pi / 4), accuracy: 1e-6)
    }

    func testRotationWithPanAndZoom() {
        // Rotate 90° clockwise, zoom out to 0.5× and pan the center to (260, 180).
        let center = CGPoint(x: 260, y: 180)
        let t = transform(center: center, probe: CGPoint(x: 260, y: 230))

        assertPoint(apply(t, toScreen: viewCenter), center, "Center follows the pan")
        assertPoint(apply(t, toScreen: referenceProbe), CGPoint(x: 260, y: 230),
                    "Probe follows the rotation and zoom")
        assertPoint(apply(t, toScreen: CGPoint(x: 100, y: 200)), CGPoint(x: 260, y: 130),
                    "A pin left of center ends up above it at half the distance")
    }
}

// MARK: - Successive rotation updates through a real MKMapView

/// Drives `Coordinator.mapViewDidChangeVisibleRegion` with a real `MKMapView` and sibling
/// `LandmarkOverlayView`, as `MapContainerView` lays them out. The pure-math tests above can't
/// catch a reference point measured through the overlay's existing transform.
///
/// `async` + `await MainActor.run { }` because the coordinator holds `@MainActor @Observable`
/// stores — see `RefreshLandmarksZoomTests`.
final class GestureTransformMapTests: XCTestCase {

    /// Regression: points were converted into the overlay, whose transform already held the
    /// previous update's rotation, so a turn from 30° to 31° produced a 1° transform and pins
    /// drifted during continuous rotation.
    func testPinsStayOnTheirCoordinatesThroughSuccessiveRotations() async {
        await MainActor.run {
            let bounds    = CGRect(x: 0, y: 0, width: 400, height: 800)
            let container = UIView(frame: bounds)
            let mapView   = MKMapView(frame: bounds)
            let overlay   = LandmarkOverlayView(frame: bounds)
            container.addSubview(mapView)
            container.addSubview(overlay)

            let landmarkContainer = NSPersistentContainer(name: "FogOfWalk")
            let desc = NSPersistentStoreDescription()
            desc.type = NSInMemoryStoreType
            landmarkContainer.persistentStoreDescriptions = [desc]
            landmarkContainer.loadPersistentStores { _, _ in }
            let coordinator = MapContainerView.Coordinator(
                store: ExplorationStore(),
                gridSettings: GridSettings(),
                landmarkStore: LandmarkStore(container: landmarkContainer),
                searchService: LandmarkSearchService()
            )
            coordinator.landmarkOverlayView = overlay

            mapView.setRegion(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)), animated: false)
            // The first callback establishes the north-up reference render.
            coordinator.mapViewDidChangeVisibleRegion(mapView)

            // A pin drawn at this point of the untransformed overlay.
            let drawnAt  = CGPoint(x: 300, y: 150)
            let landmark = mapView.convert(drawnAt, toCoordinateFrom: mapView)

            for heading in [30.0, 31.0, 31.0, 30.0, 45.0] {
                let camera = mapView.camera.copy() as! MKMapCamera
                camera.heading = heading
                mapView.setCamera(camera, animated: false)
                XCTAssertEqual(mapView.camera.heading, heading, accuracy: 0.5,
                               "Precondition: the map took heading \(heading)°")

                coordinator.mapViewDidChangeVisibleRegion(mapView)

                let shown    = displayed(drawnAt, by: overlay)
                let expected = mapView.convert(landmark, toPointTo: container)
                XCTAssertEqual(shown.x, expected.x, accuracy: 1, "x at heading \(heading)°")
                XCTAssertEqual(shown.y, expected.y, accuracy: 1, "y at heading \(heading)°")
            }
        }
    }

    /// Where a point drawn in the overlay appears in its superview, after the layer transform
    /// (applied about the layer's center, its anchor point).
    @MainActor
    func displayed(_ point: CGPoint, by view: UIView) -> CGPoint {
        let t = view.layer.transform
        let x = Double(point.x - view.bounds.midX)
        let y = Double(point.y - view.bounds.midY)
        return CGPoint(x: x * t.m11 + y * t.m21 + t.m41 + view.center.x,
                       y: x * t.m12 + y * t.m22 + t.m42 + view.center.y)
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
            coordinator.gridSettings.showLandmarks = true
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
            coordinator.gridSettings.showLandmarks = true
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

    func testLandmarksHiddenByDefaultProducesNoPins() async {
        await MainActor.run {
            // Other tests in this run may have already flipped and persisted the toggle
            // via the real UserDefaults.standard, so clear it to observe the true default
            // for a value that's never been set.
            UserDefaults.standard.removeObject(forKey: "com.fogofwalk.showLandmarks")
            let (coordinator, store) = makeCoordinator()
            store.addLandmarks([WikidataLandmark(id: "Q1", name: "Museum", description: nil,
                                                lat: 40.7128, lon: -74.0060,
                                                category: "museum", imageURL: nil)],
                               visitedCells: [])
            let mapView = MKMapView()

            XCTAssertFalse(coordinator.gridSettings.showLandmarks,
                           "Precondition: display defaults to off")
            coordinator.refreshLandmarks(in: region(span: 0.01), mapView: mapView)
            XCTAssertEqual(overlayView.pins.count, 0, "Landmarks must not render until enabled")
        }
    }

    func testEnablingShowLandmarksPopulatesPins() async {
        await MainActor.run {
            let (coordinator, store) = makeCoordinator()
            store.addLandmarks([WikidataLandmark(id: "Q1", name: "Museum", description: nil,
                                                lat: 40.7128, lon: -74.0060,
                                                category: "museum", imageURL: nil)],
                               visitedCells: [])
            let mapView = MKMapView()

            coordinator.gridSettings.showLandmarks = true
            coordinator.refreshLandmarks(in: region(span: 0.01), mapView: mapView)
            XCTAssertEqual(overlayView.pins.count, 1, "Enabling the toggle must render pins")
        }
    }

    func testDisablingShowLandmarksClearsPins() async {
        await MainActor.run {
            let (coordinator, store) = makeCoordinator()
            coordinator.gridSettings.showLandmarks = true
            store.addLandmarks([WikidataLandmark(id: "Q1", name: "Museum", description: nil,
                                                lat: 40.7128, lon: -74.0060,
                                                category: "museum", imageURL: nil)],
                               visitedCells: [])
            let mapView = MKMapView()

            coordinator.refreshLandmarks(in: region(span: 0.01), mapView: mapView)
            XCTAssertEqual(overlayView.pins.count, 1,
                           "Precondition: pins populated while enabled")

            coordinator.gridSettings.showLandmarks = false
            coordinator.refreshLandmarks(in: region(span: 0.01), mapView: mapView)
            XCTAssertEqual(overlayView.pins.count, 0, "Disabling the toggle must clear pins")
        }
    }

    /// Regression: every new 50 m cell re-runs `updateUIView`, which rebuilt every pin even
    /// when no landmark had changed.
    func testUnchangedLandmarkStateSkipsPinRebuild() async {
        await MainActor.run {
            let (coordinator, store) = makeCoordinator()
            coordinator.gridSettings.showLandmarks = true
            store.addLandmarks([WikidataLandmark(id: "Q1", name: "Museum", description: nil,
                                                lat: 40.7128, lon: -74.0060,
                                                category: "museum", imageURL: nil)],
                               visitedCells: [])
            let mapView = MKMapView()

            XCTAssertTrue(coordinator.refreshLandmarksIfChanged(in: region(span: 0.01), mapView: mapView))
            XCTAssertEqual(overlayView.pins.count, 1)
            XCTAssertFalse(coordinator.refreshLandmarksIfChanged(in: region(span: 0.01), mapView: mapView),
                           "Nothing changed, so pins must not be rebuilt")

            // A discovery changes what pins show, so it must rebuild.
            store.checkDiscovery(newCell: GridMath.cellID(
                for: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)))
            XCTAssertTrue(coordinator.refreshLandmarksIfChanged(in: region(span: 0.01), mapView: mapView))
            XCTAssertEqual(overlayView.pins.first?.isDiscovered, true)

            coordinator.gridSettings.showLandmarks = false
            XCTAssertTrue(coordinator.refreshLandmarksIfChanged(in: region(span: 0.01), mapView: mapView))
            XCTAssertEqual(overlayView.pins.count, 0)
        }
    }
}
