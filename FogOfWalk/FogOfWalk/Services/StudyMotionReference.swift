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
        let metersFromWalkingOnset: Double?
        let stepsFromWalkingOnset: Int?
    }

    struct Result: Codable {
        let queriedAt: Date
        let intervalStart: Date
        let intervalEnd: Date
        let activityAvailable: Bool
        let pedometerAvailable: Bool
        let activities: [Activity]
        let firstReportedWalking: Date?
        let wholeIntervalMeters: Double?
        let wholeIntervalSteps: Int?
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
        let whole = try await pedometerData(pedometer, from: start, to: end)
        let onset = mapped.first(where: { $0.walking })?.start
        var points: [DistancePoint] = []
        if let onset, onset < end {
            // Fifteen-second cumulative history bounds the distance at a logged fix
            // receipt without running a second location consumer during the trial.
            let limit = min(end, onset.addingTimeInterval(10 * 60))
            var through = onset.addingTimeInterval(15)
            while through < limit {
                let data = try await pedometerData(pedometer, from: onset, to: through)
                points.append(DistancePoint(through: through,
                                            metersFromWalkingOnset: data.distance?.doubleValue,
                                            stepsFromWalkingOnset: data.numberOfSteps.intValue))
                through.addTimeInterval(15)
            }
            let data = try await pedometerData(pedometer, from: onset, to: limit)
            points.append(DistancePoint(through: limit,
                                        metersFromWalkingOnset: data.distance?.doubleValue,
                                        stepsFromWalkingOnset: data.numberOfSteps.intValue))
        }
        return Result(queriedAt: Date(), intervalStart: start, intervalEnd: end,
                      activityAvailable: activityAvailable,
                      pedometerAvailable: pedometerAvailable,
                      activities: mapped, firstReportedWalking: onset,
                      wholeIntervalMeters: whole.distance?.doubleValue,
                      wholeIntervalSteps: whole.numberOfSteps.intValue,
                      distanceTimeline: points)
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
