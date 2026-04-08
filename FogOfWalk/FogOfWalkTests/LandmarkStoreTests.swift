import XCTest
import CoreData
import CoreLocation
import MapKit
@testable import FogOfWalk

// NOTE: All test methods are `async` so they run inside a Swift Task. This is
// necessary on the iOS 26 beta simulator to avoid a Swift-runtime crash that
// occurs when a @MainActor @Observable object is deallocated from a non-Task
// XCTest context.

final class LandmarkStoreTests: XCTestCase {

    // MARK: - Helpers

    func makeInMemoryContainer() -> NSPersistentContainer {
        let container   = NSPersistentContainer(name: "FogOfWalk")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error { XCTFail("In-memory store failed to load: \(error)") }
        }
        return container
    }

    @MainActor
    func makeStore() -> LandmarkStore {
        LandmarkStore(container: makeInMemoryContainer())
    }

    /// Inserts a Landmark entity directly into Core Data, bypassing `addLandmarks`.
    /// Used by migration tests to simulate pre-Wikidata stored data.
    @MainActor
    func insertRawLandmark(id: String, into container: NSPersistentContainer) {
        let ctx = container.viewContext
        let entity = Landmark(context: ctx)
        entity.identifier            = id
        entity.name                  = "Legacy Landmark"
        entity.category              = "MKPOICategoryMuseum"
        entity.latitude              = 40.0
        entity.longitude             = -74.0
        entity.discoveryRadiusMeters = 100
        entity.isDiscovered          = false
        entity.firstSeen             = Date()
        try? ctx.save()
    }

    func makeWikidataLandmark(
        id: String = "Q1",
        name: String = "Test Landmark",
        description: String? = nil,
        lat: Double = 40.0,
        lon: Double = -74.0,
        category: String = "museum",
        imageURL: String? = nil
    ) -> WikidataLandmark {
        WikidataLandmark(id: id, name: name, description: description,
                         lat: lat, lon: lon, category: category, imageURL: imageURL)
    }

    // MARK: - addLandmarks

    func testAddLandmarksDeduplicatesByIdentifier() async {
        await MainActor.run {
            let store = makeStore()
            let item = makeWikidataLandmark(id: "Q99", name: "Stadium", category: "stadium")

            store.addLandmarks([item])
            store.addLandmarks([item])

            XCTAssertEqual(store.allLandmarks.count, 1, "Duplicate landmark should not be inserted twice")
        }
    }

    func testAddLandmarksStoresCorrectAttributes() async {
        await MainActor.run {
            let store = makeStore()
            let item  = makeWikidataLandmark(id: "Q42", name: "Museum of Art",
                                             lat: 34.0, lon: -118.0, category: "museum")

            store.addLandmarks([item])

            let landmark = store.allLandmarks.first
            XCTAssertNotNil(landmark)
            XCTAssertEqual(landmark?.identifier, "Q42")
            XCTAssertEqual(landmark?.name, "Museum of Art")
            XCTAssertEqual(landmark?.category, "museum")
            XCTAssertEqual(landmark?.latitude  ?? 0, 34.0,   accuracy: 0.0001)
            XCTAssertEqual(landmark?.longitude ?? 0, -118.0, accuracy: 0.0001)
            XCTAssertFalse(landmark?.isDiscovered ?? true)
        }
    }

    func testAddMultipleLandmarksAtOnce() async {
        await MainActor.run {
            let store = makeStore()
            let items = [
                makeWikidataLandmark(id: "Q1", name: "Museum",   category: "museum"),
                makeWikidataLandmark(id: "Q2", name: "Airport",  category: "airport"),
                makeWikidataLandmark(id: "Q3", name: "Stadium",  category: "stadium"),
            ]
            store.addLandmarks(items)
            XCTAssertEqual(store.allLandmarks.count, 3)
        }
    }

    // MARK: - Category discovery radii

    func testCategoryRadiusForWikidataCategories() async {
        await MainActor.run {
            let categories: [(String, Double)] = [
                ("airport",      500),
                ("stadium",      300),
                ("amusementPark", 400),
                ("nationalPark",  300),
                ("zoo",          200),
                ("university",   200),
                ("museum",       100),
                ("theater",      100),
                ("library",      100),
                ("landmark",     100),
            ]
            for (cat, expectedRadius) in categories {
                let item = makeWikidataLandmark(id: "Q\(cat)", category: cat)
                let store = makeStore()
                store.addLandmarks([item])
                XCTAssertEqual(
                    store.allLandmarks.first?.discoveryRadiusMeters ?? 0,
                    expectedRadius,
                    "Category '\(cat)' should have radius \(expectedRadius)"
                )
            }
        }
    }

    func testUnknownCategoryDefaultsToOneHundredMeters() async {
        await MainActor.run {
            let store = makeStore()
            store.addLandmarks([makeWikidataLandmark(category: "unknownType")])
            XCTAssertEqual(store.allLandmarks.first?.discoveryRadiusMeters, 100)
        }
    }

    // MARK: - checkDiscovery

    func testCheckDiscoveryWithinRadius() async {
        await MainActor.run {
            let store    = makeStore()
            let cellSize = 50.0
            let coord    = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            store.addLandmarks([makeWikidataLandmark(id: "Q10", name: "Famous Landmark",
                                                     lat: coord.latitude, lon: coord.longitude,
                                                     category: "landmark")])

            let cell         = GridMath.cellID(for: coord)
            let discovered   = store.checkDiscovery(visitedCells: [cell])

            XCTAssertEqual(discovered.count, 1, "Landmark should be discovered when its cell is visited")
            XCTAssertTrue(discovered.first?.isDiscovered ?? false)
            XCTAssertNotNil(discovered.first?.firstDiscovered)
        }
    }

    func testCheckDiscoveryOutsideRadius() async {
        await MainActor.run {
            let store    = makeStore()
            let cellSize = 50.0
            let landmarkCoord = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            store.addLandmarks([makeWikidataLandmark(lat: landmarkCoord.latitude,
                                                     lon: landmarkCoord.longitude,
                                                     category: "museum")])

            // Visit a cell ~10 km away
            let farCoord = CLLocationCoordinate2D(latitude: 40.8000, longitude: -74.0060)
            let farCell  = GridMath.cellID(for: farCoord)
            let discovered = store.checkDiscovery(visitedCells: [farCell])

            XCTAssertEqual(discovered.count, 0)
            XCTAssertFalse(store.allLandmarks.first?.isDiscovered ?? true)
        }
    }

    func testCheckDiscoveryDoesNotFireTwice() async {
        await MainActor.run {
            let store    = makeStore()
            let cellSize = 50.0
            let coord    = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            store.addLandmarks([makeWikidataLandmark(lat: coord.latitude, lon: coord.longitude)])

            let cell   = GridMath.cellID(for: coord)
            let first  = store.checkDiscovery(visitedCells: [cell])
            let second = store.checkDiscovery(visitedCells: [cell])

            XCTAssertEqual(first.count,  1, "Should discover landmark on first check")
            XCTAssertEqual(second.count, 0, "Should not re-discover already-discovered landmark")
        }
    }

    func testCheckDiscoveryAirportLargeRadius() async {
        await MainActor.run {
            let store    = makeStore()
            let cellSize = 50.0
            let airportCoord = CLLocationCoordinate2D(latitude: 40.6413, longitude: -73.7781)
            store.addLandmarks([makeWikidataLandmark(id: "QJFK", name: "JFK Airport",
                                                     lat: airportCoord.latitude,
                                                     lon: airportCoord.longitude,
                                                     category: "airport")])

            // Visit a cell 300 m from the airport — within 500 m radius
            let nearCoord = CLLocationCoordinate2D(latitude: 40.6440, longitude: -73.7781)
            let nearCell  = GridMath.cellID(for: nearCoord)
            let discovered = store.checkDiscovery(visitedCells: [nearCell])

            XCTAssertEqual(discovered.count, 1, "Airport with 500 m radius should be discoverable at 300 m")
        }
    }

    func testCheckDiscoveryWithLargeCellSetOnlyChecksNearby() async {
        // Regression test for the O(cells * landmarks) performance fix.
        // Discovery should still work correctly when there are many visited cells,
        // most of which are far from the undiscovered landmark.
        await MainActor.run {
            let store    = makeStore()
            let cellSize = 50.0
            let coord    = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            store.addLandmarks([makeWikidataLandmark(id: "QPERF", lat: coord.latitude,
                                                     lon: coord.longitude, category: "landmark")])

            // Build a large set: the target cell plus 500 far-away cells.
            var cells: Set<CellID> = []
            let targetCell = GridMath.cellID(for: coord)
            cells.insert(targetCell)
            for i in Int32(1)...500 {
                cells.insert(CellID(x: targetCell.x + i * 200, y: targetCell.y + i * 200))
            }

            let discovered = store.checkDiscovery(visitedCells: cells)
            XCTAssertEqual(discovered.count, 1,
                "Landmark should be discovered even with many far-away cells in the set")
        }
    }

    func testCheckDiscoveryMultipleLandmarks() async {
        await MainActor.run {
            let store    = makeStore()
            let cellSize = 50.0
            let coord    = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)

            store.addLandmarks([
                makeWikidataLandmark(id: "Q1", lat: coord.latitude, lon: coord.longitude, category: "museum"),
                makeWikidataLandmark(id: "Q2", lat: coord.latitude, lon: coord.longitude, category: "library"),
            ])

            let cell       = GridMath.cellID(for: coord)
            let discovered = store.checkDiscovery(visitedCells: [cell])

            XCTAssertEqual(discovered.count, 2, "Both nearby landmarks should be discovered at once")
        }
    }

    // MARK: - totalDiscovered

    func testTotalDiscoveredUpdatesAfterDiscovery() async {
        await MainActor.run {
            let store    = makeStore()
            let cellSize = 50.0
            let coord    = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            store.addLandmarks([makeWikidataLandmark(lat: coord.latitude, lon: coord.longitude)])

            XCTAssertEqual(store.totalDiscovered, 0)

            let cell = GridMath.cellID(for: coord)
            store.checkDiscovery(visitedCells: [cell])

            XCTAssertEqual(store.totalDiscovered, 1)
        }
    }

    // MARK: - Persistence

    func testLandmarksPersistAcrossStoreInstances() async {
        let container = makeInMemoryContainer()

        await MainActor.run {
            let store1 = LandmarkStore(container: container)
            let coord  = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            store1.addLandmarks([makeWikidataLandmark(id: "QPERSIST", lat: coord.latitude, lon: coord.longitude)])
            XCTAssertEqual(store1.allLandmarks.count, 1)

            let cell = GridMath.cellID(for: coord)
            store1.checkDiscovery(visitedCells: [cell])
            XCTAssertEqual(store1.totalDiscovered, 1)
        }

        await MainActor.run {
            let store2 = LandmarkStore(container: container)
            XCTAssertEqual(store2.allLandmarks.count, 1, "Landmarks must survive store re-instantiation")
            XCTAssertEqual(store2.totalDiscovered, 1, "Discovered state must survive store re-instantiation")
            XCTAssertTrue(store2.allLandmarks.first?.isDiscovered ?? false)
        }
    }

    // MARK: - landmarks(in:)

    func testLandmarksInRegionFiltersCorrectly() async {
        await MainActor.run {
            let store = makeStore()
            store.addLandmarks([
                makeWikidataLandmark(id: "QNYC",    name: "NYC Museum",    lat: 40.7128,  lon: -74.0060),
                makeWikidataLandmark(id: "QLONDON", name: "London Museum", lat: 51.5074,  lon: -0.1278),
            ])

            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
                span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
            )
            let visible = store.landmarks(in: region)

            XCTAssertEqual(visible.count, 1, "Only landmark inside region should be returned")
            XCTAssertEqual(visible.first?.name, "NYC Museum")
        }
    }

    func testLandmarksInRegionIncludesBothDiscoveredAndUndiscovered() async {
        await MainActor.run {
            let store    = makeStore()
            let cellSize = 50.0
            let coord    = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)

            store.addLandmarks([
                makeWikidataLandmark(id: "Q1", lat: coord.latitude, lon: coord.longitude),
                makeWikidataLandmark(id: "Q2", lat: coord.latitude + 0.001, lon: coord.longitude),
            ])

            // Discover only Q1
            let cell = GridMath.cellID(for: coord)
            store.checkDiscovery(visitedCells: [cell])

            let region = MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
            )
            let visible = store.landmarks(in: region)
            XCTAssertEqual(visible.count, 2, "Both discovered and undiscovered landmarks should appear in region")
        }
    }

    // MARK: - Migration

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: LandmarkStore.wikidataMigrationKey)
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: LandmarkStore.wikidataMigrationKey)
    }

    func testMigrationDeletesOldStyleLandmarks() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            insertRawLandmark(id: "MKPOICategoryMuseum|40.779|-73.963", into: container)
            insertRawLandmark(id: "some-uuid-1234-5678", into: container)

            let store = LandmarkStore(container: container)
            XCTAssertEqual(store.allLandmarks.count, 0, "Old MapKit-style landmarks should be purged on first launch")
        }
    }

    func testMigrationPreservesWikidataLandmarks() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            insertRawLandmark(id: "Q12345", into: container)
            insertRawLandmark(id: "Q99", into: container)

            let store = LandmarkStore(container: container)
            XCTAssertEqual(store.allLandmarks.count, 2, "Wikidata landmarks should survive migration")
        }
    }

    func testMigrationDeletesOldButPreservesWikidata() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            insertRawLandmark(id: "MKPOICategoryStadium|40.0|-74.0", into: container)
            insertRawLandmark(id: "Q42", into: container)

            let store = LandmarkStore(container: container)
            XCTAssertEqual(store.allLandmarks.count, 1)
            XCTAssertEqual(store.allLandmarks.first?.identifier, "Q42")
        }
    }

    func testMigrationRunsOnlyOnce() async {
        await MainActor.run {
            let container = makeInMemoryContainer()

            // First init: migration runs, clears nothing (empty store).
            let _ = LandmarkStore(container: container)
            XCTAssertTrue(UserDefaults.standard.bool(forKey: LandmarkStore.wikidataMigrationKey),
                          "Migration flag should be set after first init")

            // Insert an old-style landmark after the migration flag is set.
            insertRawLandmark(id: "MKPOICategoryZoo|40.0|-74.0", into: container)

            // Second init: migration should NOT run again.
            let store2 = LandmarkStore(container: container)
            XCTAssertEqual(store2.allLandmarks.count, 1,
                           "Landmarks inserted after migration should not be purged on second init")
        }
    }

    func testMigrationFlagSetEvenWhenNoOldData() async {
        await MainActor.run {
            let _ = LandmarkStore(container: makeInMemoryContainer())
            XCTAssertTrue(UserDefaults.standard.bool(forKey: LandmarkStore.wikidataMigrationKey),
                          "Migration flag should be set even when there is nothing to delete")
        }
    }
}
