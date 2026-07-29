import XCTest
import CoreData
import CoreLocation
import MapKit
@testable import FogOfWalk

// MARK: - Mock data source

final class MockLandmarkDataSource: LandmarkDataProviding {
    var callCount = 0
    var returnLandmarks: [WikidataLandmark] = []

    func landmarks(in region: MKCoordinateRegion) -> [WikidataLandmark] {
        callCount += 1
        return returnLandmarks
    }
}

// MARK: - Tests

final class LandmarkSearchServiceTests: XCTestCase {

    @MainActor
    func makeStore() -> LandmarkStore {
        let container = NSPersistentContainer(name: "FogOfWalk")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        container.loadPersistentStores { _, _ in }
        return LandmarkStore(container: container)
    }

    func makeRegion(center: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0),
                    span: MKCoordinateSpan = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)) -> MKCoordinateRegion {
        MKCoordinateRegion(center: center, span: span)
    }

    // MARK: - First search

    func testFirstSearchAlwaysFires() async {
        let mock = MockLandmarkDataSource()
        await MainActor.run {
            let service = LandmarkSearchService(source: mock)
            let store   = makeStore()
            service.searchIfNeeded(region: makeRegion(), landmarkStore: store, visitedCells: [])
        }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(mock.callCount, 1, "First call should always trigger a search")
    }

    // MARK: - Rate limiting by time

    func testImmediateRepeatIsSuppressed() async {
        let mock = MockLandmarkDataSource()
        await MainActor.run {
            let service = LandmarkSearchService(source: mock)
            let store   = makeStore()
            let region  = makeRegion()
            service.searchIfNeeded(region: region, landmarkStore: store, visitedCells: [])
            service.searchIfNeeded(region: region, landmarkStore: store, visitedCells: [])
            service.searchIfNeeded(region: region, landmarkStore: store, visitedCells: [])
        }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(mock.callCount, 1, "Repeated calls within the time window should be suppressed")
    }

    // MARK: - Rate limiting by distance

    func testSmallMovementIsSuppressed() async {
        let mock = MockLandmarkDataSource()
        await MainActor.run {
            let service = LandmarkSearchService(source: mock)
            let store   = makeStore()
            let center1 = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            // 10 m move — well under the 500 m threshold
            let center2 = CLLocationCoordinate2D(latitude: 40.7129, longitude: -74.0060)
            service.searchIfNeeded(region: makeRegion(center: center1), landmarkStore: store, visitedCells: [])
            service.searchIfNeeded(region: makeRegion(center: center2), landmarkStore: store, visitedCells: [])
        }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(mock.callCount, 1, "Small movement should not trigger a second search")
    }

    func testLargeMovementTriggersSearch() async {
        let mock = MockLandmarkDataSource()
        await MainActor.run {
            let service = LandmarkSearchService(source: mock)
            let store   = makeStore()
            let center1 = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            // ~800 m north — over the 500 m threshold
            let center2 = CLLocationCoordinate2D(latitude: 40.7200, longitude: -74.0060)
            service.searchIfNeeded(region: makeRegion(center: center1), landmarkStore: store, visitedCells: [])
            service.searchIfNeeded(region: makeRegion(center: center2), landmarkStore: store, visitedCells: [])
        }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(mock.callCount, 2, "Large movement should trigger a new search")
    }

    // MARK: - Landmark loading into store

    func testLandmarksFromSourceAreAddedToStore() async {
        let mock = MockLandmarkDataSource()
        mock.returnLandmarks = [
            WikidataLandmark(id: "Q1", name: "Met Museum",  description: nil,
                             lat: 40.7794, lon: -73.9632, category: "museum",  imageURL: nil),
            WikidataLandmark(id: "Q2", name: "JFK Airport", description: nil,
                             lat: 40.6413, lon: -73.7781, category: "airport", imageURL: nil),
        ]

        var store: LandmarkStore!
        await MainActor.run {
            store = makeStore()
            let service = LandmarkSearchService(source: mock)
            service.searchIfNeeded(region: makeRegion(), landmarkStore: store, visitedCells: [])
        }
        try? await Task.sleep(for: .milliseconds(100))
        await MainActor.run {
            XCTAssertEqual(store.allLandmarks.count, 2)
            let names = Set(store.allLandmarks.map { $0.name })
            XCTAssertTrue(names.contains("Met Museum"))
            XCTAssertTrue(names.contains("JFK Airport"))
        }
    }

    func testLandmarksAreNotDuplicatedOnRepeatSearch() async {
        let mock = MockLandmarkDataSource()
        mock.returnLandmarks = [
            WikidataLandmark(id: "Q1", name: "Museum", description: nil,
                             lat: 40.0, lon: -74.0, category: "museum", imageURL: nil),
        ]

        var store: LandmarkStore!
        await MainActor.run {
            store = makeStore()
            let service = LandmarkSearchService(source: mock)
            // First search
            service.searchIfNeeded(region: makeRegion(), landmarkStore: store, visitedCells: [])
        }
        try? await Task.sleep(for: .milliseconds(100))

        // Second search from far away (triggers a new load)
        await MainActor.run {
            let service2 = LandmarkSearchService(source: mock)
            service2.searchIfNeeded(region: makeRegion(), landmarkStore: store, visitedCells: [])
        }
        try? await Task.sleep(for: .milliseconds(100))

        await MainActor.run {
            XCTAssertEqual(store.allLandmarks.count, 1, "Same landmark should not be stored twice")
        }
    }

    // MARK: - Zoom gating

    func testSearchServiceSkipsWideZoom() async {
        let mock = MockLandmarkDataSource()
        await MainActor.run {
            let service = LandmarkSearchService(source: mock)
            let store   = makeStore()
            let wide    = makeRegion(span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30))
            service.searchIfNeeded(region: wide, landmarkStore: store, visitedCells: [])
        }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(mock.callCount, 0,
                       "A world-zoom region must not ingest landmarks")
    }

    func testSearchServiceRunsAtWalkingZoom() async {
        let mock = MockLandmarkDataSource()
        await MainActor.run {
            let service = LandmarkSearchService(source: mock)
            let store   = makeStore()
            let close   = makeRegion(span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
            service.searchIfNeeded(region: close, landmarkStore: store, visitedCells: [])
        }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(mock.callCount, 1,
                       "Walking zoom must still ingest — the span guard must not be too aggressive")
    }

    func testWideZoomDoesNotConsumeRateLimitBudget() async {
        // The span guard must sit above the lastSearchTime/lastSearchCenter writes, or a
        // skipped wide zoom would suppress the next legitimate query for 30 s.
        let mock = MockLandmarkDataSource()
        await MainActor.run {
            let service = LandmarkSearchService(source: mock)
            let store   = makeStore()
            let center  = CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0)
            service.searchIfNeeded(
                region: makeRegion(center: center,
                                   span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30)),
                landmarkStore: store, visitedCells: [])
            service.searchIfNeeded(
                region: makeRegion(center: center,
                                   span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)),
                landmarkStore: store, visitedCells: [])
        }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(mock.callCount, 1,
                       "Zooming back in after a wide zoom must still fire a search")
    }

    // MARK: - Empty source

    func testEmptySourceAddsNoLandmarks() async {
        let mock = MockLandmarkDataSource()
        mock.returnLandmarks = []

        var store: LandmarkStore!
        await MainActor.run {
            store = makeStore()
            let service = LandmarkSearchService(source: mock)
            service.searchIfNeeded(region: makeRegion(), landmarkStore: store, visitedCells: [])
        }
        try? await Task.sleep(for: .milliseconds(100))
        await MainActor.run {
            XCTAssertEqual(store.allLandmarks.count, 0)
        }
    }
}
