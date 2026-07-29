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

    /// Inserts landmarks with an empty visited set, for tests that are not about discovery.
    ///
    /// `addLandmarks` requires `visitedCells` so no production call site can silently drop
    /// discoveries. This helper is the one place where passing `[]` is deliberate — tests that
    /// do care about the interaction call `addLandmarks` directly with a real set.
    @MainActor
    func seed(_ store: LandmarkStore, _ items: [WikidataLandmark]) {
        store.addLandmarks(items, visitedCells: [])
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

            seed(store, [item])
            seed(store, [item])

            XCTAssertEqual(store.allLandmarks.count, 1, "Duplicate landmark should not be inserted twice")
        }
    }

    func testAddLandmarksStoresCorrectAttributes() async {
        await MainActor.run {
            let store = makeStore()
            let item  = makeWikidataLandmark(id: "Q42", name: "Museum of Art",
                                             lat: 34.0, lon: -118.0, category: "museum")

            seed(store, [item])

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
            seed(store, items)
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
                seed(store, [item])
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
            seed(store, [makeWikidataLandmark(category: "unknownType")])
            XCTAssertEqual(store.allLandmarks.first?.discoveryRadiusMeters, 100)
        }
    }

    // MARK: - checkDiscovery

    func testCheckDiscoveryWithinRadius() async {
        await MainActor.run {
            let store    = makeStore()
            let coord    = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            seed(store, [makeWikidataLandmark(id: "Q10", name: "Famous Landmark",
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
            let landmarkCoord = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            seed(store, [makeWikidataLandmark(lat: landmarkCoord.latitude,
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
            let coord    = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            seed(store, [makeWikidataLandmark(lat: coord.latitude, lon: coord.longitude)])

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
            let airportCoord = CLLocationCoordinate2D(latitude: 40.6413, longitude: -73.7781)
            seed(store, [makeWikidataLandmark(id: "QJFK", name: "JFK Airport",
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
            let coord    = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            seed(store, [makeWikidataLandmark(id: "QPERF", lat: coord.latitude,
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
            let coord    = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)

            seed(store, [
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
            let coord    = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            seed(store, [makeWikidataLandmark(lat: coord.latitude, lon: coord.longitude)])

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
            seed(store1, [makeWikidataLandmark(id: "QPERSIST", lat: coord.latitude, lon: coord.longitude)])
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
            seed(store, [
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
            let coord    = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)

            seed(store, [
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

    // MARK: - Hot path: checkDiscovery(newCell:)

    func testCheckDiscoveryWithNewCellOnly() async {
        // The signature is the assertion: with no visited-set parameter, this entry point
        // *structurally* cannot scan the visited set, however much the user has explored.
        await MainActor.run {
            let store = makeStore()
            let coord = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            seed(store, [makeWikidataLandmark(id: "QNEW", lat: coord.latitude,
                                              lon: coord.longitude, category: "landmark")])

            let discovered = store.checkDiscovery(newCell: GridMath.cellID(for: coord))

            XCTAssertEqual(discovered.count, 1)
            XCTAssertEqual(store.totalDiscovered, 1)
        }
    }

    func testCheckDiscoveryWithNewCellIgnoresFarLandmarks() async {
        await MainActor.run {
            let store = makeStore()
            let here  = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            seed(store, [makeWikidataLandmark(id: "QFAR", lat: 51.5074, lon: -0.1278)])

            XCTAssertEqual(store.checkDiscovery(newCell: GridMath.cellID(for: here)).count, 0)
        }
    }

    func testCheckDiscoveryWithNewCellFindsMaxRadiusLandmark() async {
        // The bucket search must use the largest radius across all categories, not the radius
        // of whatever it happens to find — in this direction a candidate's radius is unknown
        // until it has been found. An airport at 430 m is only reachable if it does.
        await MainActor.run {
            let store   = makeStore()
            let airport = CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0)
            seed(store, [makeWikidataLandmark(id: "QAIR", lat: airport.latitude,
                                              lon: airport.longitude, category: "airport")])

            let cell = cellDueEast(of: airport, meters: 430)
            XCTAssertEqual(store.checkDiscovery(newCell: cell).count, 1)
        }
    }

    func testDiscoveryProbeCountDoesNotGrowWithVisitedCellCount() async {
        // The real complexity test. No purely behavioural assertion can catch a complexity
        // bug, because the slow implementation produced the correct answer too — so this
        // counts the work instead. An upper bound rather than equality, so a later early-exit
        // optimisation doesn't break it.
        await MainActor.run {
            let coord  = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            let target = GridMath.cellID(for: coord)

            for cellCount in [10, 10_000] {
                let store = makeStore()
                seed(store, [makeWikidataLandmark(id: "QPROBE", lat: coord.latitude,
                                                  lon: coord.longitude, category: "airport")])

                var cells: Set<CellID> = [target]
                for i in 1..<cellCount {
                    cells.insert(CellID(x: target.x + Int32(i) * 137,
                                        y: target.y + Int32(i) * 149))
                }

                // Bound derived from the box rather than hardcoded, so it stays meaningful if
                // kCellSizeMeters changes. An upper bound, not equality.
                let box = GridMath.cellBox(around: coord, radiusMeters: 500)
                let boxSize = (Int(box.maxX) - Int(box.minX) + 1) * (Int(box.maxY) - Int(box.minY) + 1)

                XCTAssertEqual(store.checkDiscovery(visitedCells: cells).count, 1,
                               "Discovery must still succeed with \(cellCount) visited cells")
                XCTAssertLessThanOrEqual(
                    store.lastDiscoveryProbeCount, boxSize,
                    """
                    Probe count must be bounded by the discovery radius (\(boxSize) cells), \
                    not by the \(cellCount) visited cells. \
                    Got \(store.lastDiscoveryProbeCount).
                    """
                )
            }
        }
    }

    func testSweepProbeCountDoesNotGrowWithLandmarkCount() async {
        // Companion to the test above, guarding the other axis. That one pins cost against the
        // visited-set size (the direction-pick inside isWithinVisitedCells); this one pins it
        // against the *landmark* count, which is what the bucket prefilter buys. Without the
        // prefilter every undiscovered landmark bbox-probes, so 2,000 landmarks far from any
        // walked ground cost ~2,000 x box-size probes instead of a few Set lookups each.
        await MainActor.run {
            let store  = makeStore()
            let coord  = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            let target = GridMath.cellID(for: coord)

            var items = [makeWikidataLandmark(id: "QNEAR", lat: coord.latitude,
                                              lon: coord.longitude, category: "airport")]
            // 2,000 airports in distinct buckets, all well clear of the visited region below
            // (which spans ~5 km) and inside real longitudes.
            for i in 1...2_000 {
                items.append(makeWikidataLandmark(id: "QFAR\(i)",
                                                  lat: coord.latitude,
                                                  lon: coord.longitude + 20.0 + Double(i) * 0.05,
                                                  category: "airport"))
            }
            seed(store, items)

            var cells: Set<CellID> = [target]
            for i in 1..<10_000 {
                cells.insert(CellID(x: target.x + Int32(i % 100), y: target.y + Int32(i / 100)))
            }

            XCTAssertEqual(store.checkDiscovery(visitedCells: cells).count, 1,
                           "Only the nearby landmark should be discovered")
            XCTAssertLessThanOrEqual(
                store.lastDiscoveryProbeCount, 2_000,
                """
                Probe count must be bounded by the landmarks near walked ground, not by all \
                2,001 undiscovered ones. Got \(store.lastDiscoveryProbeCount).
                """
            )
        }
    }

    // MARK: - Compensating sweeps

    func testLandmarkAddedAfterCellWasWalkedIsDiscovered() async {
        // Walk first, ingest second. Only the insert sweep can catch this — the cell will never
        // be "new" again, so `checkDiscovery(newCell:)` will never see it.
        //
        // Note this does NOT guard against `visitedCells` regaining a default: it passes the
        // argument explicitly, so a re-added `= []` would leave it green. Nothing structural
        // protects that; the required parameter is the protection.
        await MainActor.run {
            let store = makeStore()
            let coord = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            let cell  = GridMath.cellID(for: coord)

            store.addLandmarks(
                [makeWikidataLandmark(id: "QLATE", lat: coord.latitude, lon: coord.longitude)],
                visitedCells: [cell]
            )

            XCTAssertEqual(store.totalDiscovered, 1,
                           "A landmark ingested onto already-walked ground must be discovered")
            XCTAssertTrue(store.allLandmarks.first?.isDiscovered ?? false)
        }
    }

    func testDiscoveryRecoveredOnNextLaunchSweep() async {
        // Simulates the rollback gap: isDiscovered reverted in Core Data while its cell stays
        // in the visited set. Without an unconditional launch sweep that discovery is lost
        // forever, because the cell will never be new again.
        let container = makeInMemoryContainer()
        let coord = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        let cell  = GridMath.cellID(for: coord)

        await MainActor.run {
            let store = LandmarkStore(container: container)
            store.addLandmarks(
                [makeWikidataLandmark(id: "QHEAL", lat: coord.latitude, lon: coord.longitude)],
                visitedCells: [cell]
            )
            XCTAssertEqual(store.totalDiscovered, 1)

            // Revert directly in Core Data, behind the store's back.
            store.allLandmarks.first?.isDiscovered = false
            try? container.viewContext.save()
        }

        await MainActor.run {
            let store = LandmarkStore(container: container)
            XCTAssertEqual(store.totalDiscovered, 0, "Precondition: the revert took effect")

            store.sweepAllUndiscovered(visitedCells: [cell])

            XCTAssertEqual(store.totalDiscovered, 1,
                           "The launch sweep must recover a rolled-back discovery")
        }
    }

    func testBucketIndexUpdatedWhenLandmarkBecomesDiscovered() async {
        // Two landmarks in the same bucket, discovered from two different cells. Guards the
        // index-mutation bugs the bucket index introduces: if removing the first corrupted the
        // bucket, the second would become undiscoverable.
        await MainActor.run {
            let store = makeStore()
            // ~500 m apart: far enough that each needs its own cell (100 m museum radius),
            // close enough to share a bucket (32 cells ≈ 1600 m).
            let a = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            let b = CLLocationCoordinate2D(latitude: 40.7173, longitude: -74.0060)
            XCTAssertEqual(LandmarkStore.bucket(for: GridMath.cellID(for: a)),
                           LandmarkStore.bucket(for: GridMath.cellID(for: b)),
                           "Fixture must share a bucket, or this stops testing index mutation")
            seed(store, [
                makeWikidataLandmark(id: "QA", lat: a.latitude, lon: a.longitude),
                makeWikidataLandmark(id: "QB", lat: b.latitude, lon: b.longitude),
            ])

            XCTAssertEqual(store.checkDiscovery(newCell: GridMath.cellID(for: a)).count, 1)
            XCTAssertEqual(store.checkDiscovery(newCell: GridMath.cellID(for: b)).count, 1,
                           "The second landmark must still be reachable after the first left the index")
            XCTAssertEqual(store.totalDiscovered, 2)

            XCTAssertEqual(store.checkDiscovery(newCell: GridMath.cellID(for: a)).count, 0,
                           "An already-discovered landmark must not be rediscovered")
        }
    }

    // MARK: - Discovery direction symmetry (cos-latitude bbox)

    /// Cell whose *centre* lies approximately `meters` due east of `coord`.
    private func cellDueEast(of coord: CLLocationCoordinate2D, meters: Double) -> CellID {
        let cosLat = cos(coord.latitude * .pi / 180.0)
        let lon    = coord.longitude + meters / (GridMath.metersPerDegree * cosLat)
        return GridMath.cellID(for: CLLocationCoordinate2D(latitude: coord.latitude,
                                                           longitude: lon))
    }

    /// Equirectangular distance from `coord` to the centre of `cell`, in metres.
    private func metersFromCoord(_ coord: CLLocationCoordinate2D, toCentreOf cell: CellID) -> Double {
        let centre = GridMath.center(for: cell)
        let cosLat = cos(coord.latitude * .pi / 180.0)
        let dLat = (centre.latitude  - coord.latitude)  * GridMath.metersPerDegree
        let dLon = (centre.longitude - coord.longitude) * GridMath.metersPerDegree * cosLat
        return (dLat * dLat + dLon * dLon).squareRoot()
    }

    func testAirportDiscoveredDueEastAtHighLatitude() async {
        // Regression test for the missing cos(latitude) correction in the discovery bbox.
        // Longitude degrees are half as long at 60°N, so a cell 430 m due east sits at
        // Δlon 7.74e-3° while the old, uncorrected bbox was only 4.95e-3° wide — the cell was
        // filtered out before the precise check ever ran. Walking north of this airport
        // discovered it; walking the same distance east did not.
        await MainActor.run {
            let store   = makeStore()
            let airport = CLLocationCoordinate2D(latitude: 60.0, longitude: 10.0)
            seed(store, [makeWikidataLandmark(id: "QNORTH", name: "Oslo Airport",
                                                     lat: airport.latitude,
                                                     lon: airport.longitude,
                                                     category: "airport")])

            let cell = cellDueEast(of: airport, meters: 430)
            XCTAssertLessThan(metersFromCoord(airport, toCentreOf: cell), 500,
                              "Fixture must genuinely be inside the 500 m radius")

            XCTAssertEqual(store.checkDiscovery(visitedCells: [cell]).count, 1,
                           "Discovery must work due east, not just due north")
        }
    }

    func testAirportDiscoveredDueNorthAtHighLatitude() async {
        // The direction that already worked. Paired with the east case so the two together
        // document the asymmetry and pin the fix.
        await MainActor.run {
            let store   = makeStore()
            let airport = CLLocationCoordinate2D(latitude: 60.0, longitude: 10.0)
            seed(store, [makeWikidataLandmark(id: "QNORTH", name: "Oslo Airport",
                                                     lat: airport.latitude,
                                                     lon: airport.longitude,
                                                     category: "airport")])

            let north = CLLocationCoordinate2D(
                latitude: airport.latitude + 430 / GridMath.metersPerDegree,
                longitude: airport.longitude
            )
            let cell = GridMath.cellID(for: north)
            XCTAssertEqual(store.checkDiscovery(visitedCells: [cell]).count, 1)
        }
    }

    func testAirportNotDiscoveredJustOutsideRadiusDueEast() async {
        // Guards the *far* edge of the widened bbox. The cos correction makes the box up to
        // 5x wider at high latitude, and from here on only the precise distance check stops
        // over-discovery. This test deliberately picks a cell that IS inside the bbox but
        // outside the radius, so it fails if anyone ever trusts the box alone.
        await MainActor.run {
            let store   = makeStore()
            let airport = CLLocationCoordinate2D(latitude: 60.0, longitude: 10.0)
            seed(store, [makeWikidataLandmark(id: "QNORTH", name: "Oslo Airport",
                                                     lat: airport.latitude,
                                                     lon: airport.longitude,
                                                     category: "airport")])

            // Walk east one cell at a time until the centre passes 500 m. The bbox pads by a
            // full cell, so the first such cell is still inside it.
            let box = GridMath.cellBox(around: airport, radiusMeters: 500)
            var cell = GridMath.cellID(for: airport)
            while metersFromCoord(airport, toCentreOf: cell) <= 500 {
                cell = CellID(x: cell.x + 1, y: cell.y)
            }
            XCTAssertLessThanOrEqual(cell.x, box.maxX,
                "Fixture must sit inside the bbox, or this tests the box instead of the check")

            XCTAssertEqual(store.checkDiscovery(visitedCells: [cell]).count, 0,
                           "A cell inside the bbox but beyond the radius must not discover")
        }
    }

    func testDiscoveryUnaffectedByVisitedSetSize() async {
        // Both branches of isWithinVisitedCells (probe-the-box vs iterate-the-set) must agree.
        // A tiny set takes the iterate branch; a large one takes the probe branch.
        await MainActor.run {
            let airport = CLLocationCoordinate2D(latitude: 60.0, longitude: 10.0)
            let target  = cellDueEast(of: airport, meters: 430)

            for extraCells in [0, 5_000] {
                let store = makeStore()
                seed(store, [makeWikidataLandmark(id: "QNORTH", lat: airport.latitude,
                                                         lon: airport.longitude,
                                                         category: "airport")])
                var cells: Set<CellID> = [target]
                for i in 0..<extraCells {
                    cells.insert(CellID(x: target.x + Int32(i + 1) * 500,
                                        y: target.y + Int32(i + 1) * 500))
                }
                XCTAssertEqual(store.checkDiscovery(visitedCells: cells).count, 1,
                               "Discovery must be identical with \(extraCells) far-away cells")
            }
        }
    }

    // MARK: - landmarks(in:limit:)

    func testLandmarksInRegionRespectsLimit() async {
        await MainActor.run {
            let store = makeStore()
            let items = (0..<50).map { i in
                makeWikidataLandmark(id: "Q\(i)", lat: 40.0 + Double(i) * 0.0001, lon: -74.0)
            }
            seed(store, items)

            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0),
                span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
            )
            XCTAssertEqual(store.landmarks(in: region).count, 50,
                           "Under the limit, every visible landmark is returned")
            XCTAssertEqual(store.landmarks(in: region, limit: 10).count, 10,
                           "Pin array must be capped so the overlay's per-frame scan is bounded")
        }
    }

    func testLandmarksInRegionLimitPrefersDiscovered() async {
        await MainActor.run {
            let store = makeStore()
            let coord = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)

            // One landmark exactly on the visited cell, plus 20 undiscovered neighbours.
            var items = [makeWikidataLandmark(id: "QDISCOVERED",
                                              lat: coord.latitude, lon: coord.longitude)]
            items += (0..<20).map { i in
                makeWikidataLandmark(id: "QHINT\(i)",
                                     lat: coord.latitude + 0.01 + Double(i) * 0.001,
                                     lon: coord.longitude)
            }
            seed(store, items)
            store.checkDiscovery(visitedCells: [GridMath.cellID(for: coord)])
            XCTAssertEqual(store.totalDiscovered, 1)

            let region = MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
            )
            let capped = store.landmarks(in: region, limit: 3)
            XCTAssertEqual(capped.count, 3)
            XCTAssertTrue(capped.contains { $0.identifier == "QDISCOVERED" },
                          "Discovered pins are labelled and tappable — they must survive the cap")
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
