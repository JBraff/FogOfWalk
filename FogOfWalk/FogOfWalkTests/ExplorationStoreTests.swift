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

    func testLoadErrorIsNilOnSuccess() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            XCTAssertNil(store.loadError, "loadError should be nil when Core Data loads successfully")
        }
    }

    func testAddCellReturnsTrueForNewCell() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()
            let result = store.addCell(CellID(x: 0, y: 0))
            XCTAssertTrue(result, "addCell should return true for a new cell")
        }
    }

    func testAddCellReturnsFalseForDuplicate() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()
            let cell = CellID(x: 1, y: 2)
            store.addCell(cell)
            let second = store.addCell(cell)
            XCTAssertFalse(second, "addCell should return false for a duplicate")
        }
    }

    func testAddCellUpdatesCacheAndCount() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()
            let cell = CellID(x: 5, y: 7)
            store.addCell(cell)
            XCTAssertTrue(store.visitedCellsCache.contains(cell))
            XCTAssertEqual(store.totalVisitedCount, 1)
        }
    }

    func testVisitedCellsInRegionReturnsOnlyIntersection() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()

            let nyc  = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
            let cell = GridMath.cellID(for: nyc)
            let far  = CellID(x: cell.x + 1000, y: cell.y + 1000)

            store.addCell(cell)
            store.addCell(far)

            let region  = MKCoordinateRegion(center: nyc, latitudinalMeters: 300,
                                             longitudinalMeters: 300)
            let visible = store.visitedCells(in: region)

            XCTAssertTrue(visible.contains(cell), "Nearby cell must be included")
            XCTAssertFalse(visible.contains(far), "Far cell must be excluded")
        }
    }

    func testVisitedCellsInRegionReturnsEmptyWhenNoneMatch() async {
        await MainActor.run {
            let store  = ExplorationStore(container: makeInMemoryContainer())
            store.configure()

            let sydney = CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)
            let nyc    = CLLocationCoordinate2D(latitude:  40.7128, longitude: -74.0060)

            store.addCell(GridMath.cellID(for: sydney))

            let region  = MKCoordinateRegion(center: nyc, latitudinalMeters: 300,
                                             longitudinalMeters: 300)
            let visible = store.visitedCells(in: region)

            XCTAssertTrue(visible.isEmpty, "Should return empty when no visited cells in region")
        }
    }

    func testDeleteAllCellsClearsEverything() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()
            store.addCell(CellID(x: 0, y: 0))
            store.addCell(CellID(x: 1, y: 1))
            XCTAssertEqual(store.totalVisitedCount, 2)

            store.deleteAllCells()

            XCTAssertEqual(store.totalVisitedCount, 0)
            XCTAssertTrue(store.visitedCellsCache.isEmpty)
        }
    }

    func testIsVisitedReflectsCache() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()
            let cell  = CellID(x: 3, y: 4)
            XCTAssertFalse(store.isVisited(cell))
            store.addCell(cell)
            XCTAssertTrue(store.isVisited(cell))
        }
    }

    func testTotalCellCountAccountsForLongitudeScaling() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()

            // Cupertino: ~37.3°N. cos(37.3°) ≈ 0.795.
            // A circle at this latitude should contain more cells in longitude
            // than a naive (equatorial) calculation would suggest.
            let cupertino = CLLocationCoordinate2D(latitude: 37.3230, longitude: -122.0322)
            let radius: CLLocationDistance = 500
            let circle = CLCircularRegion(center: cupertino, radius: radius, identifier: "test")

            let total = store.totalCellCount(in: circle)

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
            store.configure()

            // At the equator, cos(0°)=1, so no longitude correction is needed.
            let equator = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
            let circle = CLCircularRegion(center: equator, radius: 500, identifier: "eq")

            let total = store.totalCellCount(in: circle)

            // π * (500/50)² ≈ 314. Allow a range for grid discretization.
            XCTAssertGreaterThan(total, 280, "Equator total too low: \(total)")
            XCTAssertLessThan(total, 350, "Equator total too high: \(total)")
        }
    }

    func testVisitedCellCountUsesGeodesicDistance() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()

            let cupertino = CLLocationCoordinate2D(latitude: 37.3230, longitude: -122.0322)
            let circle = CLCircularRegion(center: cupertino, radius: 500, identifier: "test")

            // Add a cell at the center — should be counted.
            let centerCell = GridMath.cellID(for: cupertino)
            store.addCell(centerCell)

            // Add a cell far away — should NOT be counted.
            let farCell = CellID(x: centerCell.x + 1000, y: centerCell.y + 1000)
            store.addCell(farCell)

            let visited = store.visitedCellCount(in: circle)
            XCTAssertEqual(visited, 1, "Only the nearby cell should be inside the circle")
        }
    }

    func testCityPercentageIsReasonable() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()

            let cupertino = CLLocationCoordinate2D(latitude: 37.3230, longitude: -122.0322)
            let circle = CLCircularRegion(center: cupertino, radius: 500, identifier: "test")

            // Add 12 cells near center.
            let baseCell = GridMath.cellID(for: cupertino)
            for dx in Int32(0)..<4 {
                for dy in Int32(0)..<3 {
                    store.addCell(CellID(x: baseCell.x + dx, y: baseCell.y + dy))
                }
            }

            let visited = store.visitedCellCount(in: circle)
            let total   = store.totalCellCount(in: circle)
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
            store.configure()

            var received: VisitedCell?
            store.onNewCell = { received = $0 }

            let cell = CellID(x: 10, y: 20)
            store.addCell(cell)

            XCTAssertNotNil(received, "onNewCell should fire for a new cell")
            XCTAssertEqual(received?.cellX, 10)
            XCTAssertEqual(received?.cellY, 20)
        }
    }

    func testOnNewCellCallbackNotFiredForDuplicate() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()

            var callCount = 0
            store.onNewCell = { _ in callCount += 1 }

            let cell = CellID(x: 1, y: 2)
            store.addCell(cell)
            store.addCell(cell)

            XCTAssertEqual(callCount, 1, "onNewCell should not fire for a duplicate")
        }
    }

    // MARK: - Issue #4: delete/cache mismatch

    func testDeleteAllCellsPersistsDeletionToStore() async {
        let container = makeInMemoryContainer()

        await MainActor.run {
            let store1 = ExplorationStore(container: container)
            store1.configure()
            store1.addCell(CellID(x: 0, y: 0))
            store1.addCell(CellID(x: 1, y: 1))
            XCTAssertEqual(store1.totalVisitedCount, 2)
            store1.deleteAllCells()
            XCTAssertEqual(store1.totalVisitedCount, 0)
        }

        // A new instance on the same container must also see zero cells.
        await MainActor.run {
            let store2 = ExplorationStore(container: container)
            store2.configure()
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
            store1.configure()
            store1.addCell(CellID(x: 0, y: 0))
            store1.addCell(CellID(x: 1, y: 0))
        }

        // New instance on the same container should load from Core Data.
        await MainActor.run {
            let store2 = ExplorationStore(container: container)
            XCTAssertEqual(store2.totalVisitedCount, 0, "Cache should be empty before configure()")
            store2.configure()
            XCTAssertEqual(store2.totalVisitedCount, 2, "Cache should be restored from Core Data")
        }
    }

    // MARK: - Recent cells

    func testLoadRecentCellsWithNilCutoffClearsCache() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()
            store.addCell(CellID(x: 0, y: 0))
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
            store.configure()
            let cell = CellID(x: 3, y: 7)
            store.addCell(cell)
            // Load with a past cutoff that includes the just-added cell.
            store.loadRecentCells(since: Date.distantPast)
            XCTAssertTrue(store.recentCellsCache.contains(cell),
                          "Recently added cell should appear in recentCellsCache")
        }
    }

    func testLoadRecentCellsExcludesOldCells() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()
            store.addCell(CellID(x: 1, y: 1))
            // Use a cutoff in the far future — nothing should qualify.
            store.loadRecentCells(since: Date.distantFuture)
            XCTAssertTrue(store.recentCellsCache.isEmpty,
                          "Future cutoff should exclude all existing cells")
        }
    }

    func testAddCellUpdatesRecentCacheWhenActive() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()
            // Add a seed cell so loadRecentCells returns a non-empty set.
            store.addCell(CellID(x: 0, y: 0))
            store.loadRecentCells(since: Date.distantPast)
            XCTAssertFalse(store.recentCellsCache.isEmpty, "Seed cell should populate recent cache")
            // Now adding a new cell should also update the recent cache.
            let cell = CellID(x: 9, y: 9)
            store.addCell(cell)
            XCTAssertTrue(store.recentCellsCache.contains(cell),
                          "addCell should insert into recentCellsCache when it is non-empty")
        }
    }

    func testAddCellDoesNotPopulateRecentCacheWhenEmpty() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()
            // Do not call loadRecentCells — cache remains empty.
            let cell = CellID(x: 2, y: 2)
            store.addCell(cell)
            XCTAssertTrue(store.recentCellsCache.isEmpty,
                          "addCell should not populate recentCellsCache when highlight is off")
        }
    }

    /// Regression test for the isHighlightActive bug: before the fix, addCell checked
    /// `recentCellsCache.isEmpty` instead of `isHighlightActive`, so cells walked early
    /// in the day (before any cells matched the cutoff) were never added to recentCellsCache.
    func testAddCellUpdatesRecentCacheWhenActiveButInitiallyEmpty() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()
            // Enable highlight for today — cache starts empty (no cells walked yet today).
            store.loadRecentCells(since: Calendar.current.startOfDay(for: Date()))
            XCTAssertTrue(store.recentCellsCache.isEmpty,
                          "Cache starts empty with no cells walked today")
            // Walk a new cell — it should be added to recentCellsCache because isHighlightActive is true.
            let cell = CellID(x: 9, y: 9)
            store.addCell(cell)
            XCTAssertTrue(store.recentCellsCache.contains(cell),
                          "addCell should insert into recentCellsCache when highlight is active, even if cache was initially empty")
        }
    }

    func testRecentCellsGenerationIncrementsOnLoadRecentCells() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()
            let gen0 = store.recentCellsGeneration
            store.loadRecentCells(since: Date.distantPast)
            XCTAssertGreaterThan(store.recentCellsGeneration, gen0,
                                 "recentCellsGeneration should increment after loadRecentCells with a date")
            let gen1 = store.recentCellsGeneration
            store.loadRecentCells(since: nil)
            XCTAssertGreaterThan(store.recentCellsGeneration, gen1,
                                 "recentCellsGeneration should increment even when clearing via nil cutoff")
        }
    }

    func testRecentCellsGenerationIncrementsOnDeleteAll() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()
            store.addCell(CellID(x: 0, y: 0))
            store.loadRecentCells(since: Date.distantPast)
            let gen = store.recentCellsGeneration
            store.deleteAllCells()
            XCTAssertGreaterThan(store.recentCellsGeneration, gen,
                                 "recentCellsGeneration should increment on deleteAllCells")
        }
    }

    // MARK: - Today count

    func testTodayVisitedCountStartsAtZero() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()
            XCTAssertEqual(store.todayVisitedCount, 0)
        }
    }

    func testAddCellIncrementsTodayCount() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()
            store.addCell(CellID(x: 0, y: 0))
            store.addCell(CellID(x: 1, y: 0))
            XCTAssertEqual(store.todayVisitedCount, 2)
        }
    }

    func testAddCellDoesNotIncrementTodayCountForDuplicate() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()
            let cell = CellID(x: 0, y: 0)
            store.addCell(cell)
            store.addCell(cell)
            XCTAssertEqual(store.todayVisitedCount, 1)
        }
    }

    func testDeleteAllCellsResetsTodayCount() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()
            store.addCell(CellID(x: 0, y: 0))
            XCTAssertEqual(store.todayVisitedCount, 1)
            store.deleteAllCells()
            XCTAssertEqual(store.todayVisitedCount, 0)
        }
    }

    func testConfigureLoadsTodayCountFromCoreData() async {
        let container = makeInMemoryContainer()

        await MainActor.run {
            let store1 = ExplorationStore(container: container)
            store1.configure()
            store1.addCell(CellID(x: 0, y: 0))
            store1.addCell(CellID(x: 1, y: 0))
        }

        await MainActor.run {
            let store2 = ExplorationStore(container: container)
            store2.configure()
            XCTAssertEqual(store2.todayVisitedCount, 2,
                "todayVisitedCount should be restored from Core Data on configure()")
        }
    }

    // MARK: - Day rollover

    func testTodayCountResetsAfterDayChange() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            let day1 = Calendar.current.startOfDay(for: Date())
            store.nowProvider = { day1 }
            store.configure()
            store.addCell(CellID(x: 0, y: 0))
            store.addCell(CellID(x: 1, y: 0))
            XCTAssertEqual(store.todayVisitedCount, 2)

            let day2 = Calendar.current.date(byAdding: .day, value: 1, to: day1)!
            store.nowProvider = { day2 }
            let rolled = store.refreshForDayChangeIfNeeded()

            XCTAssertTrue(rolled, "refreshForDayChangeIfNeeded should report a rollover")
            XCTAssertEqual(store.todayVisitedCount, 0, "today count should reset on day change")
            XCTAssertEqual(store.totalVisitedCount, 2, "total count must be unaffected by rollover")
        }
    }

    func testAddCellAfterDayChangeCountsOnlyNewDay() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            let day1 = Calendar.current.startOfDay(for: Date())
            store.nowProvider = { day1 }
            store.configure()
            store.addCell(CellID(x: 0, y: 0))

            let day2 = Calendar.current.date(byAdding: .day, value: 1, to: day1)!
            store.nowProvider = { day2 }
            store.refreshForDayChangeIfNeeded()

            store.addCell(CellID(x: 5, y: 5))
            XCTAssertEqual(store.todayVisitedCount, 1,
                "only the cell added after rollover should count toward the new day")
        }
    }

    func testHighlightCacheRebuiltAfterDayChange() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            let day1 = Calendar.current.startOfDay(for: Date())
            store.nowProvider = { day1 }
            store.configure()
            store.loadRecentCells(since: day1)
            store.addCell(CellID(x: 0, y: 0))
            XCTAssertFalse(store.recentCellsCache.isEmpty)

            let priorGeneration = store.recentCellsGeneration
            let day2 = Calendar.current.date(byAdding: .day, value: 1, to: day1)!
            store.nowProvider = { day2 }
            store.refreshForDayChangeIfNeeded()

            XCTAssertTrue(store.recentCellsCache.isEmpty,
                "yesterday's cells must not remain in the highlight cache")
            XCTAssertEqual(store.recentCellsGeneration, priorGeneration &+ 1,
                "highlight rebuild should advance the generation exactly once")
        }
    }

    func testRefreshForDayChangeIsNoOpWithinSameDay() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            let day1 = Calendar.current.startOfDay(for: Date())
            store.nowProvider = { day1 }
            store.configure()
            store.addCell(CellID(x: 0, y: 0))

            let countBefore = store.todayVisitedCount
            let generationBefore = store.recentCellsGeneration
            let rolled = store.refreshForDayChangeIfNeeded()

            XCTAssertFalse(rolled, "no rollover should be reported within the same day")
            XCTAssertEqual(store.todayVisitedCount, countBefore)
            XCTAssertEqual(store.recentCellsGeneration, generationBefore)
        }
    }

    func testHighlightNotArmedIsNotRebuiltOnDayChange() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            let day1 = Calendar.current.startOfDay(for: Date())
            store.nowProvider = { day1 }
            store.configure()
            store.addCell(CellID(x: 0, y: 0))
            // Never arm the highlight — recentCellsCache stays empty and inactive.

            let day2 = Calendar.current.date(byAdding: .day, value: 1, to: day1)!
            store.nowProvider = { day2 }
            store.refreshForDayChangeIfNeeded()

            XCTAssertTrue(store.recentCellsCache.isEmpty,
                "a disarmed highlight must not be armed by a day change")
        }
    }

    func testDeleteAllCellsClearsRecentCache() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()
            store.addCell(CellID(x: 0, y: 0))
            store.loadRecentCells(since: Date.distantPast)
            XCTAssertFalse(store.recentCellsCache.isEmpty)
            store.deleteAllCells()
            XCTAssertTrue(store.recentCellsCache.isEmpty,
                          "deleteAllCells should also clear recentCellsCache")
        }
    }
}
