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
                                   locality: "Springfield")
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
            _ = landmarkStore.restoreDiscovered([(identifier: "Q1", firstDiscovered: Date(timeIntervalSince1970: 42))])

            let data = try BackupService.exportData(explorationStore: explorationStore, landmarkStore: landmarkStore)
            let payload = try BackupService.decode(data)

            XCTAssertEqual(payload.visitedCells.count, 1)
            XCTAssertEqual(payload.visitedCells.first?.cellX, 4)
            XCTAssertEqual(payload.landmarks, [BackupLandmark(identifier: "Q1", firstDiscovered: Date(timeIntervalSince1970: 42))])
        }
    }

    func testMergeAppliesCellsAndLandmarksAndReturnsSummary() async {
        await MainActor.run {
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

            let summary = BackupService.merge(payload, into: explorationStore, landmarkStore: landmarkStore)

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
            _ = sourceLandmarks.restoreDiscovered([(identifier: "Q7", firstDiscovered: Date(timeIntervalSince1970: 300))])

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

            _ = BackupService.merge(payload, into: destExploration, landmarkStore: destLandmarks)

            XCTAssertTrue(destExploration.visitedCellsCache.contains(CellID(x: 7, y: 7)))
            XCTAssertTrue(destLandmarks.allLandmarks.first?.isDiscovered ?? false)
            XCTAssertEqual(destLandmarks.allLandmarks.first?.firstDiscovered, Date(timeIntervalSince1970: 300))
        }
    }
}
