import XCTest
import CoreData
import CoreLocation
@testable import FogOfWalk

// Observable services/stores must be created and released in async Task context.
final class StationaryLocationSourceTests: XCTestCase {
    func testNormalIdentityIgnoresPersistedLiveSourceAndRefusesSelection() async {
        await MainActor.run {
            let h = LiveTestHarness(isStudyApp: false, persistedSource: "liveUpdates")
            XCTAssertEqual(h.service.studyLocationSource, .legacy)
            XCTAssertFalse(h.service.setStudyLocationSource(.liveUpdates))
            h.service.requestPermissionAndStart()
            XCTAssertTrue(h.manager.didCallStartUpdatingLocation)
            XCTAssertTrue(h.factory.sources.isEmpty)
            XCTAssertTrue(h.service.usesMapLocation)
        }
    }

    func testAbsentAndUnknownSelectionsKeepLegacyDefault() async {
        await MainActor.run {
            for value in [nil, "future-source"] as [String?] {
                let h = LiveTestHarness(persistedSource: value)
                XCTAssertEqual(h.service.studyLocationSource, .legacy)
                h.service.requestPermissionAndStart()
                XCTAssertTrue(h.manager.didCallStartUpdatingLocation)
                XCTAssertTrue(h.factory.sources.isEmpty)
            }
        }
    }

    func testSelectionStopsLegacyAndMapConsumersAndPersists() async {
        await MainActor.run {
            let h = LiveTestHarness()
            h.service.requestPermissionAndStart()
            var mapEnabled = true
            h.service.installStudyMapControl { mapEnabled = $0 }
            XCTAssertTrue(h.service.setStudyLocationSource(.liveUpdates))
            XCTAssertEqual(h.factory.sources.count, 1)
            XCTAssertTrue(h.manager.didCallStopUpdatingLocation)
            XCTAssertTrue(h.manager.didCallStopMonitoringSignificantLocationChanges)
            XCTAssertFalse(h.manager.allowsBackgroundLocationUpdates)
            XCTAssertFalse(mapEnabled)
            XCTAssertEqual(h.defaults.string(forKey: StudyLocationSource.defaultsKey), "liveUpdates")
            // A replacement map must not start a second location consumer.
            h.service.installStudyMapControl { mapEnabled = $0 }
            XCTAssertFalse(mapEnabled)
            XCTAssertEqual(h.factory.sources.count, 1)
        }
    }

    func testPersistedLiveStartsOnceAcrossLaunchAndForegroundRearm() async {
        await MainActor.run {
            let h = LiveTestHarness(persistedSource: "liveUpdates")
            h.service.restartIfAuthorized() // app-init background restoration path
            h.service.requestPermissionAndStart() // SwiftUI task
            h.service.restartIfAuthorized()
            XCTAssertEqual(h.factory.sources.count, 1)
            XCTAssertFalse(h.manager.didCallStartUpdatingLocation)
            XCTAssertFalse(h.manager.didCallStartMonitoringSignificantLocationChanges)
        }
    }

    func testPersistedOffPreventsLiveStartupUntilExplicitRestore() async {
        await MainActor.run {
            let h = LiveTestHarness(persistedSource: "liveUpdates", disabled: true)
            h.service.requestPermissionAndStart()
            h.service.restartIfAuthorized()
            XCTAssertTrue(h.factory.sources.isEmpty)
            XCTAssertTrue(h.service.setStudyTrackingDisabled(false))
            XCTAssertEqual(h.factory.sources.count, 1)
            XCTAssertFalse(h.service.usesMapLocation)
        }
    }

    func testStationaryStateKeepsSourceAliveAndForegroundDoesNotResetIt() async {
        await MainActor.run {
            let h = LiveTestHarness(persistedSource: "liveUpdates")
            h.service.requestPermissionAndStart()
            XCTAssertNil(h.service.studyStationary)
            h.source.emit(stationary: true)
            XCTAssertEqual(h.service.studyStationary, true)
            XCTAssertTrue(h.service.isPaused)
            XCTAssertEqual(h.source.stops, 0)
            h.service.restartIfAuthorized()
            XCTAssertEqual(h.factory.sources.count, 1)
            XCTAssertEqual(h.service.studyStationary, true)
            // A nonstationary event without a fix does not claim fresh delivery.
            h.source.emit(stationary: false)
            XCTAssertFalse(h.service.isPaused)
            XCTAssertNil(h.service.currentLocation)
            XCTAssertTrue(h.diagnostics.batches.isEmpty)
        }
    }

    func testResumedFreshLocationsReachRealExplorationWithoutAMap() async {
        await MainActor.run {
            let h = LiveTestHarness(persistedSource: "liveUpdates")
            let container = makeInMemoryContainer()
            let store = ExplorationStore(container: container)
            let landmarks = LandmarkStore(container: container)
            let recorder = ExplorationRecorder(store: store, landmarks: landmarks, diagnostics: h.diagnostics)
            h.service.onLocationUpdate = { recorder.record($0) }
            h.service.requestPermissionAndStart()
            let departure = sample(latitude: 40)
            h.source.emit(location: departure, stationary: true)
            XCTAssertTrue(h.service.isPaused, "The final stationary fix must not clear the framework state")
            let resumed = sample(latitude: 40.003)
            h.source.emit(location: resumed, stationary: false)
            XCTAssertFalse(h.service.isPaused)
            XCTAssertEqual(h.service.currentLocation, resumed)
            XCTAssertEqual(store.visitedCellsCache, Set([
                GridMath.cellID(for: departure.coordinate), GridMath.cellID(for: resumed.coordinate)
            ]), "Only actual sample cells should be recorded, with no interpolated route")
            XCTAssertEqual(h.diagnostics.downstream.count, 2)
            XCTAssertEqual(h.diagnostics.batches.count, 2)
        }
    }

    func testOldGenerationCannotDeliverOrEndReplacementSource() async {
        await MainActor.run {
            let h = LiveTestHarness(persistedSource: "liveUpdates")
            h.service.requestPermissionAndStart()
            let old = h.source
            h.service.setStudyTrackingDisabled(true)
            XCTAssertEqual(old.stops, 1)
            h.service.setStudyTrackingDisabled(false)
            XCTAssertEqual(h.factory.sources.count, 2)
            old.emit(location: sample(), stationary: true)
            old.handler?(.ended("old error"))
            XCTAssertNil(h.service.currentLocation)
            XCTAssertNil(h.service.studyStationary)
            XCTAssertEqual(h.source.stops, 0)
            h.source.emit(location: sample(), stationary: false)
            XCTAssertEqual(h.diagnostics.batches.count, 1)
        }
    }

    func testSwitchBackToLegacyStopsLiveAndRejectsLateEvents() async {
        await MainActor.run {
            let h = LiveTestHarness(persistedSource: "liveUpdates")
            h.service.requestPermissionAndStart()
            let old = h.source
            var enabled = false
            h.service.installStudyMapControl { enabled = $0 }
            h.service.setStudyLocationSource(.legacy)
            old.emit(location: sample(), stationary: true)
            XCTAssertEqual(old.stops, 1)
            XCTAssertNil(h.service.currentLocation)
            XCTAssertTrue(h.manager.didCallStartUpdatingLocation)
            XCTAssertTrue(h.manager.didCallStartMonitoringSignificantLocationChanges)
            XCTAssertTrue(enabled)
        }
    }

    func testQueuedLegacyCallbacksCannotAlterLiveSource() async {
        let h = await MainActor.run { () -> LiveTestHarness in
            let h = LiveTestHarness()
            h.service.locationManager(CLLocationManager(), didUpdateLocations: [sample()])
            h.service.locationManagerDidPauseLocationUpdates(CLLocationManager())
            h.service.setStudyLocationSource(.liveUpdates)
            h.source.emit(stationary: false)
            return h
        }
        try? await Task.sleep(for: .milliseconds(30))
        await MainActor.run {
            XCTAssertNil(h.service.currentLocation)
            XCTAssertFalse(h.service.isPaused)
            XCTAssertTrue(h.diagnostics.batches.isEmpty)
            h.source.emit(stationary: true)
            h.service.locationManagerDidResumeLocationUpdates(CLLocationManager())
        }
        try? await Task.sleep(for: .milliseconds(30))
        await MainActor.run { XCTAssertTrue(h.service.isPaused) }
    }

    func testPermissionRevocationStopsLiveAndGrantCreatesNewGeneration() async {
        let h = await MainActor.run { () -> LiveTestHarness in
            let h = LiveTestHarness(persistedSource: "liveUpdates")
            h.service.requestPermissionAndStart()
            h.manager.authorizationStatus = .denied
            h.service.locationManagerDidChangeAuthorization(CLLocationManager())
            return h
        }
        try? await Task.sleep(for: .milliseconds(30))
        await MainActor.run {
            XCTAssertTrue(h.service.isPermissionDenied)
            XCTAssertEqual(h.source.stops, 1)
            h.source.emit(location: sample(), stationary: false)
            XCTAssertTrue(h.diagnostics.batches.isEmpty)
            h.manager.authorizationStatus = .authorizedAlways
            h.service.locationManagerDidChangeAuthorization(CLLocationManager())
        }
        try? await Task.sleep(for: .milliseconds(30))
        await MainActor.run {
            XCTAssertFalse(h.service.isPermissionDenied)
            XCTAssertEqual(h.factory.sources.count, 2)
            h.source.emit(location: sample(), stationary: false)
            XCTAssertEqual(h.diagnostics.batches.count, 1)
        }
    }

    func testWhenInUseWaitsForAlwaysWithoutStartingAnyTracker() async {
        let h = await MainActor.run { () -> LiveTestHarness in
            let h = LiveTestHarness(persistedSource: "liveUpdates", status: .authorizedWhenInUse)
            h.service.requestPermissionAndStart()
            h.service.restartIfAuthorized()
            h.service.locationManagerDidChangeAuthorization(CLLocationManager())
            return h
        }
        try? await Task.sleep(for: .milliseconds(30))
        await MainActor.run {
            XCTAssertTrue(h.factory.sources.isEmpty)
            XCTAssertTrue(h.manager.didCallRequestAlwaysAuthorization)
            XCTAssertFalse(h.manager.didCallStartUpdatingLocation)
            XCTAssertFalse(h.manager.allowsBackgroundLocationUpdates)
        }
    }

    func testManualOffCancelsLiveAndSuppressesRearmAndLateEvents() async {
        await MainActor.run {
            let h = LiveTestHarness(persistedSource: "liveUpdates")
            h.service.requestPermissionAndStart()
            let source = h.source
            h.service.setStudyTrackingDisabled(true)
            h.service.restartIfAuthorized()
            source.emit(location: sample(), stationary: false)
            XCTAssertEqual(source.stops, 1)
            XCTAssertEqual(h.factory.sources.count, 1)
            XCTAssertNil(h.service.currentLocation)
            XCTAssertFalse(h.service.usesMapLocation)
        }
    }

    func testSourceErrorStopsUntilExplicitForegroundRecovery() async {
        await MainActor.run {
            let h = LiveTestHarness(persistedSource: "liveUpdates")
            h.service.requestPermissionAndStart()
            let source = h.source
            source.handler?(.ended("test error"))
            XCTAssertEqual(source.stops, 1)
            XCTAssertTrue(h.service.isPaused)
            XCTAssertTrue(h.service.studySourceStatus.contains("Source ended"))
            XCTAssertFalse(h.manager.didCallStartUpdatingLocation)
            source.emit(location: sample(), stationary: false)
            XCTAssertNil(h.service.currentLocation)
            h.service.restartIfAuthorized()
            XCTAssertEqual(h.factory.sources.count, 2)
            h.source.emit(location: sample(), stationary: false)
            XCTAssertNotNil(h.service.currentLocation)
        }
    }

    func testCachedFutureInvalidAndDuplicateSamplesCannotClaimResume() async {
        await MainActor.run {
            let h = LiveTestHarness(persistedSource: "liveUpdates")
            let beforeSession = sample()
            h.service.requestPermissionAndStart()
            for location in [beforeSession, sample(time: Date().addingTimeInterval(-20)),
                             sample(time: Date().addingTimeInterval(20)), sample(accuracy: -1)] {
                h.source.emit(location: location, stationary: false)
            }
            XCTAssertTrue(h.diagnostics.batches.isEmpty)
            let fresh = sample()
            h.source.emit(location: fresh, stationary: false)
            h.source.emit(location: fresh, stationary: false)
            XCTAssertEqual(h.diagnostics.batches.count, 1)
        }
    }

    func testCaptureLocksSourceAndStopLoggingLeavesSourceRunning() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let h = LiveTestHarness(persistedSource: "liveUpdates")
            let diagnostics = LocationStudyDiagnostics(isStudyApp: true, directoryURL: directory, defaults: h.defaults)
            let service = LocationService(manager: h.manager, diagnostics: diagnostics, isStudyApp: true,
                                          defaults: h.defaults, makeStationarySource: { h.factory.make() })
            service.requestPermissionAndStart()
            h.source.emit(stationary: true)
            try diagnostics.startCapture()
            service.recordStudyTrackingState()
            XCTAssertFalse(service.setStudyLocationSource(.legacy))
            XCTAssertFalse(service.setStudyTrackingDisabled(true))
            h.source.emit(location: sample(), stationary: false)
            diagnostics.stopCapture()
            XCTAssertEqual(h.source.stops, 0)
            XCTAssertEqual(service.studyLocationSource, .liveUpdates)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let events = try Data(contentsOf: diagnostics.currentFileURL!).split(separator: 0x0A).map {
                try decoder.decode(LocationStudyDiagnostics.Event.self, from: Data($0))
            }
            XCTAssertTrue(events.contains { $0.kind == "capture_start" && $0.detail == "liveUpdates" })
            XCTAssertTrue(events.contains { $0.kind == "live_stationary_snapshot" && $0.detail == "true" })
            XCTAssertTrue(events.contains { $0.kind == "live_stationary" && $0.detail == "false" })
            XCTAssertTrue(events.contains { $0.kind == "batch" && $0.detail == "liveUpdates" })
            service.setStudyTrackingDisabled(true)
        }
    }

    private func makeInMemoryContainer() -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "FogOfWalk")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error { XCTFail("In-memory store failed: \(error)") }
        }
        return container
    }

    private func sample(latitude: Double = 40, time: Date = Date(), accuracy: Double = 5) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: -74),
                   altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 5, timestamp: time)
    }
}

@MainActor
private final class LiveTestHarness {
    let manager = MockLocationManager()
    let factory = LiveTestSourceFactory()
    let diagnostics = LiveTestDiagnostics()
    let defaults = UserDefaults(suiteName: "fog-live-test-\(UUID().uuidString)")!
    let service: LocationService
    var source: LiveTestSource { factory.sources.last! }

    init(isStudyApp: Bool = true, persistedSource: String? = nil, disabled: Bool = false,
         status: CLAuthorizationStatus = .authorizedAlways) {
        defaults.set(persistedSource, forKey: StudyLocationSource.defaultsKey)
        defaults.set(disabled, forKey: LocationService.studyTrackingDisabledKey)
        manager.authorizationStatus = status
        let factory = self.factory
        service = LocationService(manager: manager, diagnostics: diagnostics, isStudyApp: isStudyApp,
                                  defaults: defaults, makeStationarySource: { factory.make() })
    }
}

@MainActor
private final class LiveTestSourceFactory {
    var sources: [LiveTestSource] = []
    func make() -> LiveTestSource {
        let source = LiveTestSource()
        sources.append(source)
        return source
    }
}

@MainActor
private final class LiveTestSource: StationaryLocationSource {
    var handler: (@MainActor (StationaryLocationEvent) -> Void)?
    var stops = 0
    func start(_ receive: @escaping @MainActor (StationaryLocationEvent) -> Void) { handler = receive }
    func stop() { stops += 1 } // Retain callback to model late native deliveries.
    func emit(location: CLLocation? = nil, stationary: Bool) {
        handler?(.update(location: location, stationary: stationary, diagnostic: "test"))
    }
}

@MainActor
private final class LiveTestDiagnostics: LocationDiagnosticRecording {
    var isCapturing = false
    var batches: [[CLLocation]] = []
    var downstream: [CellID] = []
    func recordLifecycle(_ name: String, detail: String?) {}
    func recordBatch(_ locations: [CLLocation], receivedAt: Date, sessionStartedAt: Date?) { batches.append(locations) }
    func recordDownstream(cell: CellID, isNew: Bool, discoveries: Int, dayRollover: Bool) { downstream.append(cell) }
}
