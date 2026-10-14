import XCTest
@testable import FogOfWalk

@MainActor
final class StudyMotionReferenceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func walking(at date: Date) -> StudyMotionReference.Activity {
        .init(start: date, confidence: 2, stationary: false, walking: true,
              running: false, cycling: false, automotive: false, unknown: false)
    }

    func testDelayedClassificationRetainsEarlierStepsInEveryQuery() async throws {
        let onset = start.addingTimeInterval(420)
        let end = start.addingTimeInterval(828.8)
        var ranges: [(Date, Date)] = []
        let result = try await StudyMotionReference.makeResult(
            from: start, to: end, activities: [walking(at: onset)]
        ) { from, through in
            ranges.append((from, through))
            // Movement before classification must survive even when the first
            // classified walking interval would itself return zero steps.
            let earlier = through >= self.start.addingTimeInterval(360) ? 61 : 0
            let later = through > onset.addingTimeInterval(45) ? 559 : 0
            return .init(meters: Double(earlier) * 0.6 + Double(later) * 0.7,
                         steps: earlier + later)
        }
        XCTAssertTrue(ranges.allSatisfy { $0.0 == start })
        XCTAssertEqual(ranges.map { $0.1 }, result.timelinePlan.endpoints)
        XCTAssertEqual(result.firstReportedWalking, onset)
        XCTAssertEqual(result.distanceTimeline.first { $0.through == onset }?.stepsFromCaptureStart, 61)
        XCTAssertEqual(result.distanceTimeline.first {
            $0.through == onset.addingTimeInterval(45)
        }?.stepsFromCaptureStart, 61)
        XCTAssertEqual(result.wholeIntervalSteps, 620)
        XCTAssertEqual(result.wholeIntervalMeters, result.distanceTimeline.last?.metersFromCaptureStart)
        XCTAssertEqual(ranges.filter { $0.1 == end }.count, 1)
    }

    func testNoWalkingClassificationStillReportsMovementAndUnavailableDistance() async throws {
        let end = start.addingTimeInterval(32.5)
        let result = try await StudyMotionReference.makeResult(
            from: start, to: end, activities: []
        ) { _, _ in .init(meters: nil, steps: 12) }
        XCTAssertNil(result.firstReportedWalking)
        XCTAssertNil(result.timelinePlan.detailStart)
        XCTAssertEqual(result.distanceTimeline.map(\.through), [
            start.addingTimeInterval(15), start.addingTimeInterval(30), end
        ])
        XCTAssertTrue(result.distanceTimeline.allSatisfy { $0.stepsFromCaptureStart == 12 })
        XCTAssertTrue(result.distanceTimeline.allSatisfy { $0.metersFromCaptureStart == nil })
        XCTAssertNil(result.wholeIntervalMeters)
        XCTAssertEqual(result.wholeIntervalSteps, 12)
    }

    func testOvernightIdleUsesBoundedQueriesAndRetainsFullCaptureAndOnsetDetail() async throws {
        let onset = start.addingTimeInterval(8 * 3_600)
        let end = onset.addingTimeInterval(1_800.5)
        let plan = try StudyMotionReference.timelinePlan(
            from: start, to: end, firstReportedWalking: onset
        )
        XCTAssertLessThanOrEqual(plan.endpoints.count, 129)
        XCTAssertGreaterThan(plan.coarseIntervalSeconds, 15)
        XCTAssertEqual(plan.origin, start)
        XCTAssertEqual(plan.endpoints.last, end)
        XCTAssertEqual(plan.endpoints, Array(Set(plan.endpoints)).sorted())
        XCTAssertTrue(plan.endpoints.allSatisfy { $0 > start && $0 <= end })
        XCTAssertEqual(plan.detailStart, onset.addingTimeInterval(-120))
        XCTAssertEqual(plan.detailEnd, onset.addingTimeInterval(600))
        for offset in stride(from: -120, through: 600, by: 15) {
            XCTAssertTrue(plan.endpoints.contains(onset.addingTimeInterval(Double(offset))))
        }
        // Independently noted onset outside the detail window still has adjacent
        // full-capture samples; the exported coarse cadence exposes that resolution.
        let manualOnset = onset.addingTimeInterval(-300)
        let before = try XCTUnwrap(plan.endpoints.last { $0 < manualOnset })
        let after = try XCTUnwrap(plan.endpoints.first { $0 > manualOnset })
        XCTAssertLessThanOrEqual(after.timeIntervalSince(before), plan.coarseIntervalSeconds)
    }

    func testShortCaptureClampsDetailAndQueriesEndpointOnce() async throws {
        let end = start.addingTimeInterval(7.25)
        var count = 0
        let result = try await StudyMotionReference.makeResult(
            from: start, to: end, activities: [walking(at: start)]
        ) { from, through in
            count += 1
            XCTAssertEqual(from, self.start)
            XCTAssertEqual(through, end)
            return .init(meters: 3, steps: 5)
        }
        XCTAssertEqual(count, 1)
        XCTAssertEqual(result.timelinePlan.detailStart, start)
        XCTAssertEqual(result.timelinePlan.detailEnd, end)
        XCTAssertEqual(result.wholeIntervalSteps, 5)
    }

    func testEarliestWalkingIsUsedEvenWhenActivitiesAreUnordered() async throws {
        let early = start.addingTimeInterval(30)
        let result = try await StudyMotionReference.makeResult(
            from: start, to: start.addingTimeInterval(90),
            activities: [walking(at: start.addingTimeInterval(60)), walking(at: early)]
        ) { _, _ in .init(meters: 0, steps: 0) }
        XCTAssertEqual(result.firstReportedWalking, early)
    }

    func testInvalidIntervalsNeverQueryHistory() async {
        for end in [start, start.addingTimeInterval(-1)] {
            do {
                _ = try await StudyMotionReference.makeResult(from: start, to: end, activities: []) { _, _ in
                    XCTFail("Invalid intervals must not query pedometer history")
                    return .init(meters: 0, steps: 0)
                }
                XCTFail("Invalid interval must fail")
            } catch {
                XCTAssertTrue(error is StudyMotionReference.QueryError)
            }
        }
    }

    func testHistoryErrorIsPropagatedWithoutPartialReport() async {
        enum HistoryError: Error { case denied }
        do {
            _ = try await StudyMotionReference.makeResult(
                from: start, to: start.addingTimeInterval(30), activities: []
            ) { _, _ in throw HistoryError.denied }
            XCTFail("History failure must not produce a usable report")
        } catch {
            XCTAssertTrue(error is HistoryError)
        }
    }

    func testExportLabelsCaptureOriginAndVersionWithoutWalkingOriginKeys() async throws {
        let result = try await StudyMotionReference.makeResult(
            from: start, to: start.addingTimeInterval(20), activities: []
        ) { _, _ in .init(meters: 37.1, steps: 61) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(result)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 2)
        let plan = try XCTUnwrap(json["timelinePlan"] as? [String: Any])
        XCTAssertEqual(plan["origin"] as? Double, 1_000_000)
        let points = try XCTUnwrap(json["distanceTimeline"] as? [[String: Any]])
        XCTAssertEqual(points.last?["stepsFromCaptureStart"] as? Int, 61)
        XCTAssertEqual(points.last?["metersFromCaptureStart"] as? Double, 37.1)
        XCTAssertNil(points.last?["stepsFromWalkingOnset"])
        XCTAssertNil(points.last?["metersFromWalkingOnset"])
    }
}
