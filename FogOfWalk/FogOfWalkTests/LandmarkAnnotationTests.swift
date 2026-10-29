import XCTest
import MapKit
import CoreData
@testable import FogOfWalk

@MainActor
private func makeLandmarkCoordinator() -> MapContainerView.Coordinator {
    let container = NSPersistentContainer(name: "FogOfWalk")
    let desc = NSPersistentStoreDescription()
    desc.type = NSInMemoryStoreType
    container.persistentStoreDescriptions = [desc]
    container.loadPersistentStores { _, error in XCTAssertNil(error) }
    return MapContainerView.Coordinator(store: ExplorationStore(container: container),
        gridSettings: GridSettings(), landmarkStore: LandmarkStore(container: container),
        searchService: LandmarkSearchService(source: EmptyLandmarkSource()))
}

// Observable stores must be created and released inside a Task (see LandmarkStoreTests).
final class LandmarkAnnotationTests: XCTestCase {
    func region(span: Double = 0.02, longitude: Double = -74) -> MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 40, longitude: longitude),
                           span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))
    }

    func item(_ id: String = "Q1", longitude: Double = -74) -> WikidataLandmark {
        WikidataLandmark(id: id, name: "Museum", description: nil, lat: 40, lon: longitude,
                         category: "museum", imageURL: nil)
    }

    func testToggleAndWideZoomClearAndRestoreOnlyLandmarkAnnotations() async {
        await MainActor.run {
            let coordinator = makeLandmarkCoordinator()
            let oldSetting = coordinator.gridSettings.showLandmarks
            defer { coordinator.gridSettings.showLandmarks = oldSetting }
            let map = MKMapView()
            let other = MKPointAnnotation()
            map.addAnnotation(other)
            coordinator.landmarkStore.addLandmarks([item()], visitedCells: [])
            coordinator.gridSettings.showLandmarks = true
            coordinator.refreshLandmarks(in: region(), mapView: map)
            XCTAssertEqual(coordinator.landmarkAnnotations.count, 1)
            coordinator.refreshLandmarks(in: region(span: 30), mapView: map)
            XCTAssertTrue(coordinator.landmarkAnnotations.isEmpty)
            XCTAssertTrue(map.annotations.contains { $0 === other })
            coordinator.refreshLandmarks(in: region(), mapView: map)
            XCTAssertEqual(coordinator.landmarkAnnotations.count, 1)
            coordinator.gridSettings.showLandmarks = false
            XCTAssertTrue(coordinator.refreshLandmarksIfChanged(in: region(), mapView: map))
            XCTAssertTrue(coordinator.landmarkAnnotations.isEmpty)
            coordinator.gridSettings.showLandmarks = true
            XCTAssertTrue(coordinator.refreshLandmarksIfChanged(in: region(), mapView: map))
            XCTAssertEqual(coordinator.landmarkAnnotations.count, 1)
        }
    }

    func testUnchangedRefreshRetainsAnnotationIdentityAndDiscoveryUpdatesData() async throws {
        try await MainActor.run {
            let coordinator = makeLandmarkCoordinator()
            let oldSetting = coordinator.gridSettings.showLandmarks
            defer { coordinator.gridSettings.showLandmarks = oldSetting }
            coordinator.gridSettings.showLandmarks = true
            coordinator.landmarkStore.addLandmarks([item(), item("Q2", longitude: -73.985)], visitedCells: [])
            let map = MKMapView()
            XCTAssertTrue(coordinator.refreshLandmarksIfChanged(in: region(), mapView: map))
            let annotation = try XCTUnwrap(coordinator.landmarkAnnotations["Q1"])
            XCTAssertFalse(coordinator.refreshLandmarksIfChanged(in: region(), mapView: map))
            coordinator.refreshLandmarks(in: region(longitude: -73.999), mapView: map)
            XCTAssertTrue(coordinator.landmarkAnnotations["Q1"] === annotation)
            coordinator.landmarkStore.checkDiscovery(newCell: GridMath.cellID(for: annotation.coordinate))
            XCTAssertTrue(coordinator.refreshLandmarksIfChanged(in: region(), mapView: map))
            XCTAssertTrue(coordinator.landmarkAnnotations["Q1"] === annotation)
            XCTAssertTrue(annotation.pin.isDiscovered)
            let freshView = try XCTUnwrap(coordinator.mapView(map, viewFor: annotation) as? LandmarkAnnotationView)
            XCTAssertTrue(freshView.isEnabled, "Offscreen discovery must configure reused/new views from current data")
            coordinator.refreshLandmarks(in: region(longitude: -70), mapView: map)
            XCTAssertTrue(coordinator.landmarkAnnotations.isEmpty)
            XCTAssertFalse(map.annotations.contains { $0 === annotation })
        }
    }

    func testSelectionOpensOnlyDiscoveredPinsAndAllowsRepeatedTaps() async throws {
        try await MainActor.run {
            let coordinator = makeLandmarkCoordinator()
            let map = SelectionRecordingMap()
            let annotation = LandmarkAnnotation(pin: LandmarkPin(identifier: "Q1", name: "Museum", category: "museum",
                coordinate: region().center, isDiscovered: false))
            let view = try XCTUnwrap(coordinator.mapView(map, viewFor: annotation))
            var taps: [String] = []
            coordinator.onLandmarkTapped = { taps.append($0) }
            coordinator.mapView(map, didSelect: view)
            XCTAssertTrue(taps.isEmpty)
            _ = annotation.update(pin: LandmarkPin(identifier: "Q1", name: "Museum", category: "museum",
                coordinate: region().center, isDiscovered: true))
            for _ in 0..<2 { coordinator.mapView(map, didSelect: view) }
            XCTAssertEqual(taps, ["Q1", "Q1"])
            XCTAssertEqual(map.deselections, 3)
            XCTAssertTrue(coordinator.mapView(map, viewFor: map.userLocation) is HeadingUserLocationView)
            XCTAssertNil(coordinator.mapView(map, viewFor: MKPointAnnotation()))
        }
    }

    func testInstalledAnnotationCapAndGateUseVisibleSpanInsteadOfPaddedSpan() async {
        await MainActor.run {
            let coordinator = makeLandmarkCoordinator()
            let oldSetting = coordinator.gridSettings.showLandmarks
            defer { coordinator.gridSettings.showLandmarks = oldSetting }
            coordinator.gridSettings.showLandmarks = true
            let map = MKMapView()
            coordinator.landmarkStore.addLandmarks((1...350).map { item("Q\($0)") }, visitedCells: [])
            // The padded span is 1.6 degrees, but the visible span remains eligible.
            coordinator.refreshLandmarks(in: region(span: 0.8), mapView: map)
            XCTAssertEqual(coordinator.landmarkAnnotations.count, 300)
            XCTAssertEqual(map.annotations.filter { $0 is LandmarkAnnotation }.count, 300)
            coordinator.refreshLandmarks(in: region(span: 1.01), mapView: map)
            XCTAssertTrue(coordinator.landmarkAnnotations.isEmpty)
            XCTAssertTrue(map.annotations.filter { $0 is LandmarkAnnotation }.isEmpty)
        }
    }

    func testCountNeutralMetadataEditRefreshesRetainedAnnotation() async throws {
        try await MainActor.run {
            let coordinator = makeLandmarkCoordinator()
            let oldSetting = coordinator.gridSettings.showLandmarks
            defer { coordinator.gridSettings.showLandmarks = oldSetting }
            coordinator.gridSettings.showLandmarks = true
            coordinator.landmarkStore.addLandmarks([item()], visitedCells: [])
            let map = MKMapView()
            coordinator.refreshLandmarks(in: region(), mapView: map)
            let annotation = try XCTUnwrap(coordinator.landmarkAnnotations["Q1"])
            let generation = coordinator.landmarkStore.renderGeneration
            let landmark = try XCTUnwrap(coordinator.landmarkStore.allLandmarks.first)
            landmark.name = "Renamed without changing counts"
            landmark.category = "zoo"
            landmark.latitude += 0.001
            try landmark.managedObjectContext!.save()
            XCTAssertGreaterThan(coordinator.landmarkStore.renderGeneration, generation)
            XCTAssertEqual(coordinator.landmarkStore.allLandmarks.count, 1)
            XCTAssertEqual(coordinator.landmarkStore.totalDiscovered, 0)
            XCTAssertTrue(coordinator.refreshLandmarksIfChanged(in: region(), mapView: map))
            XCTAssertTrue(coordinator.landmarkAnnotations["Q1"] === annotation)
            XCTAssertEqual(annotation.pin.name, landmark.name)
            XCTAssertEqual(annotation.pin.category, "zoo")
            XCTAssertEqual(annotation.coordinate.latitude, landmark.latitude)
        }
    }

    func testDisplayDefaultsOff() async {
        await MainActor.run {
            let key = "com.fogofwalk.showLandmarks"
            let old = UserDefaults.standard.object(forKey: key)
            defer { UserDefaults.standard.set(old, forKey: key) }
            UserDefaults.standard.removeObject(forKey: key)
            let coordinator = makeLandmarkCoordinator()
            let map = MKMapView()
            coordinator.landmarkStore.addLandmarks([item()], visitedCells: [])
            coordinator.refreshLandmarks(in: region(), mapView: map)
            XCTAssertFalse(coordinator.gridSettings.showLandmarks)
            XCTAssertTrue(coordinator.landmarkAnnotations.isEmpty)
        }
    }
}

private final class SelectionRecordingMap: MKMapView {
    var deselections = 0
    override func deselectAnnotation(_ annotation: MKAnnotation?, animated: Bool) {
        deselections += 1
        super.deselectAnnotation(annotation, animated: animated)
    }
}

final class LandmarkMapGeometryTests: XCTestCase {
    func testFiftyPinsKeepAnchorsAndGlyphSizeAcrossPanZoomRotationAndDiscovery() async throws {
        for _ in 0..<50 {
            if await MainActor.run(body: { !UIApplication.shared.connectedScenes.isEmpty }) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let fixture = try await MainActor.run { try LandmarkGeometryFixture() }
        for (span, heading, longitude) in [(0.02, 0.0, -74.0), (0.015, 30.0, -74.001),
                                            (0.01, 31.0, -74.0), (0.02, 90.0, -74.0)] {
            await MainActor.run { fixture.move(span: span, heading: heading, longitude: longitude) }
            // Allow MapKit's native annotation placement to finish; no manual pin positioning.
            try await Task.sleep(for: .milliseconds(400))
            await MainActor.run { fixture.checkGeometry() }
        }
        await MainActor.run {
            let annotation = fixture.coordinator.landmarkAnnotations["Q1"]!
            let before = fixture.map.view(for: annotation)
            fixture.coordinator.landmarkStore.checkDiscovery(newCell: GridMath.cellID(for: annotation.coordinate))
            fixture.coordinator.refreshLandmarksIfChanged(in: fixture.map.region, mapView: fixture.map)
            XCTAssertTrue(fixture.map.view(for: annotation) === before)
            XCTAssertTrue(before?.isEnabled == true, "A visible hint becomes tappable in its existing view")
            XCTAssertEqual(before?.accessibilityLabel, "Museum 1")
            fixture.close()
        }
    }
}

@MainActor
private final class LandmarkGeometryFixture {
    let coordinator = makeLandmarkCoordinator()
    let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
    let window: UIWindow
    var originalSizes: [String: CGSize] = [:]

    init() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = map.frame
        let root = UIViewController()
        window.rootViewController = root
        root.view.addSubview(map)
        window.makeKeyAndVisible()
        map.delegate = coordinator
        map.isPitchEnabled = false
        coordinator.gridSettings.showLandmarks = true
        coordinator.landmarkStore.addLandmarks((1...50).map {
            WikidataLandmark(id: "Q\($0)", name: "Museum \($0)", description: nil,
                lat: 40 + Double($0 % 5) * 0.0005, lon: -74 + Double($0 / 5) * 0.0003,
                category: "museum", imageURL: nil)
        }, visitedCells: [])
        move(span: 0.02, heading: 0, longitude: -74)
    }

    func move(span: Double, heading: Double, longitude: Double) {
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 40.001, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)), animated: false)
        let camera = map.camera.copy() as! MKMapCamera
        camera.heading = heading
        map.setCamera(camera, animated: false)
        coordinator.mapView(map, regionDidChangeAnimated: false)
    }

    func checkGeometry(file: StaticString = #filePath, line: UInt = #line) {
        var checked = 0
        for annotation in coordinator.landmarkAnnotations.values {
            guard let view = map.view(for: annotation) else { continue }
            checked += 1
            let anchor = view.convert(CGPoint(x: view.bounds.midX - view.centerOffset.x,
                                              y: view.bounds.midY - view.centerOffset.y), to: map)
            let expected = map.convert(annotation.coordinate, toPointTo: map)
            XCTAssertEqual(anchor.x, expected.x, accuracy: 1, file: file, line: line)
            XCTAssertEqual(anchor.y, expected.y, accuracy: 1, file: file, line: line)
            if let oldSize = originalSizes[annotation.identifier] {
                XCTAssertEqual(view.bounds.size, oldSize, file: file, line: line)
            }
            originalSizes[annotation.identifier] = view.bounds.size
            XCTAssertEqual(view.transform, .identity, file: file, line: line)
        }
        XCTAssertEqual(checked, 50, "Required priority preserves overlapping pins", file: file, line: line)
    }

    func close() {
        coordinator.gridSettings.showLandmarks = false
        map.delegate = nil
        map.removeFromSuperview()
        window.isHidden = true
        window.rootViewController = nil
    }
}
