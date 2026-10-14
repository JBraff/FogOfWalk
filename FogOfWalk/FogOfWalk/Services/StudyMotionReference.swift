import CoreMotion
import Foundation

/// Post-run history only. No live motion stream is started and this never wakes tracking.
enum StudyMotionReference {
    struct Activity: Codable {
        let start: Date
        let confidence: Int
        let stationary: Bool
        let walking: Bool
        let running: Bool
        let cycling: Bool
        let automotive: Bool
        let unknown: Bool
    }

    struct DistancePoint: Codable {
        let through: Date
        let metersFromCaptureStart: Double?
        let stepsFromCaptureStart: Int?
    }

    struct PedometerReading {
        let meters: Double?
        let steps: Int
    }

    struct TimelinePlan: Codable {
        let origin: Date
        let end: Date
        let coarseIntervalSeconds: Double
        let detailIntervalSeconds: Double
        let detailStart: Date?
        let detailEnd: Date?
        let endpoints: [Date]
    }

    struct Result: Codable {
        // Version 1 measured its timeline from walking classification. Version 2
        // measures every point from capture start, including earlier movement.
        let schemaVersion: Int
        let queriedAt: Date
        let intervalStart: Date
        let intervalEnd: Date
        let activityAvailable: Bool
        let pedometerAvailable: Bool
        let activities: [Activity]
        let firstReportedWalking: Date?
        let wholeIntervalMeters: Double?
        let wholeIntervalSteps: Int?
        let timelinePlan: TimelinePlan
        let distanceTimeline: [DistancePoint]
    }

    enum QueryError: LocalizedError {
        case unavailable
        case invalidInterval

        var errorDescription: String? {
            switch self {
            case .unavailable: "Motion activity or pedometer history is unavailable on this phone."
            case .invalidInterval: "Stop a capture after starting it before querying motion history."
            }
        }
    }

    static func query(from start: Date, to end: Date) async throws -> Result {
        guard end > start else { throw QueryError.invalidInterval }
        let activityAvailable = CMMotionActivityManager.isActivityAvailable()
        let pedometerAvailable = CMPedometer.isStepCountingAvailable()
        guard activityAvailable, pedometerAvailable else { throw QueryError.unavailable }

        let activityManager = CMMotionActivityManager()
        let activities = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[CMMotionActivity], Error>) in
            activityManager.queryActivityStarting(from: start, to: end, to: .main) { items, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: items ?? []) }
            }
        }
        let mapped = activities.map {
            Activity(start: $0.startDate, confidence: $0.confidence.rawValue,
                     stationary: $0.stationary, walking: $0.walking,
                     running: $0.running, cycling: $0.cycling,
                     automotive: $0.automotive, unknown: $0.unknown)
        }
        let pedometer = CMPedometer()
        return try await makeResult(from: start, to: end, activities: mapped) { from, to in
            let data = try await pedometerData(pedometer, from: from, to: to)
            return PedometerReading(meters: data.distance?.doubleValue,
                                    steps: data.numberOfSteps.intValue)
        }
    }

    /// Covers even captures with no walking classification. Long idle periods use
    /// at most 80 coarse queries, plus at most 49 detail queries around the first
    /// reported walking transition. These are sampling intervals, not accuracy
    /// bounds on Core Motion or an independently noted departure time.
    static func timelinePlan(from start: Date, to end: Date,
                             firstReportedWalking: Date?) throws -> TimelinePlan {
        let duration = end.timeIntervalSince(start)
        guard duration.isFinite, duration > 0 else { throw QueryError.invalidInterval }
        let coarseInterval = max(15, ceil(duration / 80 / 15) * 15)
        var endpoints: Set<Date> = [end]
        var through = start.addingTimeInterval(coarseInterval)
        while through < end {
            endpoints.insert(through)
            through.addTimeInterval(coarseInterval)
        }

        var detailStart: Date?
        var detailEnd: Date?
        if let reported = firstReportedWalking, reported >= start, reported < end {
            // The two-minute lookback provides detail before classification; it
            // does not assume manual onset lies within this window. The full
            // capture remains available at the exported coarse cadence.
            let lower = max(start, reported.addingTimeInterval(-120))
            let upper = min(end, reported.addingTimeInterval(600))
            detailStart = lower
            detailEnd = upper
            if lower > start { endpoints.insert(lower) }
            through = lower.addingTimeInterval(15)
            while through < upper {
                endpoints.insert(through)
                through.addTimeInterval(15)
            }
            endpoints.insert(upper)
        }
        return TimelinePlan(origin: start, end: end,
                            coarseIntervalSeconds: coarseInterval,
                            detailIntervalSeconds: 15,
                            detailStart: detailStart, detailEnd: detailEnd,
                            endpoints: endpoints.sorted())
    }

    /// Injectable historical reader lets regression tests verify the actual query
    /// ranges and exported counts without live motion streams or device hardware.
    static func makeResult(
        from start: Date, to end: Date, activities: [Activity],
        readPedometer: (Date, Date) async throws -> PedometerReading
    ) async throws -> Result {
        let onset = activities.filter { $0.walking }.map(\.start).min()
        let plan = try timelinePlan(from: start, to: end, firstReportedWalking: onset)
        var points: [DistancePoint] = []
        for through in plan.endpoints {
            let reading = try await readPedometer(start, through)
            points.append(DistancePoint(through: through,
                                        metersFromCaptureStart: reading.meters,
                                        stepsFromCaptureStart: reading.steps))
        }
        // The endpoint query is also the whole-capture total: avoid querying it
        // twice and risking inconsistent results from separate history reads.
        let whole = points.last!
        return Result(schemaVersion: 2, queriedAt: Date(),
                      intervalStart: start, intervalEnd: end,
                      activityAvailable: true, pedometerAvailable: true,
                      activities: activities, firstReportedWalking: onset,
                      wholeIntervalMeters: whole.metersFromCaptureStart,
                      wholeIntervalSteps: whole.stepsFromCaptureStart,
                      timelinePlan: plan, distanceTimeline: points)
    }

    private static func pedometerData(
        _ pedometer: CMPedometer, from start: Date, to end: Date
    ) async throws -> CMPedometerData {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<CMPedometerData, Error>) in
            pedometer.queryPedometerData(from: start, to: end) { data, error in
                if let error { continuation.resume(throwing: error) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: QueryError.unavailable) }
            }
        }
    }
}
