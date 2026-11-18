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

    func testExpiredActiveCaptureClearsSavedStateAndCanStartAgain() async throws {
        try await checkMissingCapture(expired: true, active: true)
    }

    func testExternallyMissingActiveCaptureClearsSavedStateAndCanStartAgain() async throws {
        try await checkMissingCapture(expired: false, active: true)
    }

    func testMissingCompletedCaptureClearsSavedStateAndCanStartAgain() async throws {
        try await checkMissingCapture(expired: false, active: false)
    }

    private func checkMissingCapture(expired: Bool, active: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fog-study-tests-\(UUID().uuidString)")
        let suite = "fog-study-tests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let file = directory.appendingPathComponent("location-expired.jsonl")
            let start = Date().addingTimeInterval(-8 * 86_400)
            defaults.set(file.lastPathComponent, forKey: "locationStudy.fileName")
            defaults.set(start, forKey: "locationStudy.startedAt")
            defaults.set(start.addingTimeInterval(60), forKey: "locationStudy.endedAt")
            defaults.set(active, forKey: "locationStudy.active")
            if expired {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data("{}\n".utf8).write(to: file)
                try FileManager.default.setAttributes([.modificationDate: start], ofItemAtPath: file.path)
            }

            let diagnostics = LocationStudyDiagnostics(
                isStudyApp: true, directoryURL: directory, defaults: defaults
            )
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
            XCTAssertFalse(diagnostics.isCapturing)
            XCTAssertFalse(defaults.bool(forKey: "locationStudy.active"))
            for key in ["fileName", "startedAt", "endedAt"] {
                XCTAssertNil(defaults.object(forKey: "locationStudy.\(key)"))
            }
            XCTAssertNil(diagnostics.currentFileURL)
            XCTAssertNil(diagnostics.captureStartedAt)
            XCTAssertNil(diagnostics.captureEndedAt)
            XCTAssertTrue(diagnostics.lastError?.contains("expired or is missing") == true)

            // A later relaunch must not keep rediscovering stale metadata.
            let relaunched = LocationStudyDiagnostics(
                isStudyApp: true, directoryURL: directory, defaults: defaults
            )
            XCTAssertNil(relaunched.lastError)
            try diagnostics.startCapture()
            XCTAssertTrue(diagnostics.isCapturing)
            XCTAssertNil(diagnostics.lastError)
            XCTAssertNotEqual(diagnostics.currentFileURL, file)
            diagnostics.stopCapture()
        }
    }

    func testFreshActiveCaptureResumesOnRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fog-study-tests-\(UUID().uuidString)")
        let suite = "fog-study-tests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let start = Date()
            let original = LocationStudyDiagnostics(
                isStudyApp: true, directoryURL: directory, defaults: defaults
            )
            try original.startCapture(at: start)
            original.stopCapture()
            // Model the saved state left by a process exiting during capture.
            defaults.set(true, forKey: "locationStudy.active")
            defaults.removeObject(forKey: "locationStudy.endedAt")
            let resumed = LocationStudyDiagnostics(
                isStudyApp: true, directoryURL: directory, defaults: defaults
            )
            XCTAssertTrue(resumed.isCapturing)
            XCTAssertEqual(resumed.currentFileURL, original.currentFileURL)
            XCTAssertEqual(resumed.captureStartedAt, start)
            XCTAssertNil(resumed.captureEndedAt)
            XCTAssertNil(resumed.lastError)
            resumed.stopCapture()
            let contents = try String(contentsOf: resumed.currentFileURL!, encoding: .utf8)
            XCTAssertTrue(contents.contains("process_relaunch"))
        }
    }

    func testNormalAppDoesNotCleanUpOrResumeSavedStudyCapture() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fog-study-tests-\(UUID().uuidString)")
        let suite = "fog-study-tests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let file = directory.appendingPathComponent("location-expired.jsonl")
            let start = Date().addingTimeInterval(-8 * 86_400)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("{}\n".utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: start], ofItemAtPath: file.path)
            defaults.set(file.lastPathComponent, forKey: "locationStudy.fileName")
            defaults.set(start, forKey: "locationStudy.startedAt")
            defaults.set(true, forKey: "locationStudy.active")

            let diagnostics = LocationStudyDiagnostics(
                isStudyApp: false, directoryURL: directory, defaults: defaults
            )
            XCTAssertFalse(diagnostics.isCapturing)
            XCTAssertNil(diagnostics.currentFileURL)
            XCTAssertNil(diagnostics.lastError)
            XCTAssertTrue(defaults.bool(forKey: "locationStudy.active"))
            XCTAssertEqual(defaults.string(forKey: "locationStudy.fileName"), file.lastPathComponent)
            XCTAssertEqual(defaults.object(forKey: "locationStudy.startedAt") as? Date, start)
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        }
    }
}
