import XCTest
import CoreData
import MapKit
@testable import FogOfWalk

// NOTE: All test methods are `async` so they run inside a Swift Task. This is
// necessary on the iOS 26 beta simulator to avoid a Swift-runtime crash that
// occurs when a @MainActor @Observable object is deallocated from a non-Task
// XCTest context (swift_task_deinitOnExecutorImpl / TaskLocal heap corruption).

final class ExplorationStoreTests: XCTestCase {

    // MARK: - Helpers

    /// Returns a fresh NSPersistentContainer backed by an in-memory store.
    /// NSPersistentContainer(name:) finds the compiled model in the host-app
    /// bundle automatically when tests run inside the FogOfWalk host application.
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

    // MARK: - Tests

    func testAddCellReturnsTrueForNewCell() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)
            let result = store.addCell(CellID(x: 0, y: 0), cellSizeMeters: 50)
            XCTAssertTrue(result, "addCell should return true for a new cell")
        }
    }

    func testAddCellReturnsFalseForDuplicate() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)
            let cell = CellID(x: 1, y: 2)
            store.addCell(cell, cellSizeMeters: 50)
            let second = store.addCell(cell, cellSizeMeters: 50)
            XCTAssertFalse(second, "addCell should return false for a duplicate")
        }
    }

    func testAddCellUpdatesCacheAndCount() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)
            let cell = CellID(x: 5, y: 7)
            store.addCell(cell, cellSizeMeters: 50)
            XCTAssertTrue(store.visitedCellsCache.contains(cell))
            XCTAssertEqual(store.totalVisitedCount, 1)
        }
    }

    func testVisitedCellsInRegionReturnsOnlyIntersection() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)

            let nyc  = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            let cell = GridMath.cellID(for: nyc, cellSizeMeters: 50)
            let far  = CellID(x: cell.x + 1000, y: cell.y + 1000)

            store.addCell(cell, cellSizeMeters: 50)
            store.addCell(far,  cellSizeMeters: 50)

            let region  = MKCoordinateRegion(center: nyc, latitudinalMeters: 300,
                                             longitudinalMeters: 300)
            let visible = store.visitedCells(in: region, cellSizeMeters: 50)

            XCTAssertTrue(visible.contains(cell), "Nearby cell must be included")
            XCTAssertFalse(visible.contains(far), "Far cell must be excluded")
        }
    }

    func testVisitedCellsInRegionReturnsEmptyWhenNoneMatch() async {
        await MainActor.run {
            let store  = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)

            let sydney = CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)
            let nyc    = CLLocationCoordinate2D(latitude:  40.7128, longitude: -74.0060)

            store.addCell(GridMath.cellID(for: sydney, cellSizeMeters: 50), cellSizeMeters: 50)

            let region  = MKCoordinateRegion(center: nyc, latitudinalMeters: 300,
                                             longitudinalMeters: 300)
            let visible = store.visitedCells(in: region, cellSizeMeters: 50)

            XCTAssertTrue(visible.isEmpty, "Should return empty when no visited cells in region")
        }
    }

    func testDeleteAllCellsClearsEverything() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)
            store.addCell(CellID(x: 0, y: 0), cellSizeMeters: 50)
            store.addCell(CellID(x: 1, y: 1), cellSizeMeters: 50)
            XCTAssertEqual(store.totalVisitedCount, 2)

            store.deleteAllCells()

            XCTAssertEqual(store.totalVisitedCount, 0)
            XCTAssertTrue(store.visitedCellsCache.isEmpty)
        }
    }

    func testDifferentCellSizesAreIndependent() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            let cell  = CellID(x: 0, y: 0)

            store.configure(cellSizeMeters: 50)
            store.addCell(cell, cellSizeMeters: 50)
            XCTAssertEqual(store.totalVisitedCount, 1)

            // Switching to a different cell size must show an empty cache.
            store.configure(cellSizeMeters: 100)
            XCTAssertEqual(store.totalVisitedCount, 0,
                "100 m cache must not include cells stored under 50 m")
        }
    }

    func testIsVisitedReflectsCache() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)
            let cell  = CellID(x: 3, y: 4)
            XCTAssertFalse(store.isVisited(cell))
            store.addCell(cell, cellSizeMeters: 50)
            XCTAssertTrue(store.isVisited(cell))
        }
    }

    func testTotalCellCountAccountsForLongitudeScaling() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)

            // Cupertino: ~37.3°N. cos(37.3°) ≈ 0.795.
            // A circle at this latitude should contain more cells in longitude
            // than a naive (equatorial) calculation would suggest.
            let cupertino = CLLocationCoordinate2D(latitude: 37.3230, longitude: -122.0322)
            let radius: CLLocationDistance = 500
            let circle = CLCircularRegion(center: cupertino, radius: radius, identifier: "test")

            let total = store.totalCellCount(in: circle, cellSizeMeters: 50)

            // At the equator, the circle would be symmetric: roughly π*(500/50)² ≈ 314 cells.
            // At 37.3°N, cells are narrower in real meters (by cos(lat)), so more cells fit
            // in the east-west direction. The total should be ~314/cos(37.3°) ≈ 395.
            // Without the cos(lat) correction the denominator would be ~314, so assert > 340
            // to catch the regression.
            XCTAssertGreaterThan(total, 340,
                "totalCellCount must use cos(lat)-corrected longitude span; got \(total)")
        }
    }

    func testTotalCellCountSymmetricAtEquator() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)

            // At the equator, cos(0°)=1, so no longitude correction is needed.
            let equator = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
            let circle = CLCircularRegion(center: equator, radius: 500, identifier: "eq")

            let total = store.totalCellCount(in: circle, cellSizeMeters: 50)

            // π * (500/50)² ≈ 314. Allow a range for grid discretization.
            XCTAssertGreaterThan(total, 280, "Equator total too low: \(total)")
            XCTAssertLessThan(total, 350, "Equator total too high: \(total)")
        }
    }

    func testVisitedCellCountUsesGeodesicDistance() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)

            let cupertino = CLLocationCoordinate2D(latitude: 37.3230, longitude: -122.0322)
            let circle = CLCircularRegion(center: cupertino, radius: 500, identifier: "test")

            // Add a cell at the center — should be counted.
            let centerCell = GridMath.cellID(for: cupertino, cellSizeMeters: 50)
            store.addCell(centerCell, cellSizeMeters: 50)

            // Add a cell far away — should NOT be counted.
            let farCell = CellID(x: centerCell.x + 1000, y: centerCell.y + 1000)
            store.addCell(farCell, cellSizeMeters: 50)

            let visited = store.visitedCellCount(in: circle, cellSizeMeters: 50)
            XCTAssertEqual(visited, 1, "Only the nearby cell should be inside the circle")
        }
    }

    func testCityPercentageIsReasonable() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)

            let cupertino = CLLocationCoordinate2D(latitude: 37.3230, longitude: -122.0322)
            let circle = CLCircularRegion(center: cupertino, radius: 500, identifier: "test")

            // Add 12 cells near center.
            let baseCell = GridMath.cellID(for: cupertino, cellSizeMeters: 50)
            for dx in Int32(0)..<4 {
                for dy in Int32(0)..<3 {
                    store.addCell(CellID(x: baseCell.x + dx, y: baseCell.y + dy), cellSizeMeters: 50)
                }
            }

            let visited = store.visitedCellCount(in: circle, cellSizeMeters: 50)
            let total   = store.totalCellCount(in: circle, cellSizeMeters: 50)
            let percent = Double(visited) / Double(total)

            // 12 cells out of ~395 should be roughly 3%, definitely under 5%.
            XCTAssertLessThan(percent, 0.05,
                "12 cells in a 500m circle should be well under 5%, got \(percent * 100)%")
        }
    }

    // MARK: - onNewCell callback

    func testOnNewCellCallbackFiresForNewCell() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)

            var received: VisitedCell?
            store.onNewCell = { received = $0 }

            let cell = CellID(x: 10, y: 20)
            store.addCell(cell, cellSizeMeters: 50)

            XCTAssertNotNil(received, "onNewCell should fire for a new cell")
            XCTAssertEqual(received?.cellX, 10)
            XCTAssertEqual(received?.cellY, 20)
        }
    }

    func testOnNewCellCallbackNotFiredForDuplicate() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)

            var callCount = 0
            store.onNewCell = { _ in callCount += 1 }

            let cell = CellID(x: 1, y: 2)
            store.addCell(cell, cellSizeMeters: 50)
            store.addCell(cell, cellSizeMeters: 50)

            XCTAssertEqual(callCount, 1, "onNewCell should not fire for a duplicate")
        }
    }

    func testOnNewCellCallbackFiresEvenWhenSizeMismatchesCache() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)

            var received: VisitedCell?
            store.onNewCell = { received = $0 }

            // Add a cell under a different size than the active cache.
            store.addCell(CellID(x: 5, y: 5), cellSizeMeters: 100)

            XCTAssertNotNil(received,
                "onNewCell must fire for cells that don't match the active cache size")
            XCTAssertEqual(received?.cellSizeMeters, 100)
        }
    }

    // MARK: - Issue #3: cache consistency

    func testAddCellWithMismatchedSizeDoesNotCorruptCache() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)

            // Add a cell tagged as 100 m while the active cache is for 50 m.
            let result = store.addCell(CellID(x: 7, y: 8), cellSizeMeters: 100)

            XCTAssertTrue(result, "addCell should return true for a genuinely new cell")
            XCTAssertEqual(store.totalVisitedCount, 0,
                "50 m cache must not be contaminated by a 100 m cell")
            XCTAssertTrue(store.visitedCellsCache.isEmpty,
                "50 m cache must remain empty")

            // Switching to 100 m should reveal the persisted cell.
            store.configure(cellSizeMeters: 100)
            XCTAssertEqual(store.totalVisitedCount, 1,
                "100 m cache should contain the persisted cell")
        }
    }

    func testAddCellWithMismatchedSizeIsDeduplicated() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)

            let cell = CellID(x: 3, y: 3)
            let first  = store.addCell(cell, cellSizeMeters: 100)
            let second = store.addCell(cell, cellSizeMeters: 100)

            XCTAssertTrue(first,  "First insert should succeed")
            XCTAssertFalse(second, "Duplicate insert should return false even when size mismatches cache")
        }
    }

    // MARK: - Issue #4: delete/cache mismatch

    func testDeleteAllCellsPersistsDeletionToStore() async {
        let container = makeInMemoryContainer()

        await MainActor.run {
            let store1 = ExplorationStore(container: container)
            store1.configure(cellSizeMeters: 50)
            store1.addCell(CellID(x: 0, y: 0), cellSizeMeters: 50)
            store1.addCell(CellID(x: 1, y: 1), cellSizeMeters: 50)
            XCTAssertEqual(store1.totalVisitedCount, 2)
            store1.deleteAllCells()
            XCTAssertEqual(store1.totalVisitedCount, 0)
        }

        // A new instance on the same container must also see zero cells.
        await MainActor.run {
            let store2 = ExplorationStore(container: container)
            store2.configure(cellSizeMeters: 50)
            XCTAssertEqual(store2.totalVisitedCount, 0,
                "Deleted cells must not reappear in a new store instance")
            XCTAssertTrue(store2.visitedCellsCache.isEmpty)
        }
    }

    func testConfigureLoadsCacheFromCoreData() async {
        let container = makeInMemoryContainer()

        await MainActor.run {
            // Populate via one store instance.
            let store1 = ExplorationStore(container: container)
            store1.configure(cellSizeMeters: 50)
            store1.addCell(CellID(x: 0, y: 0), cellSizeMeters: 50)
            store1.addCell(CellID(x: 1, y: 0), cellSizeMeters: 50)
        }

        // New instance on the same container should load from Core Data.
        await MainActor.run {
            let store2 = ExplorationStore(container: container)
            XCTAssertEqual(store2.totalVisitedCount, 0, "Cache should be empty before configure()")
            store2.configure(cellSizeMeters: 50)
            XCTAssertEqual(store2.totalVisitedCount, 2, "Cache should be restored from Core Data")
        }
    }

    // MARK: - Recent cells

    func testLoadRecentCellsWithNilCutoffClearsCache() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)
            store.addCell(CellID(x: 0, y: 0), cellSizeMeters: 50)
            // Prime the cache with a non-nil cutoff first.
            store.loadRecentCells(since: Date.distantPast)
            XCTAssertFalse(store.recentCellsCache.isEmpty, "Should have recent cells")
            // Now clear with nil.
            store.loadRecentCells(since: nil)
            XCTAssertTrue(store.recentCellsCache.isEmpty,
                          "nil cutoff should clear recentCellsCache")
        }
    }

    func testLoadRecentCellsPopulatesFromCoreData() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)
            let cell = CellID(x: 3, y: 7)
            store.addCell(cell, cellSizeMeters: 50)
            // Load with a past cutoff that includes the just-added cell.
            store.loadRecentCells(since: Date.distantPast)
            XCTAssertTrue(store.recentCellsCache.contains(cell),
                          "Recently added cell should appear in recentCellsCache")
        }
    }

    func testLoadRecentCellsExcludesOldCells() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)
            store.addCell(CellID(x: 1, y: 1), cellSizeMeters: 50)
            // Use a cutoff in the far future — nothing should qualify.
            store.loadRecentCells(since: Date.distantFuture)
            XCTAssertTrue(store.recentCellsCache.isEmpty,
                          "Future cutoff should exclude all existing cells")
        }
    }

    func testAddCellUpdatesRecentCacheWhenActive() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)
            // Add a seed cell so loadRecentCells returns a non-empty set.
            store.addCell(CellID(x: 0, y: 0), cellSizeMeters: 50)
            store.loadRecentCells(since: Date.distantPast)
            XCTAssertFalse(store.recentCellsCache.isEmpty, "Seed cell should populate recent cache")
            // Now adding a new cell should also update the recent cache.
            let cell = CellID(x: 9, y: 9)
            store.addCell(cell, cellSizeMeters: 50)
            XCTAssertTrue(store.recentCellsCache.contains(cell),
                          "addCell should insert into recentCellsCache when it is non-empty")
        }
    }

    func testAddCellDoesNotPopulateRecentCacheWhenEmpty() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)
            // Do not call loadRecentCells — cache remains empty.
            let cell = CellID(x: 2, y: 2)
            store.addCell(cell, cellSizeMeters: 50)
            XCTAssertTrue(store.recentCellsCache.isEmpty,
                          "addCell should not populate recentCellsCache when highlight is off")
        }
    }

    func testDeleteAllCellsClearsRecentCache() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure(cellSizeMeters: 50)
            store.addCell(CellID(x: 0, y: 0), cellSizeMeters: 50)
            store.loadRecentCells(since: Date.distantPast)
            XCTAssertFalse(store.recentCellsCache.isEmpty)
            store.deleteAllCells()
            XCTAssertTrue(store.recentCellsCache.isEmpty,
                          "deleteAllCells should also clear recentCellsCache")
        }
    }
}
