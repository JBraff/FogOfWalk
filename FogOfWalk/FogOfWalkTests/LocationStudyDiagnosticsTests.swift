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
            defer { defaults.removePersistentDomain(forName: defaultsSuite) }
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

    private typealias Key = LocationStudyDiagnostics.DefaultsKey

    /// Runs `body` on the main actor with a fresh Study directory and defaults suite.
    private func withStudyFixture(
        _ body: @MainActor (URL, UserDefaults) throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fog-study-tests-\(UUID().uuidString)")
        let suite = "fog-study-tests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            try body(directory, defaults)
        }
    }

    /// Writes a capture file whose modification date is past the retention limit.
    private func writeExpiredCapture(in directory: URL, modified: Date) throws -> URL {
        let file = directory.appendingPathComponent("location-expired.jsonl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{}\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        return file
    }

    func testExpiredActiveCaptureClearsSavedStateAndCanStartAgain() async throws {
        try await checkMissingCapture(expired: true, active: true)
    }

    func testExternallyMissingActiveCaptureClearsSavedStateAndCanStartAgain() async throws {
        try await checkMissingCapture(expired: false, active: true)
    }

    func testMissingCompletedCaptureClearsSavedStateQuietly() async throws {
        try await checkMissingCapture(expired: false, active: false)
    }

    func testExpiredCompletedCaptureClearsSavedStateQuietly() async throws {
        try await checkMissingCapture(expired: true, active: false)
    }

    private func checkMissingCapture(expired: Bool, active: Bool) async throws {
        try await withStudyFixture { directory, defaults in
            let start = Date().addingTimeInterval(-8 * 86_400)
            let file = expired
                ? try writeExpiredCapture(in: directory, modified: start)
                : directory.appendingPathComponent("location-expired.jsonl")
            defaults.set(file.lastPathComponent, forKey: Key.fileName)
            defaults.set(start, forKey: Key.startedAt)
            defaults.set(start.addingTimeInterval(60), forKey: Key.endedAt)
            defaults.set(active, forKey: Key.active)

            let diagnostics = LocationStudyDiagnostics(
                isStudyApp: true, directoryURL: directory, defaults: defaults
            )
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
            XCTAssertFalse(diagnostics.isCapturing)
            XCTAssertFalse(defaults.bool(forKey: Key.active))
            for key in [Key.fileName, Key.startedAt, Key.endedAt] {
                XCTAssertNil(defaults.object(forKey: key))
            }
            XCTAssertNil(diagnostics.currentFileURL)
            XCTAssertNil(diagnostics.captureStartedAt)
            XCTAssertNil(diagnostics.captureEndedAt)
            if active {
                XCTAssertTrue(diagnostics.lastError?.contains("expired or is missing") == true)
            } else {
                XCTAssertNil(diagnostics.lastError)
            }

            // A later relaunch must not rediscover stale metadata, and can start afresh.
            let relaunched = LocationStudyDiagnostics(
                isStudyApp: true, directoryURL: directory, defaults: defaults
            )
            XCTAssertNil(relaunched.lastError)
            XCTAssertFalse(relaunched.isCapturing)
            XCTAssertNil(relaunched.currentFileURL)
            XCTAssertNil(relaunched.captureStartedAt)
            XCTAssertNil(relaunched.captureEndedAt)
            try relaunched.startCapture()
            XCTAssertTrue(relaunched.isCapturing)
            let newFile = try XCTUnwrap(relaunched.currentFileURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: newFile.path))
            XCTAssertEqual(defaults.string(forKey: Key.fileName), newFile.lastPathComponent)
            XCTAssertTrue(defaults.bool(forKey: Key.active))
            relaunched.stopCapture()
        }
    }

    func testFailedStartReplacesMissingCaptureNotice() async throws {
        try await withStudyFixture { directory, defaults in
            defaults.set("location-gone.jsonl", forKey: Key.fileName)
            defaults.set(true, forKey: Key.active)
            let diagnostics = LocationStudyDiagnostics(
                isStudyApp: true, directoryURL: directory, defaults: defaults
            )
            XCTAssertNotNil(diagnostics.lastError)
            // A file where the directory should be makes startCapture throw.
            try FileManager.default.removeItem(at: directory)
            try Data().write(to: directory)
            XCTAssertThrowsError(try diagnostics.startCapture())
            // Settings prefers lastError, so the stale notice must not hide the failure.
            XCTAssertNil(diagnostics.lastError)
            XCTAssertFalse(diagnostics.isCapturing)
        }
    }

    func testFreshActiveCaptureResumesOnRelaunch() async throws {
        try await withStudyFixture { directory, defaults in
            let start = Date()
            let original = LocationStudyDiagnostics(
                isStudyApp: true, directoryURL: directory, defaults: defaults
            )
            try original.startCapture(at: start)
            original.stopCapture()
            // Model the saved state left by a process exiting during capture.
            defaults.set(true, forKey: Key.active)
            defaults.removeObject(forKey: Key.endedAt)
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
        try await withStudyFixture { directory, defaults in
            let start = Date().addingTimeInterval(-8 * 86_400)
            let file = try writeExpiredCapture(in: directory, modified: start)
            defaults.set(file.lastPathComponent, forKey: Key.fileName)
            defaults.set(start, forKey: Key.startedAt)
            defaults.set(true, forKey: Key.active)

            let diagnostics = LocationStudyDiagnostics(
                isStudyApp: false, directoryURL: directory, defaults: defaults
            )
            XCTAssertFalse(diagnostics.isCapturing)
            XCTAssertNil(diagnostics.currentFileURL)
            XCTAssertNil(diagnostics.lastError)
            XCTAssertTrue(defaults.bool(forKey: Key.active))
            XCTAssertEqual(defaults.string(forKey: Key.fileName), file.lastPathComponent)
            XCTAssertEqual(defaults.object(forKey: Key.startedAt) as? Date, start)
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        }
    }
}
