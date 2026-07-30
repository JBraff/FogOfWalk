# Backup Export/Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user manually export their exploration history (visited cells + discovered-landmark state) to a JSON file, and import that file back in with merge semantics, via a new Settings screen.

**Architecture:** A new stateless `BackupService` encodes/decodes a versioned JSON payload and orchestrates merging it into `ExplorationStore` and `LandmarkStore` (each gaining a new merge-write method). A new `SettingsView` sheet, reachable from a new `ContentView` toolbar button, drives export via `ShareLink` and import via `.fileImporter`.

**Tech Stack:** Swift, SwiftUI, Core Data, `Codable`/`JSONEncoder`/`JSONDecoder`, XCTest.

## Global Constraints

- App target deploys to iOS 18.6; test target to 26.2 (per `AGENTS.md`).
- `@MainActor @Observable` — do not back-port to `ObservableObject`.
- XCTest only — no Swift Testing (`#expect`, `@Test`).
- All test methods touching a `@MainActor @Observable` store must be `async`, wrapping interactions in `await MainActor.run { }` (iOS 26 simulator dealloc-crash workaround).
- Use `container.viewContext` for all Core Data access; never a background context.
- Copy the `makeInMemoryContainer()` helper into each new test file rather than sharing one (existing repo convention — do not introduce a shared base class).
- Build: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' build`
- Full test suite: same command with `test` instead of `build` — must pass before any task is considered done, not just the new tests.
- Every task must leave the build and full test suite green.

---

### Task 1: Backup payload types and encode/decode

**Files:**
- Create: `FogOfWalk/FogOfWalk/Models/BackupService.swift`
- Test: Create `FogOfWalk/FogOfWalkTests/BackupServiceTests.swift`

**Interfaces:**
- Produces:
  - `struct BackupVisitedCell: Codable, Equatable { let cellX: Int32; let cellY: Int32; let cellSizeMeters: Double; let firstVisited: Date?; let locality: String? }`
  - `struct BackupLandmark: Codable, Equatable { let identifier: String; let firstDiscovered: Date? }`
  - `struct BackupPayload: Codable, Equatable { static let currentSchemaVersion = 1; let schemaVersion: Int; let exportedAt: Date; let visitedCells: [BackupVisitedCell]; let landmarks: [BackupLandmark] }`
  - `enum BackupError: LocalizedError, Equatable { case unsupportedSchemaVersion(Int) }`
  - `enum BackupService { static func encode(_ payload: BackupPayload) throws -> Data; static func decode(_ data: Data) throws -> BackupPayload }`

- [ ] **Step 1: Write the failing tests**

Create `FogOfWalk/FogOfWalkTests/BackupServiceTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test -only-testing:FogOfWalkTests/BackupServiceTests`
Expected: build fails — `BackupPayload`, `BackupVisitedCell`, `BackupLandmark`, `BackupError`, and `BackupService` do not exist yet.

- [ ] **Step 3: Implement**

Create `FogOfWalk/FogOfWalk/Models/BackupService.swift`:

```swift
import Foundation

// MARK: - Payload

/// One row of a user's exploration history, as stored in a backup file.
struct BackupVisitedCell: Codable, Equatable {
    let cellX: Int32
    let cellY: Int32
    let cellSizeMeters: Double
    let firstVisited: Date?
    let locality: String?
}

/// One discovered landmark, as stored in a backup file. Only the identifier and discovery
/// date travel — name/category/coordinates are re-derived from the bundled reference data
/// on the importing device, so the backup never goes stale relative to landmark metadata.
struct BackupLandmark: Codable, Equatable {
    let identifier: String
    let firstDiscovered: Date?
}

/// The full contents of a backup file. `schemaVersion` guards against importing a file
/// produced by a future, incompatible version of the app.
struct BackupPayload: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let exportedAt: Date
    let visitedCells: [BackupVisitedCell]
    let landmarks: [BackupLandmark]
}

// MARK: - Errors

enum BackupError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "This backup file uses a newer format (version \(version)) that this version of the app doesn't support."
        }
    }
}

// MARK: - Encode / decode

enum BackupService {
    static func encode(_ payload: BackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    /// Decodes and validates a backup file. Throws `BackupError.unsupportedSchemaVersion`
    /// if the file was produced by a schema version this app doesn't understand, or a
    /// `DecodingError` if the file isn't a valid backup at all.
    static func decode(_ data: Data) throws -> BackupPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)
        guard payload.schemaVersion == BackupPayload.currentSchemaVersion else {
            throw BackupError.unsupportedSchemaVersion(payload.schemaVersion)
        }
        return payload
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test -only-testing:FogOfWalkTests/BackupServiceTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add FogOfWalk/FogOfWalk/Models/BackupService.swift FogOfWalk/FogOfWalkTests/BackupServiceTests.swift
git commit -m "feat: add versioned backup payload encode/decode"
```

---

### Task 2: ExplorationStore merge-import of visited cells

**Files:**
- Modify: `FogOfWalk/FogOfWalk/Models/ExplorationStore.swift`
- Test: Modify `FogOfWalk/FogOfWalkTests/ExplorationStoreTests.swift`

**Interfaces:**
- Consumes: `BackupVisitedCell` (Task 1), `CellID`/`kCellSizeMeters` (`GridCell.swift`).
- Produces: `@discardableResult func addCells(_ records: [BackupVisitedCell]) -> Int` on `ExplorationStore` — inserts cells absent locally (matched on `cellX`/`cellY` with `cellSizeMeters == kCellSizeMeters`), and for cells that already exist keeps the earlier of the two `firstVisited` dates without touching `locality`. Returns the count of newly inserted cells. Refreshes all in-memory caches afterward.

- [ ] **Step 1: Write the failing tests**

Add to `FogOfWalk/FogOfWalkTests/ExplorationStoreTests.swift` (inside `final class ExplorationStoreTests`, after the existing tests):

```swift
    func testAddCellsInsertsNewCellsAndReturnsCount() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()

            let records = [
                BackupVisitedCell(cellX: 1, cellY: 1, cellSizeMeters: kCellSizeMeters,
                                   firstVisited: Date(timeIntervalSince1970: 1_000), locality: "Town A"),
                BackupVisitedCell(cellX: 2, cellY: 2, cellSizeMeters: kCellSizeMeters,
                                   firstVisited: Date(timeIntervalSince1970: 2_000), locality: nil)
            ]

            let added = store.addCells(records)

            XCTAssertEqual(added, 2)
            XCTAssertEqual(store.totalVisitedCount, 2)
            XCTAssertTrue(store.visitedCellsCache.contains(CellID(x: 1, y: 1)))
            XCTAssertTrue(store.visitedCellsCache.contains(CellID(x: 2, y: 2)))
        }
    }

    func testAddCellsSkipsExistingCellButKeepsEarlierDate() async {
        await MainActor.run {
            let store = ExplorationStore(container: makeInMemoryContainer())
            store.configure()
            store.nowProvider = { Date(timeIntervalSince1970: 5_000) }
            store.addCell(CellID(x: 3, y: 3))

            let request = NSFetchRequest<VisitedCell>(entityName: "VisitedCell")
            let before = try? store.viewContext.fetch(request)
            XCTAssertEqual(before?.first?.firstVisited, Date(timeIntervalSince1970: 5_000))

            let earlierRecord = BackupVisitedCell(cellX: 3, cellY: 3, cellSizeMeters: kCellSizeMeters,
                                                   firstVisited: Date(timeIntervalSince1970: 1_000),
                                                   locality: nil)
            let added = store.addCells([earlierRecord])

            XCTAssertEqual(added, 0, "Existing cell should not count as newly added")
            XCTAssertEqual(store.totalVisitedCount, 1, "No duplicate row should be created")

            let after = try? store.viewContext.fetch(request)
            XCTAssertEqual(after?.first?.firstVisited, Date(timeIntervalSince1970: 1_000),
                            "Merge should keep the earlier firstVisited date")
        }
    }
```

`ExplorationStoreTests.swift` already imports `CoreData`, so `NSFetchRequest<VisitedCell>` is available.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test -only-testing:FogOfWalkTests/ExplorationStoreTests`
Expected: build fails — `addCells` does not exist yet.

- [ ] **Step 3: Implement**

In `FogOfWalk/FogOfWalk/Models/ExplorationStore.swift`, add a new method after `addCell(_:)` (after line 192, before `isVisited`):

```swift
    /// Merge-imports backup cell records. Inserts cells absent locally (matched by grid
    /// coordinate at the current cell size); for cells that already exist, keeps the earlier
    /// of the two `firstVisited` dates without touching `locality`. Returns the number of
    /// newly inserted cells.
    @discardableResult
    func addCells(_ records: [BackupVisitedCell]) -> Int {
        guard !records.isEmpty else { return 0 }

        let ctx = container.viewContext
        let request = NSFetchRequest<VisitedCell>(entityName: "VisitedCell")
        request.predicate = NSPredicate(format: "cellSizeMeters == %f", kCellSizeMeters)
        let existing: [VisitedCell]
        do {
            existing = try ctx.fetch(request)
        } catch {
            print("ExplorationStore: addCells fetch failed: \(error)")
            return 0
        }

        var byID: [CellID: VisitedCell] = [:]
        for cell in existing {
            byID[CellID(x: cell.cellX, y: cell.cellY)] = cell
        }

        var addedCount = 0
        for record in records {
            let id = CellID(x: record.cellX, y: record.cellY)
            if let existingCell = byID[id] {
                if let imported = record.firstVisited,
                   let current = existingCell.firstVisited,
                   imported < current {
                    existingCell.firstVisited = imported
                }
                continue
            }

            let entity = VisitedCell(context: ctx)
            entity.cellX          = record.cellX
            entity.cellY          = record.cellY
            entity.cellSizeMeters = kCellSizeMeters
            entity.firstVisited   = record.firstVisited ?? nowProvider()
            entity.locality       = record.locality
            byID[id] = entity
            addedCount += 1
        }

        guard ctx.hasChanges else { return 0 }

        do {
            try ctx.save()
        } catch {
            print("ExplorationStore: addCells save failed: \(error)")
            ctx.rollback()
            return 0
        }

        reloadCache()
        return addedCount
    }

```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test -only-testing:FogOfWalkTests/ExplorationStoreTests`
Expected: PASS (all tests in the class, including the two new ones).

- [ ] **Step 5: Commit**

```bash
git add FogOfWalk/FogOfWalk/Models/ExplorationStore.swift FogOfWalk/FogOfWalkTests/ExplorationStoreTests.swift
git commit -m "feat: add merge-import of visited cells to ExplorationStore"
```

---

### Task 3: LandmarkStore merge-import of discovered landmarks

**Files:**
- Modify: `FogOfWalk/FogOfWalk/Models/LandmarkStore.swift`
- Test: Modify `FogOfWalk/FogOfWalkTests/LandmarkStoreTests.swift`

**Interfaces:**
- Consumes: `BackupLandmark` (Task 1).
- Produces: `@discardableResult func restoreDiscovered(_ records: [(identifier: String, firstDiscovered: Date)]) -> Int` on `LandmarkStore` — for each record whose `identifier` matches a locally known landmark, marks it discovered (if not already) and keeps the earlier of the existing/imported `firstDiscovered` date; records with no local match are skipped without error. Returns the count of landmarks newly marked discovered (not already discovered before the call).

- [ ] **Step 1: Write the failing tests**

Add to `FogOfWalk/FogOfWalkTests/LandmarkStoreTests.swift` (inside `final class LandmarkStoreTests`, after the existing `addLandmarks` tests, before or after the `// MARK: - addLandmarks` section — place under a new `// MARK: - restoreDiscovered` section):

```swift
    // MARK: - restoreDiscovered

    func testRestoreDiscoveredMarksKnownLandmarkDiscovered() async {
        await MainActor.run {
            let store = makeStore()
            seed(store, [makeWikidataLandmark(id: "Q10", name: "Old Fort")])
            XCTAssertFalse(store.allLandmarks.first?.isDiscovered ?? true)

            let date = Date(timeIntervalSince1970: 1_000)
            let added = store.restoreDiscovered([(identifier: "Q10", firstDiscovered: date)])

            XCTAssertEqual(added, 1)
            XCTAssertEqual(store.totalDiscovered, 1)
            XCTAssertTrue(store.allLandmarks.first?.isDiscovered ?? false)
            XCTAssertEqual(store.allLandmarks.first?.firstDiscovered, date)
        }
    }

    func testRestoreDiscoveredSkipsUnknownIdentifierWithoutError() async {
        await MainActor.run {
            let store = makeStore()
            seed(store, [makeWikidataLandmark(id: "Q10", name: "Old Fort")])

            let added = store.restoreDiscovered([(identifier: "Q999-not-local", firstDiscovered: Date())])

            XCTAssertEqual(added, 0)
            XCTAssertEqual(store.totalDiscovered, 0)
        }
    }

    func testRestoreDiscoveredKeepsEarlierDateForAlreadyDiscoveredLandmark() async {
        await MainActor.run {
            let store = makeStore()
            seed(store, [makeWikidataLandmark(id: "Q10", name: "Old Fort")])
            _ = store.restoreDiscovered([(identifier: "Q10", firstDiscovered: Date(timeIntervalSince1970: 5_000))])

            let added = store.restoreDiscovered([(identifier: "Q10", firstDiscovered: Date(timeIntervalSince1970: 1_000))])

            XCTAssertEqual(added, 0, "Landmark was already discovered, so this is not a new discovery")
            XCTAssertEqual(store.allLandmarks.first?.firstDiscovered, Date(timeIntervalSince1970: 1_000),
                            "Merge should keep the earlier firstDiscovered date")
        }
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test -only-testing:FogOfWalkTests/LandmarkStoreTests`
Expected: build fails — `restoreDiscovered` does not exist yet.

- [ ] **Step 3: Implement**

In `FogOfWalk/FogOfWalk/Models/LandmarkStore.swift`, add a new method after `addLandmarks(_:visitedCells:)` (after line 174, before `// MARK: - Discovery`):

```swift

    /// Merge-imports discovered-landmark state from a backup. For each record whose
    /// `identifier` matches a landmark known locally, marks it discovered and keeps the
    /// earlier of the existing/imported `firstDiscovered` date. Records whose identifier has
    /// no local match (e.g. bundled reference data differs between devices) are skipped
    /// without error. Returns the number of landmarks newly marked discovered.
    @discardableResult
    func restoreDiscovered(_ records: [(identifier: String, firstDiscovered: Date)]) -> Int {
        guard !records.isEmpty else { return 0 }

        var byIdentifier: [String: Landmark] = [:]
        for landmark in allLandmarks {
            byIdentifier[landmark.identifier] = landmark
        }

        let ctx = container.viewContext
        var newlyDiscoveredCount = 0
        var touched: [Landmark] = []

        for record in records {
            guard let landmark = byIdentifier[record.identifier] else { continue }

            if landmark.isDiscovered {
                if let current = landmark.firstDiscovered, record.firstDiscovered < current {
                    landmark.firstDiscovered = record.firstDiscovered
                    touched.append(landmark)
                }
            } else {
                landmark.isDiscovered = true
                landmark.firstDiscovered = record.firstDiscovered
                touched.append(landmark)
                newlyDiscoveredCount += 1
            }
        }

        guard !touched.isEmpty else { return 0 }

        do {
            try ctx.save()
        } catch {
            print("LandmarkStore: restoreDiscovered save failed: \(error)")
            ctx.rollback()
            loadFromStore()
            return 0
        }

        loadFromStore()
        return newlyDiscoveredCount
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test -only-testing:FogOfWalkTests/LandmarkStoreTests`
Expected: PASS (all tests in the class, including the three new ones).

- [ ] **Step 5: Commit**

```bash
git add FogOfWalk/FogOfWalk/Models/LandmarkStore.swift FogOfWalk/FogOfWalkTests/LandmarkStoreTests.swift
git commit -m "feat: add merge-import of discovered landmarks to LandmarkStore"
```

---

### Task 4: BackupService export and merge orchestration

**Files:**
- Modify: `FogOfWalk/FogOfWalk/Models/BackupService.swift`
- Test: Modify `FogOfWalk/FogOfWalkTests/BackupServiceTests.swift`

**Interfaces:**
- Consumes: `ExplorationStore.viewContext`/`addCells(_:)` (Task 2), `LandmarkStore.allLandmarks`/`restoreDiscovered(_:)` (Task 3).
- Produces:
  - `struct MergeSummary: Equatable { let cellsAdded: Int; let landmarksAdded: Int }`
  - `@MainActor static func exportData(explorationStore: ExplorationStore, landmarkStore: LandmarkStore) throws -> Data` on `BackupService`.
  - `@MainActor static func merge(_ payload: BackupPayload, into explorationStore: ExplorationStore, landmarkStore: LandmarkStore) -> MergeSummary` on `BackupService`.

- [ ] **Step 1: Write the failing tests**

Add to `FogOfWalk/FogOfWalkTests/BackupServiceTests.swift` (inside `final class BackupServiceTests`, after the existing tests). This needs Core Data test containers, so add the import and helpers used by the other store test files:

```swift
import CoreData

// (add this import alongside the existing `import XCTest` / `@testable import FogOfWalk`)
```

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test -only-testing:FogOfWalkTests/BackupServiceTests`
Expected: build fails — `MergeSummary`, `exportData`, and `merge` do not exist yet.

- [ ] **Step 3: Implement**

In `FogOfWalk/FogOfWalk/Models/BackupService.swift`, add `import CoreData` at the top, and add the following after the `BackupError` enum, before `// MARK: - Encode / decode`:

```swift
// MARK: - Merge summary

/// Counts surfaced to the user after an import: how many rows were actually new, as opposed
/// to already present on the device (and therefore silently merged/skipped).
struct MergeSummary: Equatable {
    let cellsAdded: Int
    let landmarksAdded: Int
}
```

Then extend the `BackupService` enum with two more static functions (add after `decode(_:)`):

```swift
    // MARK: - Export

    /// Builds a backup payload from the current state of both stores and encodes it.
    /// Only discovered landmarks are included — undiscovered ones carry no user data worth
    /// backing up, and their metadata is re-derived from bundled reference data on import.
    @MainActor
    static func exportData(explorationStore: ExplorationStore, landmarkStore: LandmarkStore) throws -> Data {
        let request = NSFetchRequest<VisitedCell>(entityName: "VisitedCell")
        let cells = try explorationStore.viewContext.fetch(request)
        let cellRecords = cells.map {
            BackupVisitedCell(cellX: $0.cellX, cellY: $0.cellY, cellSizeMeters: $0.cellSizeMeters,
                               firstVisited: $0.firstVisited, locality: $0.locality)
        }

        let landmarkRecords = landmarkStore.allLandmarks
            .filter { $0.isDiscovered }
            .map { BackupLandmark(identifier: $0.identifier, firstDiscovered: $0.firstDiscovered) }

        let payload = BackupPayload(schemaVersion: BackupPayload.currentSchemaVersion,
                                     exportedAt: Date(),
                                     visitedCells: cellRecords,
                                     landmarks: landmarkRecords)
        return try encode(payload)
    }

    // MARK: - Import

    /// Merges a decoded backup payload into both stores. Never partially applies: both
    /// underlying merge calls are all-or-nothing at the Core Data save level (see
    /// `ExplorationStore.addCells(_:)` and `LandmarkStore.restoreDiscovered(_:)`).
    @MainActor
    static func merge(_ payload: BackupPayload,
                       into explorationStore: ExplorationStore,
                       landmarkStore: LandmarkStore) -> MergeSummary {
        let cellsAdded = explorationStore.addCells(payload.visitedCells)
        let landmarksAdded = landmarkStore.restoreDiscovered(
            payload.landmarks.map { ($0.identifier, $0.firstDiscovered ?? Date()) }
        )
        return MergeSummary(cellsAdded: cellsAdded, landmarksAdded: landmarksAdded)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test -only-testing:FogOfWalkTests/BackupServiceTests`
Expected: PASS (all tests in the class).

- [ ] **Step 5: Commit**

```bash
git add FogOfWalk/FogOfWalk/Models/BackupService.swift FogOfWalk/FogOfWalkTests/BackupServiceTests.swift
git commit -m "feat: add BackupService export and merge orchestration"
```

---

### Task 5: Settings screen with export/import UI

**Files:**
- Create: `FogOfWalk/FogOfWalk/Views/SettingsView.swift`
- Modify: `FogOfWalk/FogOfWalk/ContentView.swift`

**Interfaces:**
- Consumes: `BackupService.exportData(explorationStore:landmarkStore:)`, `BackupService.decode(_:)`, `BackupService.merge(_:into:landmarkStore:)`, `MergeSummary` (Task 4); `ExplorationStore`/`LandmarkStore` via `@Environment`.
- Produces: `struct SettingsView: View` (no external API — a self-contained sheet).

This task is UI wiring on top of already-tested logic, so it has no new automated tests — consistent with the existing convention that view files (`StatsView`, `DiscoveryStatsView`, `ContentView`) have no dedicated unit test files (SwiftUI rendering isn't unit-testable in this project; see `AGENTS.md` testing conventions). Verify manually per Step 3 below.

- [ ] **Step 1: Create the Settings view**

Create `FogOfWalk/FogOfWalk/Views/SettingsView.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(ExplorationStore.self) private var store
    @Environment(LandmarkStore.self)    private var landmarkStore
    @Environment(\.dismiss)             private var dismiss

    @State private var exportURL: URL?
    @State private var showExportError = false
    @State private var exportErrorMessage = ""

    @State private var showImporter = false
    @State private var showImportError = false
    @State private var importErrorMessage = ""
    @State private var importSummaryMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Export Backup…") { exportBackup() }

                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share Backup File", systemImage: "square.and.arrow.up")
                        }
                    }

                    Button("Import Backup…") { showImporter = true }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Export your exploration history and discovered landmarks to a file you control. Import merges a backup into what's already on this device — nothing is ever overwritten.")
                }

                if let importSummaryMessage {
                    Section {
                        Text(importSummaryMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImportResult(result)
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
        .alert("Import Failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage)
        }
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func exportBackup() {
        do {
            let data = try BackupService.exportData(explorationStore: store, landmarkStore: landmarkStore)
            let filename = "FogOfWalk-Backup-\(Self.exportDateFormatter.string(from: Date())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            exportErrorMessage = error.localizedDescription
            showExportError = true
        }
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importErrorMessage = error.localizedDescription
            showImportError = true
        case .success(let url):
            do {
                let data = try Data(contentsOf: url)
                let payload = try BackupService.decode(data)
                let summary = BackupService.merge(payload, into: store, landmarkStore: landmarkStore)
                importSummaryMessage = "Imported \(summary.cellsAdded) new cell\(summary.cellsAdded == 1 ? "" : "s"), "
                    + "\(summary.landmarksAdded) new landmark\(summary.landmarksAdded == 1 ? "" : "s")."
            } catch {
                importErrorMessage = error.localizedDescription
                showImportError = true
            }
        }
    }
}
```

- [ ] **Step 2: Wire the Settings sheet into ContentView**

In `FogOfWalk/FogOfWalk/ContentView.swift`, add a new `@State` alongside the existing ones (after line 19, `upgradeBannerDismissed`):

```swift
    @State private var showSettings = false
```

Add a `.sheet(isPresented:)` for it after the existing `.sheet(item: $selectedLandmark)` block (after line 57, before `.onAppear`):

```swift
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
```

Add a way to open it: change the `StatsView` call site (line 44-45) to pass a `showSettings` binding, then add a gear button to `StatsView`. In `ContentView.swift`, replace:

```swift
                StatsView(showStats: $showStats)
                    .padding(.bottom, 8)
```

with:

```swift
                StatsView(showStats: $showStats, showSettings: $showSettings)
                    .padding(.bottom, 8)
```

In `FogOfWalk/FogOfWalk/Views/StatsView.swift`, add a binding parameter (after line 8, `@Binding var showStats: Bool`):

```swift
    @Binding var showSettings: Bool
```

Add a gear button after the existing stats button (after line 51, `.accessibilityLabel("Discovery statistics")`, still inside the `HStack`):

```swift

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.title2)
            }
            .accessibilityLabel("Settings")
```

- [ ] **Step 3: Build and manually verify**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' build`
Expected: build succeeds.

Then run the app in the simulator (Xcode ▶, or `xcrun simctl launch` after installing), walk some cells via **Features → Location → City Bicycle Ride**, and manually verify:
1. Tapping the new gear icon opens Settings.
2. "Export Backup…" then "Share Backup File" opens the system share sheet; save the file to Files.
3. Delete the app (or use a second simulator) to get a clean state, reinstall, walk a few different cells, open Settings, "Import Backup…", pick the saved file — a summary like "Imported N new cells, M new landmarks." appears, and the fog map reflects the merged cells.

- [ ] **Step 4: Run the full test suite**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test`
Expected: PASS (entire suite, not just new tests).

- [ ] **Step 5: Commit**

```bash
git add FogOfWalk/FogOfWalk/Views/SettingsView.swift FogOfWalk/FogOfWalk/ContentView.swift FogOfWalk/FogOfWalk/Views/StatsView.swift
git commit -m "feat: add Settings screen with backup export/import"
```

---

### Task 6: Update project documentation

**Files:**
- Modify: `AGENTS.md`

**Interfaces:**
- None — documentation only.

- [ ] **Step 1: Update the project layout listing**

In `AGENTS.md`, under the `Views/` section of the project layout (around line 32-39), add a line for the new file, keeping the existing alignment style:

```
      SettingsView.swift               # Sheet: export/import backup (BackupService)
```

Insert it after the `StatsView.swift` line and before `DiscoveryStatsView.swift` (matching where it's opened from), or adjust alignment to match neighboring lines.

Also add `BackupService.swift` to the `Models/` section (around line 19-27), after `LandmarkStore.swift`:

```
      BackupService.swift             # Versioned JSON export/import + merge-import into both stores
```

- [ ] **Step 2: Remove the stale "no SettingsView" note and the stale known-gap note**

Line 56 currently reads:

```
There is no `SettingsView.swift` and no `FogView.swift` — both were removed; see below.
```

Change it to:

```
There is no `FogView.swift` — it was removed; see below. `SettingsView.swift` exists again as of the backup export/import feature (below), reintroducing a settings screen after its earlier removal.
```

Line 136 currently reads:

```
- **No known way to delete location history in the running app.** `ExplorationStore.deleteAllCells`, `visitedCellCount`, `totalCellCount`, and `Coordinator.replaceFogOverlay` exist but have no production caller — this is a known gap, not a feature to build around.
```

Change it to:

```
- **No known way to delete location history in the running app.** `ExplorationStore.deleteAllCells`, `visitedCellCount`, `totalCellCount`, and `Coordinator.replaceFogOverlay` exist but have no production caller — this is a known gap, not a feature to build around. (The Settings screen added for backup export/import does *not* address this — it only exports/imports/merges, it never deletes.)
```

- [ ] **Step 3: Document the new backup architecture**

Add a new subsection under `## Architecture`, after the `### Fog rendering` section and before `## Key constraints and gotchas` (i.e. right before line 119's `---`):

```markdown
### Backup export/import

`BackupService` (`Models/BackupService.swift`) is a stateless `enum` — plain namespaced static
functions, not a store. It encodes/decodes a versioned JSON `BackupPayload`
(`visitedCells` + discovered `landmarks` only — undiscovered landmarks and all landmark
metadata besides `identifier`/`firstDiscovered` are intentionally excluded, since metadata is
re-derived from bundled reference data on the importing device) and orchestrates merging it
into both stores:

- `ExplorationStore.addCells(_:)` inserts cells absent locally and keeps the earlier
  `firstVisited` date for cells that already exist.
- `LandmarkStore.restoreDiscovered(_:)` marks known-by-`identifier` landmarks discovered and
  keeps the earlier `firstDiscovered` date; unknown identifiers are skipped without error.

`SettingsView` (`Views/SettingsView.swift`), reachable via a gear button in `StatsView`, drives
export through `ShareLink` and import through `.fileImporter`. This is manual/on-demand only —
there is no automatic or continuous sync (no CloudKit).
```

- [ ] **Step 4: Verify the doc changes render sensibly**

Run: `git diff AGENTS.md` and read it through once — confirm no other line still says "no SettingsView" or contradicts the new architecture section.

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md
git commit -m "docs: describe the backup export/import feature in AGENTS.md"
```
