import XCTest
import CoreData
import CoreLocation
import MapKit
@testable import FogOfWalk

// All tests are `async` and work inside `MainActor.run` — see the header of
// ExplorationStoreTests.swift for the iOS 26+ simulator dealloc crash this avoids.
final class ExplorationRecorderTests: XCTestCase {

    private func makeInMemoryContainer() -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "FogOfWalk")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error { XCTFail("In-memory store failed: \(error)") }
        }
        return container
    }

    /// Centre of cell (x, y) — near (0°, 0°), where one cell is ~50 m on both axes.
    private func location(x: Int32, y: Int32) -> CLLocation {
        let c = GridMath.center(for: CellID(x: x, y: y))
        return CLLocation(latitude: c.latitude, longitude: c.longitude)
    }

    // MARK: - App wiring (background relaunch)

    /// Regression: the normal app used to record only through the map coordinator, so a
    /// scene-less background relaunch dropped every location. `connect` must make a
    /// delivered location reach the store with no map, for both app identities.
    func testConnectRecordsDeliveredLocationsWithoutAMapForBothIdentities() async {
        await MainActor.run {
            for isStudyApp in [false, true] {
                let container = makeInMemoryContainer()
                let store = ExplorationStore(container: container)
                let landmarks = LandmarkStore(container: container)
                let defaults = UserDefaults(suiteName: "fog-recorder-\(UUID().uuidString)")!
                let service = LocationService(manager: MockLocationManager(), isStudyApp: isStudyApp,
                                              defaults: defaults)
                ExplorationRecorder.connect(location: service, store: store, landmarks: landmarks,
                                            geocoder: LocalityGeocoder(geocoder: MockGeocoder(),
                                                                       requestDelay: .zero),
                                            landmarkSource: nil)
                service.onLocationUpdate?(location(x: 3, y: 4))
                XCTAssertEqual(store.visitedCellsCache, [CellID(x: 3, y: 4)],
                               "isStudyApp=\(isStudyApp): location must be recorded without a map")
            }
        }
    }

    func testConnectWiresNewCellsToTheGeocoder() async {
        let geocoded = XCTestExpectation(description: "new cell geocoded")
        let mock = MockGeocoder(locality: "Walkville", onCall: { geocoded.fulfill() })
        var service: LocationService?
        var store: ExplorationStore?
        var geocoder: LocalityGeocoder?

        await MainActor.run {
            let container = makeInMemoryContainer()
            store = ExplorationStore(container: container)
            service = LocationService(manager: MockLocationManager(), isStudyApp: false)
            geocoder = LocalityGeocoder(geocoder: mock, requestDelay: .zero)
            ExplorationRecorder.connect(location: service!, store: store!,
                                        landmarks: LandmarkStore(container: container),
                                        geocoder: geocoder!, landmarkSource: nil)
            service!.onLocationUpdate?(location(x: 1, y: 1))
        }

        await fulfillment(of: [geocoded], timeout: 5)
        await MainActor.run {
            XCTAssertEqual(mock.callCount, 1)
            service = nil; store = nil; geocoder = nil
        }
    }

    // MARK: - Walk-time landmark ingest

    /// Regression: landmarks were ingested only when the map showed a region, so walking past
    /// one with the phone in a pocket discovered nothing.
    func testWalkingDiscoversALandmarkNeverShownOnTheMap() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let store = ExplorationStore(container: container)
            let landmarks = LandmarkStore(container: container)
            let near = GridMath.center(for: CellID(x: 16, y: 16))
            let source = FakeLandmarkSource(items: [
                WikidataLandmark(id: "Q1", name: "Pocket Museum", description: nil,
                                 lat: near.latitude, lon: near.longitude,
                                 category: "museum", imageURL: nil)
            ])
            XCTAssertTrue(landmarks.allLandmarks.isEmpty, "Precondition: nothing ingested yet")

            let recorder = ExplorationRecorder(store: store, landmarks: landmarks, landmarkSource: source)
            recorder.record(location(x: 16, y: 16))

            XCTAssertEqual(landmarks.allLandmarks.map(\.identifier), ["Q1"])
            XCTAssertEqual(landmarks.totalDiscovered, 1, "The walked-past landmark must be discovered")
            XCTAssertNotNil(landmarks.allLandmarks.first?.firstDiscovered)
        }
    }

    func testIngestQueriesEachBucketOncePerLaunch() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let store = ExplorationStore(container: container)
            let landmarks = LandmarkStore(container: container)
            let source = FakeLandmarkSource(items: [])
            let recorder = ExplorationRecorder(store: store, landmarks: landmarks, landmarkSource: source)

            // Both cells sit mid-bucket, so their discovery boxes fall in the same bucket.
            recorder.record(location(x: 16, y: 16))
            recorder.record(location(x: 17, y: 16))
            XCTAssertEqual(source.queries.count, 1, "A bucket already ingested must not be re-queried")

            // The queried region must cover the full discovery radius around the cell.
            let region = source.queries[0]
            let centre = GridMath.center(for: CellID(x: 16, y: 16))
            let radiusDegrees = LandmarkStore.maxDiscoveryRadius / GridMath.metersPerDegree
            XCTAssertLessThanOrEqual(region.center.latitude - region.span.latitudeDelta / 2,
                                     centre.latitude - radiusDegrees)
            XCTAssertGreaterThanOrEqual(region.center.longitude + region.span.longitudeDelta / 2,
                                        centre.longitude + radiusDegrees)
        }
    }

    func testRevisitingACellDoesNotQueryLandmarks() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let store = ExplorationStore(container: container)
            store.addCell(CellID(x: 16, y: 16))
            let source = FakeLandmarkSource(items: [])
            let recorder = ExplorationRecorder(store: store,
                                               landmarks: LandmarkStore(container: container),
                                               landmarkSource: source)
            recorder.record(location(x: 16, y: 16))
            XCTAssertTrue(source.queries.isEmpty, "Only newly walked cells trigger ingest")
        }
    }
}

@MainActor
private final class FakeLandmarkSource: LandmarkDataProviding {
    let items: [WikidataLandmark]
    private(set) var queries: [MKCoordinateRegion] = []

    init(items: [WikidataLandmark]) { self.items = items }

    func landmarks(in region: MKCoordinateRegion) -> [WikidataLandmark] {
        queries.append(region)
        return items
    }
}
