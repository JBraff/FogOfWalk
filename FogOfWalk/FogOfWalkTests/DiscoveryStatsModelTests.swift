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
        locality: String? = nil,
        state: String? = nil,
        country: String? = nil
    ) -> VisitedCell {
        let cell = VisitedCell(context: ctx)
        cell.cellX          = x
        cell.cellY          = y
        cell.cellSizeMeters = cellSizeMeters
        cell.firstVisited   = firstVisited
        cell.locality       = locality
        cell.state          = state
        cell.country        = country
        try! ctx.save()
        return cell
    }

    // MARK: - Empty state

    func testEmptyDataProducesZeros() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let model     = DiscoveryStatsModel()
            model.refresh(context: container.viewContext)

            XCTAssertEqual(model.last24HourCount, 0)
            XCTAssertEqual(model.last7DaysByDay.count, 7)
            XCTAssertTrue(model.locality(for: .thisWeek).isEmpty)
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
            model.refresh(context: ctx)

            XCTAssertEqual(model.allTimeTotal, 3)
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
            model.refresh(context: ctx)

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
            model.refresh(context: ctx)

            XCTAssertEqual(model.bestDayCount, 3)
            XCTAssertNotNil(model.bestDayDate)
            let bestDay = calendar.startOfDay(for: twoDaysAgo)
            XCTAssertEqual(model.bestDayDate?.timeIntervalSinceReferenceDate ?? 0,
                           bestDay.timeIntervalSinceReferenceDate,
                           accuracy: 1)
        }
    }

    // MARK: - Last 24 hours

    func testTodayCountIncludesCellsFromToday() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()
            let calendar  = Calendar.current
            let startOfToday = calendar.startOfDay(for: now)

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now.addingTimeInterval(-3600))   // 1 h ago — in (today)
            insertCell(in: ctx, x: 1, y: 0, firstVisited: startOfToday.addingTimeInterval(-1)) // 1 s before midnight — out
            insertCell(in: ctx, x: 2, y: 0, firstVisited: startOfToday)                    // exactly midnight — in

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx)

            XCTAssertEqual(model.last24HourCount, 2)
        }
    }

    // MARK: - 7-day chart

    func testLast7DaysByDayAlwaysHas7Entries() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let model     = DiscoveryStatsModel()
            model.refresh(context: container.viewContext)

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
            model.refresh(context: ctx)

            XCTAssertEqual(model.last7DaysByDay.count, 7)
            let todayEntry = model.last7DaysByDay.last
            XCTAssertEqual(todayEntry?.count, 3, "Today should have 3 cells")
            let total = model.last7DaysByDay.reduce(0) { $0 + $1.count }
            XCTAssertEqual(total, 4, "Total in 7-day window should be 4 (8-day-ago cell excluded)")
        }
    }

    func testLast7DaysSlotsAreConsecutiveCalendarDays() async {
        // Regression test for DST-unsafe day arithmetic.
        // Slots must be consecutive calendar days, not fixed 86400-second intervals.
        await MainActor.run {
            let container = makeInMemoryContainer()
            let model     = DiscoveryStatsModel()
            model.refresh(context: container.viewContext)

            let calendar = Calendar.current
            let slots    = model.last7DaysByDay
            XCTAssertEqual(slots.count, 7)
            for i in 1..<slots.count {
                let diff = calendar.dateComponents([.day], from: slots[i-1].date, to: slots[i].date).day
                XCTAssertEqual(diff, 1,
                    "Consecutive slots must be exactly 1 calendar day apart, got \(diff ?? -1) between \(slots[i-1].date) and \(slots[i].date)")
            }
            // Last slot must be today.
            let today = calendar.startOfDay(for: Date())
            XCTAssertEqual(slots.last?.date, today,
                "Last slot must represent today (start of day)")
        }
    }

    func testLast7DaysByDayIsOrderedOldestFirst() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now)

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx)

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
            model.refresh(context: ctx)

            let localities = model.locality(for: .thisWeek)
            XCTAssertEqual(localities.count, 2)
            XCTAssertEqual(localities.first?.name, "Springfield")
            XCTAssertEqual(localities.first?.count, 2)
            XCTAssertEqual(localities.last?.name, "Shelbyville")
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
            model.refresh(context: ctx)

            XCTAssertEqual(model.locality(for: .thisWeek).first?.name, "Unknown")
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
            model.refresh(context: ctx)

            let names = model.locality(for: .thisWeek).map { $0.name }
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
            model.refresh(context: ctx)

            XCTAssertEqual(model.totalDaysActive, 2)
        }
    }

    func testTotalDaysActiveIsZeroWhenEmpty() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let model     = DiscoveryStatsModel()
            model.refresh(context: container.viewContext)
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
            model.refresh(context: ctx)

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
            model.refresh(context: ctx)

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
            model.refresh(context: ctx)

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
            model.refresh(context: ctx)

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
            model.refresh(context: ctx)

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
            model.refresh(context: ctx)

            XCTAssertEqual(model.currentStreak, 1,
                "Last walk yesterday (no walk today) should still count as streak of 1")
        }
    }

    func testStreaksAreZeroWhenEmpty() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let model     = DiscoveryStatsModel()
            model.refresh(context: container.viewContext)
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
            model.refresh(context: ctx)

            XCTAssertEqual(model.estimatedDistanceMeters, 500.0, accuracy: 0.01)
        }
    }

    func testEstimatedDistanceIsZeroWhenEmpty() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let model     = DiscoveryStatsModel()
            model.refresh(context: container.viewContext)
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
            model.refresh(context: ctx)

            let names = model.locality(for: .allTime).map { $0.name }
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
            model.refresh(context: ctx)

            XCTAssertEqual(model.locality(for: .allTime).first?.name, "A")
            XCTAssertEqual(model.locality(for: .allTime).first?.count, 3)
        }
    }

    func testAllTimeByLocalityIsEmptyWhenNoData() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let model     = DiscoveryStatsModel()
            model.refresh(context: container.viewContext)
            XCTAssertTrue(model.locality(for: .allTime).isEmpty)
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
            model.refresh(context: ctx)

            let expected = GridMath.center(for: CellID(x: x, y: y))
            let stat = model.locality(for: .allTime).first(where: { $0.name == "Solo" })
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
            model.refresh(context: ctx)

            let c0 = GridMath.center(for: CellID(x: 0, y: 0))
            let c2 = GridMath.center(for: CellID(x: 2, y: 2))
            let expectedLat = (c0.latitude  + c2.latitude)  / 2
            let expectedLon = (c0.longitude + c2.longitude) / 2

            let stat = model.locality(for: .allTime).first(where: { $0.name == "Avg" })
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
            model.refresh(context: ctx)

            let stat = model.locality(for: .allTime).first(where: { $0.name == "Tiny" })
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
            model.refresh(context: ctx)

            let stat = model.locality(for: .allTime).first(where: { $0.name == "Wide" })
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
            model.refresh(context: ctx)

            let stat = model.locality(for: .thisWeek).first(where: { $0.name == "Recent" })
            XCTAssertNotNil(stat)
            let expected = GridMath.center(for: CellID(x: x, y: y))
            XCTAssertEqual(stat!.center.latitude,  expected.latitude,  accuracy: 1e-9)
            XCTAssertEqual(stat!.center.longitude, expected.longitude, accuracy: 1e-9)
        }
    }

    // MARK: - Today / This Month locality

    func testTodayLocalityOnlyIncludesTodaysCells() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()
            let yesterday = now.addingTimeInterval(-86400)

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now,       locality: "Todayville")
            insertCell(in: ctx, x: 1, y: 0, firstVisited: yesterday, locality: "Yesterdayton")

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx)

            let names = model.locality(for: .today).map { $0.name }
            XCTAssertTrue(names.contains("Todayville"), "Cell from today should appear in .today")
            XCTAssertFalse(names.contains("Yesterdayton"), "Cell from yesterday should not appear in .today")
        }
    }

    func testThisMonthLocalityIncludesThisMonthOnly() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()
            // Use 40 days ago to ensure we land in a different calendar month
            let twoMonthsAgo = now.addingTimeInterval(-40 * 86400)

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now,          locality: "Thismonthburg")
            insertCell(in: ctx, x: 1, y: 0, firstVisited: twoMonthsAgo, locality: "Oldmonthton")

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx)

            let thisMonthNames = model.locality(for: .thisMonth).map { $0.name }
            XCTAssertTrue(thisMonthNames.contains("Thismonthburg"))

            let allTimeNames = model.locality(for: .allTime).map { $0.name }
            XCTAssertTrue(allTimeNames.contains("Oldmonthton"), "Old cell should appear in .allTime")
        }
    }

    // MARK: - LocalityPeriod enum

    func testLocalityPeriodDisplayNamesAreNonEmpty() {
        for period in LocalityPeriod.allCases {
            XCTAssertFalse(period.displayName.isEmpty, "\(period.rawValue) displayName should not be empty")
        }
    }

    func testLocalityPeriodEmptyStateLabelsAreNonEmpty() {
        for period in LocalityPeriod.allCases {
            XCTAssertFalse(period.emptyStateLabel.isEmpty, "\(period.rawValue) emptyStateLabel should not be empty")
        }
    }

    func testLocalityPeriodRawValueRoundTrip() {
        for period in LocalityPeriod.allCases {
            let reconstructed = LocalityPeriod(rawValue: period.rawValue)
            XCTAssertEqual(reconstructed, period, "Round-trip via rawValue should reconstruct \(period)")
        }
    }

    // MARK: - Empty period locality

    func testEmptyPeriodReturnsEmptyArray() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            // Insert a cell visited 8 days ago — inside .allTime and .thisMonth but outside .today and .thisWeek
            insertCell(in: ctx, x: 0, y: 0,
                       firstVisited: Date().addingTimeInterval(-8 * 86400),
                       locality: "OldTown")

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx)

            XCTAssertTrue(model.locality(for: .today).isEmpty,
                "No cells visited today — .today should return empty array, not nil")
            XCTAssertTrue(model.locality(for: .thisWeek).isEmpty,
                "No cells visited this week — .thisWeek should return empty array, not nil")
            XCTAssertFalse(model.locality(for: .allTime).isEmpty,
                ".allTime should still contain the old cell")
        }
    }

    // MARK: - State breakdown (all-time only)

    func testStateGroupingAggregatesCorrectly() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now, state: "California")
            insertCell(in: ctx, x: 1, y: 0, firstVisited: now, state: "California")
            insertCell(in: ctx, x: 2, y: 0, firstVisited: now, state: "Nevada")

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx)

            XCTAssertEqual(model.stateStats.count, 2)
            XCTAssertEqual(model.stateStats.first?.name, "California")
            XCTAssertEqual(model.stateStats.first?.count, 2)
            XCTAssertEqual(model.stateStats.last?.name, "Nevada")
            XCTAssertEqual(model.stateStats.last?.count, 1)
        }
    }

    func testNilStateAppearsAsUnknown() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now, state: nil)

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx)

            XCTAssertEqual(model.stateStats.first?.name, "Unknown")
        }
    }

    func testStateStatsIncludeOldCells() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now.addingTimeInterval(-30 * 86400), state: "Oregon")

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx)

            XCTAssertTrue(model.stateStats.map { $0.name }.contains("Oregon"),
                "State stats are all-time — old cells must still be included")
        }
    }

    func testStateStatsEmptyWhenNoData() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let model     = DiscoveryStatsModel()
            model.refresh(context: container.viewContext)
            XCTAssertTrue(model.stateStats.isEmpty)
        }
    }

    // MARK: - Country breakdown (all-time only)

    func testCountryGroupingAggregatesCorrectly() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now, country: "United States")
            insertCell(in: ctx, x: 1, y: 0, firstVisited: now, country: "United States")
            insertCell(in: ctx, x: 2, y: 0, firstVisited: now, country: "Canada")

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx)

            XCTAssertEqual(model.countryStats.count, 2)
            XCTAssertEqual(model.countryStats.first?.name, "United States")
            XCTAssertEqual(model.countryStats.first?.count, 2)
            XCTAssertEqual(model.countryStats.last?.name, "Canada")
            XCTAssertEqual(model.countryStats.last?.count, 1)
        }
    }

    func testNilCountryAppearsAsUnknown() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let now       = Date()

            insertCell(in: ctx, x: 0, y: 0, firstVisited: now, country: nil)

            let model = DiscoveryStatsModel()
            model.refresh(context: ctx)

            XCTAssertEqual(model.countryStats.first?.name, "Unknown")
        }
    }

    func testCountryStatsEmptyWhenNoData() async {
        await MainActor.run {
            let container = makeInMemoryContainer()
            let model     = DiscoveryStatsModel()
            model.refresh(context: container.viewContext)
            XCTAssertTrue(model.countryStats.isEmpty)
        }
    }
}
