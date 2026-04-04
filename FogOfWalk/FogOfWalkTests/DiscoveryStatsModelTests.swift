import XCTest
import CoreData
import CoreLocation
import MapKit
@testable import FogOfWalk

final class DiscoveryStatsModelTests: XCTestCase {

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

    /// Insert a VisitedCell with a specific firstVisited date and optional locality.
    @discardableResult
    func insertCell(
        in ctx: NSManagedObjectContext,
        x: Int32 = 0, y: Int32 = 0,
        cellSizeMeters: Double = 50,
        firstVisited: Date,
        locality: String? = nil
    ) -> VisitedCell {
        let cell = VisitedCell(context: ctx)
        cell.cellX          = x
        cell.cellY          = y
        cell.cellSizeMeters = cellSizeMeters
        cell.firstVisited   = firstVisited
        cell.locality       = locality
        try! ctx.save()
        return cell
    }

    // MARK: - Empty state

    func testEmptyDataProducesZeros() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let model     = DiscoveryStatsModel()
            model.refresh(context: container.viewContext, cellSizeMeters: 50)

            XCTAssertEqual(model.last24HourCount, 0)
            XCTAssertEqual(model.last7DaysByDay.count, 7)
            XCTAssertTrue(model.last7DaysByLocality.isEmpty)
            XCTAssertEqual(model.allTimeTotal, 0)
            XCTAssertNil(model.firstWalkDate)
            XCTAssertEqual(model.bestDayCount, 0)
            XCTAssertNil(model.bestDayDate)
        }
    }

    // MARK: - All-time total

    func testAllTimeTotalCountsAllCells() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now)
            insertCell(in: ctx, x: 1, y: 0, firstVisited: now.addingTimeInterval(-100000))
            insertCell(in: ctx, x: 2, y: 0, firstVisited: now.addingTimeInterval(-1000000))

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            XCTAssertEqual(model.allTimeTotal, 3)
        }
    }

    func testAllTimeTotalFiltersOnCellSize() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            insertCell(in: ctx, x: 0, y: 0, cellSizeMeters: 50, firstVisited: now)
            insertCell(in: ctx, x: 1, y: 0, cellSizeMeters: 100, firstVisited: now)

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            XCTAssertEqual(model.allTimeTotal, 1, "Should only count cells for the requested cell size")
        }
    }

    // MARK: - First walk

    func testFirstWalkDateIsEarliestCell() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()
            let oldest    = now.addingTimeInterval(-500000)

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now)
            insertCell(in: ctx, x: 1, y: 0, firstVisited: oldest)

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            XCTAssertEqual(model.firstWalkDate?.timeIntervalSinceReferenceDate ?? 0,
                           oldest.timeIntervalSinceReferenceDate,
                           accuracy: 1)
        }
    }

    // MARK: - Best day

    func testBestDayDetection() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let calendar  = Calendar.current

            // Today: 1 cell
            let today = Date()
            insertCell(in: ctx, x: 0, y: 0, firstVisited: today)

            // Two days ago: 3 cells
            let twoDaysAgo = today.addingTimeInterval(-2 * 86400)
            insertCell(in: ctx, x: 1, y: 0, firstVisited: twoDaysAgo)
            insertCell(in: ctx, x: 2, y: 0, firstVisited: twoDaysAgo)
            insertCell(in: ctx, x: 3, y: 0, firstVisited: twoDaysAgo)

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            XCTAssertEqual(model.bestDayCount, 3)
            XCTAssertNotNil(model.bestDayDate)
            let bestDay = calendar.startOfDay(for: twoDaysAgo)
            XCTAssertEqual(model.bestDayDate?.timeIntervalSinceReferenceDate ?? 0,
                           bestDay.timeIntervalSinceReferenceDate,
                           accuracy: 1)
        }
    }

    // MARK: - Last 24 hours

    func testLast24HourCountIncludesRecentCells() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now.addingTimeInterval(-3600))    // 1 h ago — in
            insertCell(in: ctx, x: 1, y: 0, firstVisited: now.addingTimeInterval(-86401))  // just over 24 h — out
            insertCell(in: ctx, x: 2, y: 0, firstVisited: now.addingTimeInterval(-43200))  // 12 h ago — in

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            XCTAssertEqual(model.last24HourCount, 2)
        }
    }

    // MARK: - 7-day chart

    func testLast7DaysByDayAlwaysHas7Entries() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let model     = DiscoveryStatsModel()
            model.refresh(context: container.viewContext, cellSizeMeters: 50)

            XCTAssertEqual(model.last7DaysByDay.count, 7)
        }
    }

    func testLast7DaysByDayCountsCorrectly() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            // 3 cells today
            insertCell(in: ctx, x: 0, y: 0, firstVisited: now)
            insertCell(in: ctx, x: 1, y: 0, firstVisited: now.addingTimeInterval(-1800))
            insertCell(in: ctx, x: 2, y: 0, firstVisited: now.addingTimeInterval(-3600))

            // 1 cell 3 days ago
            insertCell(in: ctx, x: 3, y: 0, firstVisited: now.addingTimeInterval(-3 * 86400))

            // 1 cell 8 days ago — outside 7-day window
            insertCell(in: ctx, x: 4, y: 0, firstVisited: now.addingTimeInterval(-8 * 86400))

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            XCTAssertEqual(model.last7DaysByDay.count, 7)
            let todayEntry = model.last7DaysByDay.last
            XCTAssertEqual(todayEntry?.count, 3, "Today should have 3 cells")
            let total = model.last7DaysByDay.reduce(0) { $0 + $1.count }
            XCTAssertEqual(total, 4, "Total in 7-day window should be 4 (8-day-ago cell excluded)")
        }
    }

    func testLast7DaysByDayIsOrderedOldestFirst() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now)

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            let dates = model.last7DaysByDay.map { $0.date }
            XCTAssertEqual(dates, dates.sorted(), "Days should be ordered oldest to newest")
        }
    }

    // MARK: - Locality breakdown

    func testLocalityGroupingAggregatesCorrectly() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now, locality: "Springfield")
            insertCell(in: ctx, x: 1, y: 0, firstVisited: now, locality: "Springfield")
            insertCell(in: ctx, x: 2, y: 0, firstVisited: now, locality: "Shelbyville")

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            let localities = model.last7DaysByLocality
            XCTAssertEqual(localities.count, 2)
            XCTAssertEqual(localities.first?.locality, "Springfield")
            XCTAssertEqual(localities.first?.count, 2)
            XCTAssertEqual(localities.last?.locality, "Shelbyville")
            XCTAssertEqual(localities.last?.count, 1)
        }
    }

    func testNilLocalityAppearsAsUnknown() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now, locality: nil)

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            XCTAssertEqual(model.last7DaysByLocality.first?.locality, "Unknown")
        }
    }

    func testLocalityBreakdownOnlyIncludesLast7Days() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now, locality: "Recentville")
            // 8 days ago — outside window
            insertCell(in: ctx, x: 1, y: 0,
                       firstVisited: now.addingTimeInterval(-8 * 86400),
                       locality: "OldTown")

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            let names = model.last7DaysByLocality.map { $0.locality }
            XCTAssertTrue(names.contains("Recentville"))
            XCTAssertFalse(names.contains("OldTown"), "8-day-old cell should not appear in locality breakdown")
        }
    }

    // MARK: - Total days active

    func testTotalDaysActiveCountsDistinctDays() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            // 3 cells today — counts as 1 day
            insertCell(in: ctx, x: 0, y: 0, firstVisited: now)
            insertCell(in: ctx, x: 1, y: 0, firstVisited: now.addingTimeInterval(-3600))
            insertCell(in: ctx, x: 2, y: 0, firstVisited: now.addingTimeInterval(-7200))
            // 1 cell yesterday — counts as 1 more day
            insertCell(in: ctx, x: 3, y: 0, firstVisited: now.addingTimeInterval(-86400))

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            XCTAssertEqual(model.totalDaysActive, 2)
        }
    }

    func testTotalDaysActiveIsZeroWhenEmpty() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let model     = DiscoveryStatsModel()
            model.refresh(context: container.viewContext, cellSizeMeters: 50)
            XCTAssertEqual(model.totalDaysActive, 0)
        }
    }

    // MARK: - Streaks

    func testCurrentStreakThreeConsecutiveDaysIncludingToday() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now)
            insertCell(in: ctx, x: 1, y: 0, firstVisited: now.addingTimeInterval(-86400))
            insertCell(in: ctx, x: 2, y: 0, firstVisited: now.addingTimeInterval(-2 * 86400))

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            XCTAssertEqual(model.currentStreak, 3)
        }
    }

    func testCurrentStreakWithGapBeforeToday() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            // Today only — gap before it
            insertCell(in: ctx, x: 0, y: 0, firstVisited: now)
            insertCell(in: ctx, x: 1, y: 0, firstVisited: now.addingTimeInterval(-3 * 86400))

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            XCTAssertEqual(model.currentStreak, 1)
        }
    }

    func testCurrentStreakIsZeroWhenLastWalkTwoDaysAgo() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now.addingTimeInterval(-2 * 86400))

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            XCTAssertEqual(model.currentStreak, 0)
        }
    }

    func testLongestStreakSpansOlderDays() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            // 4-day run ending 10 days ago
            for i in 10...13 {
                insertCell(in: ctx, x: Int32(i), y: 0, firstVisited: now.addingTimeInterval(Double(-i) * 86400))
            }
            // Today only (streak of 1)
            insertCell(in: ctx, x: 0, y: 0, firstVisited: now)

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            XCTAssertEqual(model.longestStreak, 4)
            XCTAssertEqual(model.currentStreak, 1)
        }
    }

    func testCurrentStreakIsOneForSingleDayToday() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext

            insertCell(in: ctx, x: 0, y: 0, firstVisited: Date())

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            XCTAssertEqual(model.currentStreak, 1,
                "Single cell visited today should produce a streak of 1")
            XCTAssertEqual(model.longestStreak, 1)
        }
    }

    func testCurrentStreakIsOneForYesterdayOnlyWalk() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let yesterday = Date().addingTimeInterval(-86400)

            insertCell(in: ctx, x: 0, y: 0, firstVisited: yesterday)

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            XCTAssertEqual(model.currentStreak, 1,
                "Last walk yesterday (no walk today) should still count as streak of 1")
        }
    }

    func testStreaksAreZeroWhenEmpty() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let model     = DiscoveryStatsModel()
            model.refresh(context: container.viewContext, cellSizeMeters: 50)
            XCTAssertEqual(model.currentStreak, 0)
            XCTAssertEqual(model.longestStreak, 0)
        }
    }

    // MARK: - Estimated distance

    func testEstimatedDistanceBasedOnCellCountAndSize() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            for i in 0..<10 {
                insertCell(in: ctx, x: Int32(i), y: 0, cellSizeMeters: 50, firstVisited: now)
            }

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            XCTAssertEqual(model.estimatedDistanceMeters, 500.0, accuracy: 0.01)
        }
    }

    func testEstimatedDistanceIsZeroWhenEmpty() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let model     = DiscoveryStatsModel()
            model.refresh(context: container.viewContext, cellSizeMeters: 50)
            XCTAssertEqual(model.estimatedDistanceMeters, 0)
        }
    }

    // MARK: - All-time locality

    func testAllTimeByLocalityIncludesOldCells() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now.addingTimeInterval(-30 * 86400), locality: "OldTown")
            insertCell(in: ctx, x: 1, y: 0, firstVisited: now, locality: "NewTown")

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            let names = model.allTimeByLocality.map { $0.locality }
            XCTAssertTrue(names.contains("OldTown"), "Old cells should appear in all-time locality breakdown")
            XCTAssertTrue(names.contains("NewTown"))
        }
    }

    func testAllTimeByLocalitySortedByCountDescending() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now, locality: "A")
            insertCell(in: ctx, x: 1, y: 0, firstVisited: now, locality: "A")
            insertCell(in: ctx, x: 2, y: 0, firstVisited: now, locality: "A")
            insertCell(in: ctx, x: 3, y: 0, firstVisited: now, locality: "B")

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: 50)

            XCTAssertEqual(model.allTimeByLocality.first?.locality, "A")
            XCTAssertEqual(model.allTimeByLocality.first?.count, 3)
        }
    }

    func testAllTimeByLocalityIsEmptyWhenNoData() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let model     = DiscoveryStatsModel()
            model.refresh(context: container.viewContext, cellSizeMeters: 50)
            XCTAssertTrue(model.allTimeByLocality.isEmpty)
        }
    }

    // MARK: - Locality centroid and span

    func testSingleCellLocalityCenterMatchesGridMathCenter() async {
        await MainActor.run {
            let container      = makeInMemoryContainer()
            let ctx            = container.viewContext
            let cellSizeMeters = 50.0
            let x: Int32       = 100
            let y: Int32       = 200

            insertCell(in: ctx, x: x, y: y, cellSizeMeters: cellSizeMeters,
                       firstVisited: Date(), locality: "Solo")

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: cellSizeMeters)

            let expected = GridMath.center(for: CellID(x: x, y: y), cellSizeMeters: cellSizeMeters)
            let stat = model.allTimeByLocality.first(where: { $0.locality == "Solo" })
            XCTAssertNotNil(stat)
            XCTAssertEqual(stat!.center.latitude,  expected.latitude,  accuracy: 1e-9)
            XCTAssertEqual(stat!.center.longitude, expected.longitude, accuracy: 1e-9)
        }
    }

    func testMultiCellLocalityCenterIsAverageOfCellCenters() async {
        await MainActor.run {
            let container      = makeInMemoryContainer()
            let ctx            = container.viewContext
            let cellSizeMeters = 50.0
            let now            = Date()

            insertCell(in: ctx, x: 0, y: 0, cellSizeMeters: cellSizeMeters, firstVisited: now, locality: "Avg")
            insertCell(in: ctx, x: 2, y: 2, cellSizeMeters: cellSizeMeters, firstVisited: now, locality: "Avg")

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: cellSizeMeters)

            let c0 = GridMath.center(for: CellID(x: 0, y: 0), cellSizeMeters: cellSizeMeters)
            let c2 = GridMath.center(for: CellID(x: 2, y: 2), cellSizeMeters: cellSizeMeters)
            let expectedLat = (c0.latitude  + c2.latitude)  / 2
            let expectedLon = (c0.longitude + c2.longitude) / 2

            let stat = model.allTimeByLocality.first(where: { $0.locality == "Avg" })
            XCTAssertNotNil(stat)
            XCTAssertEqual(stat!.center.latitude,  expectedLat, accuracy: 1e-9)
            XCTAssertEqual(stat!.center.longitude, expectedLon, accuracy: 1e-9)
        }
    }

    func testSingleCellLocalitySpanHasMinimumSize() async {
        await MainActor.run {
            let container      = makeInMemoryContainer()
            let ctx            = container.viewContext
            let cellSizeMeters = 50.0

            insertCell(in: ctx, x: 0, y: 0, cellSizeMeters: cellSizeMeters,
                       firstVisited: Date(), locality: "Tiny")

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: cellSizeMeters)

            let stat = model.allTimeByLocality.first(where: { $0.locality == "Tiny" })
            XCTAssertNotNil(stat)
            XCTAssertGreaterThanOrEqual(stat!.span.latitudeDelta,  0.01)
            XCTAssertGreaterThanOrEqual(stat!.span.longitudeDelta, 0.01)
        }
    }

    func testMultiCellLocalitySpanCoversAllCells() async {
        await MainActor.run {
            let container      = makeInMemoryContainer()
            let ctx            = container.viewContext
            let cellSizeMeters = 50.0
            let now            = Date()

            for x: Int32 in [0, 100] {
                for y: Int32 in [0, 100] {
                    insertCell(in: ctx, x: x, y: y, cellSizeMeters: cellSizeMeters,
                               firstVisited: now, locality: "Wide")
                }
            }

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: cellSizeMeters)

            let stat = model.allTimeByLocality.first(where: { $0.locality == "Wide" })
            XCTAssertNotNil(stat)

            let step = cellSizeMeters / GridMath.metersPerDegree
            let minExpectedSpan = 100.0 * step
            XCTAssertGreaterThan(stat!.span.latitudeDelta,  minExpectedSpan)
            XCTAssertGreaterThan(stat!.span.longitudeDelta, minExpectedSpan)
        }
    }

    func testLocalityCenterAppearsInLast7DaysByLocality() async {
        await MainActor.run {
            let container      = makeInMemoryContainer()
            let ctx            = container.viewContext
            let cellSizeMeters = 50.0
            let x: Int32 = 50, y: Int32 = 60

            insertCell(in: ctx, x: x, y: y, cellSizeMeters: cellSizeMeters,
                       firstVisited: Date(), locality: "Recent")

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx, cellSizeMeters: cellSizeMeters)

            let stat = model.last7DaysByLocality.first(where: { $0.locality == "Recent" })
            XCTAssertNotNil(stat)
            let expected = GridMath.center(for: CellID(x: x, y: y), cellSizeMeters: cellSizeMeters)
            XCTAssertEqual(stat!.center.latitude,  expected.latitude,  accuracy: 1e-9)
            XCTAssertEqual(stat!.center.longitude, expected.longitude, accuracy: 1e-9)
        }
    }
}
