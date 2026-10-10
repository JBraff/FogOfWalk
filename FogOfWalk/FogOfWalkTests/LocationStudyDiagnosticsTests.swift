import CoreLocation
import XCTest
@testable import FogOfWalk

final class LocationStudyDiagnosticsTests: XCTestCase {
    private func location(
        latitude: Double = 40,
        longitude: Double = -74,
        accuracy: Double = 10,
        speed: Double = -1,
        time: Date
    ) -> CLLocation {
        CLLocation(coordinate: .init(latitude: latitude, longitude: longitude),
                   altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 10,
                   course: -1, speed: speed, timestamp: time)
    }

    func testShadowValidatorBoundariesAndUnknownSpeed() async {
        await MainActor.run {
            let start = Date(timeIntervalSince1970: 1_000)
            let received = start.addingTimeInterval(20)
            let valid = location(accuracy: 25, time: received.addingTimeInterval(-15))
            XCTAssertEqual(StudySampleValidator.assess(valid, receivedAt: received,
                           sessionStartedAt: start, lastAcceptedAt: nil), .accepted)
            XCTAssertEqual(StudySampleValidator.assess(valid, receivedAt: received,
                           sessionStartedAt: start, lastAcceptedAt: valid.timestamp), .outOfOrder)
            XCTAssertEqual(StudySampleValidator.assess(
                location(latitude: .nan, time: received), receivedAt: received,
                sessionStartedAt: start, lastAcceptedAt: nil), .invalidCoordinate)
            XCTAssertEqual(StudySampleValidator.assess(
                location(accuracy: 25.1, time: received), receivedAt: received,
                sessionStartedAt: start, lastAcceptedAt: nil), .invalidAccuracy)
            XCTAssertEqual(StudySampleValidator.assess(
                location(accuracy: -1, time: received), receivedAt: received,
                sessionStartedAt: start, lastAcceptedAt: nil), .invalidAccuracy)
            XCTAssertEqual(StudySampleValidator.assess(
                location(time: received.addingTimeInterval(-15.01)), receivedAt: received,
                sessionStartedAt: start, lastAcceptedAt: nil), .staleOrFuture)
            XCTAssertEqual(StudySampleValidator.assess(
                location(time: received.addingTimeInterval(0.01)), receivedAt: received,
                sessionStartedAt: start, lastAcceptedAt: nil), .staleOrFuture)
            XCTAssertEqual(StudySampleValidator.assess(
                location(time: start.addingTimeInterval(-0.01)), receivedAt: start,
                sessionStartedAt: start, lastAcceptedAt: nil), .beforeSession)
        }
    }

    func testCaptureIsOptInBoundedAndRetainsLegacyForwardedIndex() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fog-study-tests-\(UUID().uuidString)")
        let defaultsSuite = "fog-study-tests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let defaults = UserDefaults(suiteName: defaultsSuite)!
            let diagnostics = LocationStudyDiagnostics(
                isStudyApp: true, directoryURL: directory, defaults: defaults
            )
            let start = Date(timeIntervalSince1970: 1_000)
            try diagnostics.startCapture(at: start)
            // Deliberately out of order: assessment sorts by timestamp, while legacy
            // delivery must still identify the final element of the original batch.
            let newer = location(time: start.addingTimeInterval(12))
            let older = location(time: start.addingTimeInterval(10))
            diagnostics.recordBatch([newer, older],
                                    receivedAt: start.addingTimeInterval(13),
                                    sessionStartedAt: start)
            diagnostics.stopCapture(at: start.addingTimeInterval(14))
            XCTAssertFalse(diagnostics.isCapturing)
            let data = try Data(contentsOf: diagnostics.currentFileURL!)
            let lines = data.split(separator: 0x0A)
            let samples = try lines.compactMap { line -> [String: Any]? in
                let json = try JSONSerialization.jsonObject(with: Data(line)) as! [String: Any]
                return json["kind"] as? String == "sample" ? json : nil
            }
            XCTAssertEqual(samples.count, 2)
            XCTAssertEqual(samples.first { $0["index"] as? Int == 1 }?["forwarded"] as? Bool, true)
            XCTAssertEqual(samples.first { $0["index"] as? Int == 0 }?["forwarded"] as? Bool, false)
            XCTAssertEqual(samples.map { $0["shadowDecision"] as? String }, ["accepted", "accepted"])
        }
    }

    func testNormalAppCannotStartCapture() async {
        await MainActor.run {
            let diagnostics = LocationStudyDiagnostics(isStudyApp: false)
            do {
                try diagnostics.startCapture()
                XCTFail("The normal app must not start location capture")
            } catch {
                XCTAssertNotNil(error as? LocationStudyDiagnostics.CaptureError)
            }
            XCTAssertFalse(diagnostics.isCapturing)
        }
    }
}
