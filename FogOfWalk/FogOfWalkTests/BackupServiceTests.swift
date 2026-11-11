import CoreData
import XCTest
@testable import FogOfWalk

final class BackupServiceTests: XCTestCase {

    private func samplePayload() -> BackupPayload {
        BackupPayload(
            schemaVersion: BackupPayload.currentSchemaVersion,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            visitedCells: [
                BackupVisitedCell(cellX: 1, cellY: 2, cellSizeMeters: 50.0,
                                   firstVisited: Date(timeIntervalSince1970: 1_600_000_000),
                                   locality: "Springfield", state: "Illinois", country: "United States")
            ],
            landmarks: [
                BackupLandmark(identifier: "Q42", firstDiscovered: Date(timeIntervalSince1970: 1_650_000_000))
            ]
        )
    }

    func testEncodeDecodeRoundTrip() throws {
        let payload = samplePayload()
        let data = try BackupService.encode(payload)
        let decoded = try BackupService.decode(data)
        XCTAssertEqual(decoded, payload)
    }

    func testDecodeRejectsUnsupportedSchemaVersion() throws {
        var payload = samplePayload()
        payload = BackupPayload(schemaVersion: 999, exportedAt: payload.exportedAt,
                                 visitedCells: payload.visitedCells, landmarks: payload.landmarks)
        let data = try BackupService.encode(payload)

        XCTAssertThrowsError(try BackupService.decode(data)) { error in
            guard let backupError = error as? BackupError else {
                return XCTFail("Expected BackupError, got \(error)")
            }
            XCTAssertEqual(backupError, .unsupportedSchemaVersion(999))
        }
    }

    func testDecodeAcceptsOlderSchemaVersion() throws {
        // A v1 backup file predates the `state`/`country` fields entirely — the keys are
        // absent from the JSON, not merely null. `BackupVisitedCell.state`/`.country` default
        // to nil, so this must still decode cleanly and be treated as an old-but-supported file.
        let json = """
        {
            "schemaVersion": 1,
            "exportedAt": "2023-11-14T22:13:20Z",
            "visitedCells": [
                { "cellX": 1, "cellY": 2, "cellSizeMeters": 50.0,
                  "firstVisited": "2020-09-13T12:26:40Z", "locality": "Springfield" }
            ],
            "landmarks": [
                { "identifier": "Q42", "firstDiscovered": "2022-04-15T21:20:00Z" }
            ]
        }
        """
        let data = Data(json.utf8)

        let decoded = try BackupService.decode(data)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.visitedCells.first?.locality, "Springfield")
        XCTAssertNil(decoded.visitedCells.first?.state)
        XCTAssertNil(decoded.visitedCells.first?.country)
    }

    func testDecodeRejectsMalformedJSON() {
        let garbage = Data("not json".utf8)
        XCTAssertThrowsError(try BackupService.decode(garbage))
    }

    // MARK: - Helpers (Core Data)

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

    // MARK: - exportData / merge

    func testExportDataIncludesVisitedCellsAndDiscoveredLandmarksOnly() async throws {
        try await MainActor.run {
            let explorationStore = ExplorationStore(container: makeInMemoryContainer())
            explorationStore.configure()
            explorationStore.addCell(CellID(x: 4, y: 4))

            let landmarkStore = LandmarkStore(container: makeInMemoryContainer())
            landmarkStore.addLandmarks(
                [WikidataLandmark(id: "Q1", name: "Discovered", description: nil,
                                  lat: 0, lon: 0, category: "museum", imageURL: nil),
                 WikidataLandmark(id: "Q2", name: "Undiscovered", description: nil,
                                  lat: 40, lon: -74, category: "museum", imageURL: nil)],
                visitedCells: []
            )
            _ = try landmarkStore.restoreDiscovered([(identifier: "Q1", firstDiscovered: Date(timeIntervalSince1970: 42))])

            let data = try BackupService.exportData(explorationStore: explorationStore, landmarkStore: landmarkStore)
            let payload = try BackupService.decode(data)

            XCTAssertEqual(payload.visitedCells.count, 1)
            XCTAssertEqual(payload.visitedCells.first?.cellX, 4)
            XCTAssertEqual(payload.landmarks, [BackupLandmark(identifier: "Q1", firstDiscovered: Date(timeIntervalSince1970: 42))])
        }
    }

    func testExportDataIncludesStateAndCountry() async throws {
        try await MainActor.run {
            let explorationStore = ExplorationStore(container: makeInMemoryContainer())
            explorationStore.configure()
            explorationStore.addCell(CellID(x: 4, y: 4))

            let request = NSFetchRequest<VisitedCell>(entityName: "VisitedCell")
            let cells = try? explorationStore.viewContext.fetch(request)
            cells?.first?.state = "California"
            cells?.first?.country = "United States"
            try? explorationStore.viewContext.save()

            let landmarkStore = LandmarkStore(container: makeInMemoryContainer())

            let data = try BackupService.exportData(explorationStore: explorationStore, landmarkStore: landmarkStore)
            let payload = try BackupService.decode(data)

            XCTAssertEqual(payload.visitedCells.first?.state, "California")
            XCTAssertEqual(payload.visitedCells.first?.country, "United States")
        }
    }

    func testMergeAppliesCellsAndLandmarksAndReturnsSummary() async throws {
        try await MainActor.run {
            let explorationStore = ExplorationStore(container: makeInMemoryContainer())
            explorationStore.configure()

            let landmarkStore = LandmarkStore(container: makeInMemoryContainer())
            landmarkStore.addLandmarks(
                [WikidataLandmark(id: "Q5", name: "Lighthouse", description: nil,
                                  lat: 0, lon: 0, category: "landmark", imageURL: nil)],
                visitedCells: []
            )

            let payload = BackupPayload(
                schemaVersion: BackupPayload.currentSchemaVersion,
                exportedAt: Date(),
                visitedCells: [BackupVisitedCell(cellX: 9, cellY: 9, cellSizeMeters: kCellSizeMeters,
                                                  firstVisited: Date(timeIntervalSince1970: 100), locality: nil)],
                landmarks: [BackupLandmark(identifier: "Q5", firstDiscovered: Date(timeIntervalSince1970: 200))]
            )

            let summary = try BackupService.merge(payload, into: explorationStore, landmarkStore: landmarkStore)

            XCTAssertEqual(summary, MergeSummary(cellsAdded: 1, landmarksAdded: 1))
            XCTAssertTrue(explorationStore.visitedCellsCache.contains(CellID(x: 9, y: 9)))
            XCTAssertTrue(landmarkStore.allLandmarks.first?.isDiscovered ?? false)
        }
    }

    func testExportImportRoundTripReproducesState() async throws {
        try await MainActor.run {
            let sourceExploration = ExplorationStore(container: makeInMemoryContainer())
            sourceExploration.configure()
            sourceExploration.addCell(CellID(x: 7, y: 7))

            let sourceLandmarks = LandmarkStore(container: makeInMemoryContainer())
            sourceLandmarks.addLandmarks(
                [WikidataLandmark(id: "Q7", name: "Bridge", description: nil,
                                  lat: 10, lon: 10, category: "landmark", imageURL: nil)],
                visitedCells: []
            )
            _ = try sourceLandmarks.restoreDiscovered([(identifier: "Q7", firstDiscovered: Date(timeIntervalSince1970: 300))])

            let data = try BackupService.exportData(explorationStore: sourceExploration, landmarkStore: sourceLandmarks)
            let payload = try BackupService.decode(data)

            let destExploration = ExplorationStore(container: makeInMemoryContainer())
            destExploration.configure()
            let destLandmarks = LandmarkStore(container: makeInMemoryContainer())
            destLandmarks.addLandmarks(
                [WikidataLandmark(id: "Q7", name: "Bridge", description: nil,
                                  lat: 10, lon: 10, category: "landmark", imageURL: nil)],
                visitedCells: []
            )

            _ = try BackupService.merge(payload, into: destExploration, landmarkStore: destLandmarks)

            XCTAssertTrue(destExploration.visitedCellsCache.contains(CellID(x: 7, y: 7)))
            XCTAssertTrue(destLandmarks.allLandmarks.first?.isDiscovered ?? false)
            XCTAssertEqual(destLandmarks.allLandmarks.first?.firstDiscovered, Date(timeIntervalSince1970: 300))
        }
    }

    func testMergeUsesExportedAtAsFallbackWhenFirstDiscoveredIsNil() async throws {
        try await MainActor.run {
            let explorationStore = ExplorationStore(container: makeInMemoryContainer())
            explorationStore.configure()

            let landmarkStore = LandmarkStore(container: makeInMemoryContainer())
            landmarkStore.addLandmarks(
                [WikidataLandmark(id: "Q99", name: "TestLandmark", description: nil,
                                  lat: 50, lon: 50, category: "landmark", imageURL: nil)],
                visitedCells: []
            )

            let exportedAtDate = Date(timeIntervalSince1970: 999)
            let payload = BackupPayload(
                schemaVersion: BackupPayload.currentSchemaVersion,
                exportedAt: exportedAtDate,
                visitedCells: [],
                landmarks: [BackupLandmark(identifier: "Q99", firstDiscovered: nil)]
            )

            _ = try BackupService.merge(payload, into: explorationStore, landmarkStore: landmarkStore)

            XCTAssertTrue(landmarkStore.allLandmarks.first?.isDiscovered ?? false)
            XCTAssertEqual(landmarkStore.allLandmarks.first?.firstDiscovered, exportedAtDate,
                          "When firstDiscovered is nil, merge should use payload.exportedAt as fallback")
        }
    }

    // MARK: - Replace

    @MainActor
    private func replacementFixture() throws -> (ExplorationStore, LandmarkStore) {
        let container = makeInMemoryContainer()
        let store = ExplorationStore(container: container)
        store.configure()
        _ = try store.addCells([
            BackupVisitedCell(cellX: 1, cellY: 2, cellSizeMeters: kCellSizeMeters,
                              firstVisited: Date(timeIntervalSince1970: 10), locality: "Old Town",
                              state: "Old State", country: "Old Country"),
            BackupVisitedCell(cellX: 8, cellY: 8, cellSizeMeters: kCellSizeMeters,
                              firstVisited: Date(), locality: "Removed Town")
        ])
        let landmarks = LandmarkStore(container: container, defaults: nil)
        landmarks.addLandmarks([
            WikidataLandmark(id: "Q42", name: "Museum", description: nil,
                             lat: 0, lon: 0, category: "museum", imageURL: nil),
            WikidataLandmark(id: "Q43", name: "Tower", description: nil,
                             lat: 1, lon: 1, category: "landmark", imageURL: nil)
        ], visitedCells: [])
        _ = try landmarks.restoreDiscovered([
            ("Q42", Date(timeIntervalSince1970: 10)), ("Q43", Date(timeIntervalSince1970: 20))
        ])
        return (store, landmarks)
    }

    @MainActor
    private func history(_ store: ExplorationStore, _ landmarks: LandmarkStore) throws -> BackupPayload {
        try BackupService.decode(BackupService.exportData(explorationStore: store, landmarkStore: landmarks))
    }

    private func assertSameHistory(_ actual: BackupPayload, _ expected: BackupPayload,
                                   file: StaticString = #filePath, line: UInt = #line) {
        // Fetch order and the time of the export are not user history.
        XCTAssertEqual(actual.visitedCells.sorted { $0.cellX < $1.cellX },
                       expected.visitedCells.sorted { $0.cellX < $1.cellX }, file: file, line: line)
        XCTAssertEqual(actual.landmarks.sorted { $0.identifier < $1.identifier },
                       expected.landmarks.sorted { $0.identifier < $1.identifier }, file: file, line: line)
    }

    func testReplaceOverwritesLabelsDatesAndDiscoveriesAndRefreshesCountNeutralCaches() async throws {
        try await MainActor.run {
            for highlighting in [false, true] {
                let (store, landmarks) = try replacementFixture()
                let now = Date()
                store.nowProvider = { now }
                let cutoff = Calendar.current.startOfDay(for: now)
                store.loadRecentCells(since: highlighting ? cutoff : nil)
                let generation = store.recentCellsGeneration
                let landmarkGeneration = landmarks.renderGeneration
                let payload = BackupPayload(schemaVersion: 2, exportedAt: Date(), visitedCells: [
                    BackupVisitedCell(cellX: 1, cellY: 2, cellSizeMeters: kCellSizeMeters,
                                      firstVisited: Date(), locality: "New Town", state: nil, country: "New Country"),
                    BackupVisitedCell(cellX: 9, cellY: 9, cellSizeMeters: kCellSizeMeters,
                                      firstVisited: nil, locality: nil)
                ], landmarks: [BackupLandmark(identifier: "Q42", firstDiscovered: nil)])
                var callbacks = 0
                store.onNewCell = { _ in callbacks += 1 }

                try BackupService.replace(payload, into: store, landmarkStore: landmarks, landmarkSource: EmptyLandmarkSource())

                // Compare without encode/decode's subsecond date rounding.
                let cells = try store.viewContext.fetch(VisitedCell.fetchRequest())
                let kept = try XCTUnwrap(cells.first { $0.cellX == 1 })
                XCTAssertEqual(kept.firstVisited, payload.visitedCells[0].firstVisited)
                XCTAssertEqual(kept.locality, "New Town")
                XCTAssertNil(kept.state)
                XCTAssertEqual(kept.country, "New Country")
                XCTAssertEqual(cells.first { $0.cellX == 9 }?.firstVisited, now)
                XCTAssertEqual(store.visitedCellsCache, [CellID(x: 1, y: 2), CellID(x: 9, y: 9)])
                XCTAssertEqual(store.totalVisitedCount, 2)
                XCTAssertEqual(store.todayVisitedCount, 2)
                XCTAssertEqual(store.recentCellsCache, highlighting ? [CellID(x: 1, y: 2), CellID(x: 9, y: 9)] : [])
                XCTAssertGreaterThan(store.recentCellsGeneration, generation)
                XCTAssertGreaterThan(landmarks.renderGeneration, landmarkGeneration)
                XCTAssertEqual(landmarks.totalDiscovered, 1)
                XCTAssertTrue(try XCTUnwrap(landmarks.allLandmarks.first { $0.identifier == "Q42" }).isDiscovered)
                XCTAssertEqual(landmarks.allLandmarks.first { $0.identifier == "Q42" }?.firstDiscovered, payload.exportedAt)
                let removed = try XCTUnwrap(landmarks.allLandmarks.first { $0.identifier == "Q43" })
                XCTAssertFalse(removed.isDiscovered)
                XCTAssertNil(removed.firstDiscovered)
                XCTAssertEqual(callbacks, 0)
                let stats = DiscoveryStatsModel()
                stats.refresh(context: store.viewContext)
                XCTAssertEqual(stats.allTimeTotal, 2)
                XCTAssertEqual(Set(stats.locality(for: .allTime).map(\.name)), ["New Town", "Unknown"])
                XCTAssertEqual(stats.countryStats.map(\.name), ["New Country"])
            }
        }
    }

    func testEmptyReplaceClearsHistoryAndRebuildsDiscoveryIndex() async throws {
        try await MainActor.run {
            let (store, landmarks) = try replacementFixture()
            store.loadRecentCells(since: .distantPast)
            let payload = BackupPayload(schemaVersion: 2, exportedAt: Date(), visitedCells: [], landmarks: [])
            try BackupService.replace(payload, into: store, landmarkStore: landmarks, landmarkSource: EmptyLandmarkSource())
            XCTAssertTrue(try store.viewContext.fetch(VisitedCell.fetchRequest()).isEmpty)
            XCTAssertTrue(store.visitedCellsCache.isEmpty)
            XCTAssertTrue(store.recentCellsCache.isEmpty)
            XCTAssertEqual(store.totalVisitedCount, 0)
            XCTAssertEqual(store.todayVisitedCount, 0)
            XCTAssertEqual(landmarks.totalDiscovered, 0)
            XCTAssertTrue(landmarks.allLandmarks.allSatisfy { !$0.isDiscovered && $0.firstDiscovered == nil })
            // Cleared discoveries must remain discoverable on a later walk.
            XCTAssertEqual(landmarks.checkDiscovery(newCell: CellID(x: 0, y: 0)).map(\.identifier), ["Q42"])
        }
    }

    func testReplaceSaveFailureRollsBackBothEntitiesAndPreservesCaches() async throws {
        try await MainActor.run {
            let (store, landmarks) = try replacementFixture()
            store.loadRecentCells(since: .distantPast)
            let before = try history(store, landmarks)
            let visited = store.visitedCellsCache
            let recent = store.recentCellsCache
            let generation = store.recentCellsGeneration
            let persistentStore = try XCTUnwrap(store.container.persistentStoreCoordinator.persistentStores.first)
            persistentStore.isReadOnly = true
            XCTAssertThrowsError(try BackupService.replace(samplePayload(), into: store, landmarkStore: landmarks, landmarkSource: EmptyLandmarkSource()))
            assertSameHistory(try history(store, landmarks), before)
            XCTAssertEqual(store.visitedCellsCache, visited)
            XCTAssertEqual(store.recentCellsCache, recent)
            XCTAssertEqual(store.recentCellsGeneration, generation)
            XCTAssertEqual(store.totalVisitedCount, 2)
            XCTAssertEqual(landmarks.totalDiscovered, 2)
            XCTAssertFalse(store.viewContext.hasChanges)
            persistentStore.isReadOnly = false
            // Retrying after a failed save must work and restore exact file dates/labels.
            try BackupService.replace(samplePayload(), into: store, landmarkStore: landmarks, landmarkSource: EmptyLandmarkSource())
            assertSameHistory(try history(store, landmarks), samplePayload())
        }
    }

    func testMalformedAndFutureFilesLeaveExistingHistoryUnchanged() async throws {
        try await MainActor.run {
            let (store, landmarks) = try replacementFixture()
            let before = try history(store, landmarks)
            let future = BackupPayload(schemaVersion: 999, exportedAt: Date(), visitedCells: [], landmarks: [])
            for data in [Data("not json".utf8), try BackupService.encode(future)] {
                XCTAssertThrowsError(try BackupService.replace(BackupService.decode(data), into: store, landmarkStore: landmarks, landmarkSource: EmptyLandmarkSource()))
                assertSameHistory(try history(store, landmarks), before)
            }
        }
    }

    func testReplaceRejectsUnresolvableLandmarkAndDuplicateRecordsWithoutChanges() async throws {
        try await MainActor.run {
            let (store, landmarks) = try replacementFixture()
            let before = try history(store, landmarks)
            let cell = samplePayload().visitedCells[0]
            for payload in [
                BackupPayload(schemaVersion: 2, exportedAt: Date(), visitedCells: [],
                              landmarks: [BackupLandmark(identifier: "QMissing", firstDiscovered: nil)]),
                BackupPayload(schemaVersion: 2, exportedAt: Date(), visitedCells: [cell, cell], landmarks: []),
                BackupPayload(schemaVersion: 2, exportedAt: Date(), visitedCells: [],
                              landmarks: [samplePayload().landmarks[0], samplePayload().landmarks[0]])
            ] {
                XCTAssertThrowsError(try BackupService.replace(payload, into: store, landmarkStore: landmarks,
                                                               landmarkSource: EmptyLandmarkSource()))
                assertSameHistory(try history(store, landmarks), before)
            }
        }
    }

    func testReplaceRejectsSeparateContextsAndPreservesPendingEdits() async throws {
        try await MainActor.run {
            let (store, landmarks) = try replacementFixture()
            let before = try history(store, landmarks)
            let separate = LandmarkStore(container: makeInMemoryContainer(), defaults: nil)
            XCTAssertThrowsError(try BackupService.replace(samplePayload(), into: store, landmarkStore: separate, landmarkSource: EmptyLandmarkSource()))
            assertSameHistory(try history(store, landmarks), before)
            let cell = try XCTUnwrap(store.viewContext.fetch(VisitedCell.fetchRequest()).first)
            cell.locality = "Pending edit"
            XCTAssertThrowsError(try BackupService.replace(samplePayload(), into: store, landmarkStore: landmarks, landmarkSource: EmptyLandmarkSource()))
            XCTAssertEqual(cell.locality, "Pending edit")
            XCTAssertTrue(store.viewContext.hasChanges)
            store.viewContext.rollback()
        }
    }

    func testReplaceResolvesLandmarksNotYetIngestedFromReferenceDatabase() async throws {
        try await MainActor.run {
            let (store, landmarks) = try replacementFixture()
            let url = try makeTestDatabase(landmarks: [
                ("Q99", "Distant Museum", nil, 30, 40, "museum", nil)
            ])
            defer { try? FileManager.default.removeItem(at: url) }
            let source = try BundledLandmarkSource(databaseURL: url)
            let payload = BackupPayload(schemaVersion: 2, exportedAt: Date(), visitedCells: [],
                                        landmarks: [BackupLandmark(identifier: "Q99", firstDiscovered: Date(timeIntervalSince1970: 100))])
            try BackupService.replace(payload, into: store, landmarkStore: landmarks, landmarkSource: source)
            assertSameHistory(try history(store, landmarks), payload)
            let restored = try XCTUnwrap(landmarks.allLandmarks.first { $0.identifier == "Q99" })
            XCTAssertEqual(restored.name, "Distant Museum")
            XCTAssertEqual(restored.latitude, 30)
            XCTAssertEqual(restored.longitude, 40)
            XCTAssertEqual(landmarks.totalDiscovered, 1)
        }
    }

    func testMergeStillPreservesAbsentHistoryLabelsAndEarlierDates() async throws {
        try await MainActor.run {
            let (store, landmarks) = try replacementFixture()
            let summary = try BackupService.merge(samplePayload(), into: store, landmarkStore: landmarks)
            XCTAssertEqual(summary, MergeSummary(cellsAdded: 0, landmarksAdded: 0))
            XCTAssertEqual(store.totalVisitedCount, 2)
            XCTAssertEqual(landmarks.totalDiscovered, 2)
            let kept = try XCTUnwrap(store.viewContext.fetch(VisitedCell.fetchRequest()).first { $0.cellX == 1 })
            XCTAssertEqual(kept.locality, "Old Town")
            XCTAssertEqual(kept.state, "Old State")
            XCTAssertEqual(kept.country, "Old Country")
            XCTAssertEqual(kept.firstVisited, Date(timeIntervalSince1970: 10))
            XCTAssertEqual(landmarks.allLandmarks.first { $0.identifier == "Q42" }?.firstDiscovered,
                           Date(timeIntervalSince1970: 10))
        }
    }

    func testMissingDatesUseMergeDefaultsAndCanLaterMergeEarlierDates() async throws {
        try await MainActor.run {
            let (store, landmarks) = try replacementFixture()
            let now = Date(timeIntervalSince1970: 5_000)
            store.nowProvider = { now }
            let payload = BackupPayload(schemaVersion: 1, exportedAt: Date(timeIntervalSince1970: 4_000),
                                        visitedCells: [BackupVisitedCell(cellX: 1, cellY: 2, cellSizeMeters: kCellSizeMeters,
                                                                         firstVisited: nil, locality: nil)],
                                        landmarks: [BackupLandmark(identifier: "Q42", firstDiscovered: nil)])
            try BackupService.replace(payload, into: store, landmarkStore: landmarks, landmarkSource: EmptyLandmarkSource())
            let restored = try history(store, landmarks)
            XCTAssertEqual(restored.visitedCells[0].firstVisited, now)
            XCTAssertEqual(restored.landmarks[0].firstDiscovered, payload.exportedAt)
            let earlier = Date(timeIntervalSince1970: 100)
            let merge = BackupPayload(schemaVersion: 2, exportedAt: now,
                                      visitedCells: [BackupVisitedCell(cellX: 1, cellY: 2, cellSizeMeters: kCellSizeMeters,
                                                                       firstVisited: earlier, locality: nil)],
                                      landmarks: [BackupLandmark(identifier: "Q42", firstDiscovered: earlier)])
            _ = try BackupService.merge(merge, into: store, landmarkStore: landmarks)
            let merged = try history(store, landmarks)
            XCTAssertEqual(merged.visitedCells[0].firstVisited, earlier)
            XCTAssertEqual(merged.landmarks[0].firstDiscovered, earlier)
        }
    }

    func testLaunchSweepRederivesOmittedDiscoveriesOnlyNearRetainedCells() async throws {
        try await MainActor.run {
            let (store, landmarks) = try replacementFixture()
            let payload = BackupPayload(schemaVersion: 2, exportedAt: Date(),
                                        visitedCells: [BackupVisitedCell(cellX: 0, cellY: 0, cellSizeMeters: kCellSizeMeters,
                                                                         firstVisited: Date(), locality: nil)], landmarks: [])
            try BackupService.replace(payload, into: store, landmarkStore: landmarks, landmarkSource: EmptyLandmarkSource())
            XCTAssertEqual(landmarks.totalDiscovered, 0, "Replace itself restores only the file's discoveries")
            // Reconstruct the stores and invoke the same self-heal the app invokes at launch.
            let relaunchedCells = ExplorationStore(container: store.container)
            relaunchedCells.configure()
            let relaunchedLandmarks = LandmarkStore(container: store.container, defaults: nil)
            let discoveries = relaunchedLandmarks.sweepAllUndiscovered(visitedCells: relaunchedCells.visitedCellsCache)
            XCTAssertEqual(discoveries.map(\.identifier), ["Q42"])
            XCTAssertEqual(relaunchedLandmarks.totalDiscovered, 1)
            XCTAssertFalse(try XCTUnwrap(relaunchedLandmarks.allLandmarks.first { $0.identifier == "Q43" }).isDiscovered,
                           "Removing a landmark's supporting visited cells prevents launch rediscovery")
        }
    }

    func testReplaceOnlyUpdatesLandmarksWhoseTargetDiffers() async throws {
        try await MainActor.run {
            let (store, landmarks) = try replacementFixture()
            landmarks.addLandmarks((100..<200).map {
                WikidataLandmark(id: "Q\($0)", name: "Hint \($0)", description: nil,
                                 lat: 30, lon: 40, category: "museum", imageURL: nil)
            }, visitedCells: [])
            let observer = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextWillSave,
                                                                   object: store.viewContext, queue: nil) { _ in
                MainActor.assumeIsolated {
                    let updated = store.viewContext.updatedObjects.compactMap { ($0 as? Landmark)?.identifier }
                    XCTAssertEqual(Set(updated), ["Q43"], "Unchanged discoveries and hints must not be written")
                }
            }
            defer { NotificationCenter.default.removeObserver(observer) }
            let payload = BackupPayload(schemaVersion: 2, exportedAt: Date(), visitedCells: [],
                                        landmarks: [BackupLandmark(identifier: "Q42", firstDiscovered: Date(timeIntervalSince1970: 10))])
            try BackupService.replace(payload, into: store, landmarkStore: landmarks, landmarkSource: EmptyLandmarkSource())
            XCTAssertEqual(landmarks.totalDiscovered, 1)
        }
    }

    func testReplacementSummaryUsesVisibleCountsAndPluralizes() async throws {
        try await MainActor.run {
            let (store, landmarks) = try replacementFixture()
            let payload = BackupPayload(schemaVersion: 2, exportedAt: Date(), visitedCells: [
                BackupVisitedCell(cellX: 0, cellY: 0, cellSizeMeters: kCellSizeMeters, firstVisited: Date(), locality: nil),
                BackupVisitedCell(cellX: 1, cellY: 1, cellSizeMeters: 100, firstVisited: Date(), locality: nil)
            ], landmarks: [BackupLandmark(identifier: "Q42", firstDiscovered: Date())])
            try BackupService.replace(payload, into: store, landmarkStore: landmarks, landmarkSource: EmptyLandmarkSource())
            XCTAssertEqual(SettingsView.replacementSummary(cells: store.totalVisitedCount, landmarks: landmarks.totalDiscovered),
                           "Replaced history with 1 cell and 1 discovered landmark.")
            XCTAssertEqual(SettingsView.replacementSummary(cells: 0, landmarks: 2),
                           "Replaced history with 0 cells and 2 discovered landmarks.")
        }
    }

}
