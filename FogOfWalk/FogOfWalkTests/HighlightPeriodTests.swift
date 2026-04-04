import XCTest
@testable import FogOfWalk

final class HighlightPeriodTests: XCTestCase {

    func testOffReturnsNilCutoffDate() {
        XCTAssertNil(HighlightPeriod.off.cutoffDate,
                     ".off should return nil cutoff date")
    }

    func testLastHourCutoffIsInThePast() {
        guard let cutoff = HighlightPeriod.lastHour.cutoffDate else {
            XCTFail("lastHour should have a non-nil cutoffDate"); return
        }
        XCTAssertLessThan(cutoff, Date(),
                          "lastHour cutoff should be before now")
        let diff = Date().timeIntervalSince(cutoff)
        XCTAssertGreaterThan(diff, 3590, "Should be approximately 1 hour ago (got \(diff)s)")
        XCTAssertLessThan(diff, 3610, "Should be approximately 1 hour ago (got \(diff)s)")
    }

    func testTodayCutoffIsStartOfDay() {
        guard let cutoff = HighlightPeriod.today.cutoffDate else {
            XCTFail("today should have a non-nil cutoffDate"); return
        }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        XCTAssertEqual(cutoff, startOfDay,
                       "today cutoff should equal startOfDay")
    }

    func testTodayCutoffIsInThePast() {
        guard let cutoff = HighlightPeriod.today.cutoffDate else {
            XCTFail("today should have a non-nil cutoffDate"); return
        }
        XCTAssertLessThanOrEqual(cutoff, Date(),
                                 "today cutoff should not be in the future")
    }

    func testThisWeekCutoffIsInThePast() {
        guard let cutoff = HighlightPeriod.thisWeek.cutoffDate else {
            XCTFail("thisWeek should have a non-nil cutoffDate"); return
        }
        XCTAssertLessThanOrEqual(cutoff, Date(),
                                 "thisWeek cutoff should not be in the future")
        // Should be at most 7 days ago.
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        XCTAssertGreaterThanOrEqual(cutoff, sevenDaysAgo,
                                    "thisWeek cutoff should be within the last 7 days")
    }

    func testThisMonthCutoffIsInThePast() {
        guard let cutoff = HighlightPeriod.thisMonth.cutoffDate else {
            XCTFail("thisMonth should have a non-nil cutoffDate"); return
        }
        XCTAssertLessThanOrEqual(cutoff, Date(),
                                 "thisMonth cutoff should not be in the future")
        // Should be at most 31 days ago.
        let thirtyOneDaysAgo = Date().addingTimeInterval(-31 * 24 * 3600)
        XCTAssertGreaterThanOrEqual(cutoff, thirtyOneDaysAgo,
                                    "thisMonth cutoff should be within the last 31 days")
    }

    func testAllNonOffPeriodsHaveCutoffDatesInThePast() {
        for period in HighlightPeriod.allCases where period != .off {
            guard let cutoff = period.cutoffDate else {
                XCTFail("\(period) must have a non-nil cutoffDate"); continue
            }
            XCTAssertLessThanOrEqual(cutoff, Date(),
                                     "\(period) cutoff should not be in the future")
        }
    }

    func testTodayCutoffIsAfterThisMonthCutoff() {
        // Today's start is always >= this month's start.
        guard let today     = HighlightPeriod.today.cutoffDate,
              let thisMonth = HighlightPeriod.thisMonth.cutoffDate else {
            XCTFail("Expected non-nil cutoff dates"); return
        }
        XCTAssertGreaterThanOrEqual(today, thisMonth,
            "startOfDay should be >= startOfMonth")
    }

    func testAllCasesHaveDisplayNames() {
        for period in HighlightPeriod.allCases {
            XCTAssertFalse(period.displayName.isEmpty,
                           "\(period) must have a non-empty display name")
        }
    }

    func testRawValueRoundTrip() {
        for period in HighlightPeriod.allCases {
            let roundTripped = HighlightPeriod(rawValue: period.rawValue)
            XCTAssertEqual(roundTripped, period,
                           "Raw value round-trip must work for \(period)")
        }
    }
}
