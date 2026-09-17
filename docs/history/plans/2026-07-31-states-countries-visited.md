# States & Countries Visited Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show all-time lists of states/provinces and countries visited in the Discovery Stats sheet, by capturing `administrativeArea`/`country` from the reverse-geocoding already run per visited cell.

**Architecture:** Two new optional `VisitedCell` Core Data attributes (`state`, `country`) are populated by `LocalityGeocoder` alongside the existing `locality` field, backfilled for cells geocoded before this change, aggregated by `DiscoveryStatsModel.refresh(context:)` into two new all-time-only `[LocalityStats]` arrays, and rendered as two new list sections in `DiscoveryStatsView`. The backup export/import payload carries the new fields through a schema version bump.

**Tech Stack:** Swift, SwiftUI, Core Data, CoreLocation (`CLGeocoder`/`CLPlacemark`), XCTest.

## Global Constraints

- App target deploys to iOS 18.6; test targets to iOS 26.2.
- Do not use `fatalError` for recoverable errors.
- Do not back-port away from `@Observable` / iOS 17 APIs.
- XCTest only — do not use Swift Testing (`#expect`, `@Test`, etc.). No SwiftUI previews exist in this repo.
- `@MainActor @Observable` store tests must be `async`, wrapping interactions in `await MainActor.run { }` (works around an iOS 26 simulator `@Observable` dealloc crash).
- Every feature or bug fix must include tests; a change without corresponding tests is not complete.
- After every task: build **and** run tests (`xcodebuild ... test`, or `-only-testing:FogOfWalkTests` for faster unit-only runs) before moving on. The final task must run the full suite (no `-only-testing` filter).
- Build command: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' build` (swap `build` for `test`).
- This is a synchronized-file-group Xcode project (`PBXFileSystemSynchronizedRootGroup`) — new files placed on disk under `FogOfWalk/FogOfWalk/` are picked up automatically; no `project.pbxproj` edits are needed.

---

### Task 1: Core Data schema — add `state`/`country` to `VisitedCell`

**Files:**
- Create: `FogOfWalk/FogOfWalk/FogOfWalk.xcdatamodeld/FogOfWalk 3.xcdatamodel/contents`
- Modify: `FogOfWalk/FogOfWalk/FogOfWalk.xcdatamodeld/.xccurrentversion`
- Modify: `FogOfWalk/FogOfWalk/Models/VisitedCell+CoreData.swift`
- Test: `FogOfWalk/FogOfWalkTests/ExplorationStoreTests.swift`

**Interfaces:**
- Produces: `VisitedCell.state: String?` and `VisitedCell.country: String?` (`@NSManaged` properties), used by every later task.

- [ ] **Step 1: Create the new model version**

Create `FogOfWalk/FogOfWalk/FogOfWalk.xcdatamodeld/FogOfWalk 3.xcdatamodel/contents` (a new directory + file) with this content — identical to `FogOfWalk 2.xcdatamodel/contents` with `country` and `state` attributes added to `VisitedCell` (alphabetically, matching the existing attribute ordering convention):

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="22222" systemVersion="23G93" minimumToolsVersion="Automatic" sourceLanguage="Swift" usedWithSwiftData="NO" userDefinedModelVersionIdentifier="">
    <entity name="Landmark" representedClassName="Landmark" syncable="YES" codeGenerationType="none">
        <attribute name="category" optional="NO" attributeType="String"/>
        <attribute name="discoveryRadiusMeters" optional="NO" attributeType="Double" defaultValueString="100" usesScalarValueType="YES"/>
        <attribute name="firstDiscovered" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="firstSeen" optional="NO" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="identifier" optional="NO" attributeType="String"/>
        <attribute name="isDiscovered" optional="NO" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
        <attribute name="latitude" optional="NO" attributeType="Double" defaultValueString="0.0" usesScalarValueType="YES"/>
        <attribute name="longitude" optional="NO" attributeType="Double" defaultValueString="0.0" usesScalarValueType="YES"/>
        <attribute name="name" optional="NO" attributeType="String"/>
        <uniquenessConstraints>
            <uniquenessConstraint>
                <constraint value="identifier"/>
            </uniquenessConstraint>
        </uniquenessConstraints>
    </entity>
    <entity name="VisitedCell" representedClassName="VisitedCell" syncable="YES" codeGenerationType="none">
        <attribute name="cellSizeMeters" optional="NO" attributeType="Double" defaultValueString="0.0" usesScalarValueType="YES"/>
        <attribute name="cellX" optional="NO" attributeType="Integer 32" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="cellY" optional="NO" attributeType="Integer 32" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="country" optional="YES" attributeType="String"/>
        <attribute name="firstVisited" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="locality" optional="YES" attributeType="String"/>
        <attribute name="state" optional="YES" attributeType="String"/>
        <fetchIndex name="byCellSizeAndCoords">
            <fetchIndexElement property="cellSizeMeters" type="Binary" order="ascending"/>
            <fetchIndexElement property="cellX" type="Binary" order="ascending"/>
            <fetchIndexElement property="cellY" type="Binary" order="ascending"/>
        </fetchIndex>
    </entity>
</model>
```

- [ ] **Step 2: Point the model at the new version**

Overwrite `FogOfWalk/FogOfWalk/FogOfWalk.xcdatamodeld/.xccurrentversion`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>_XCCurrentVersionName</key>
	<string>FogOfWalk 3.xcdatamodel</string>
</dict>
</plist>
```

- [ ] **Step 3: Add the managed properties**

In `FogOfWalk/FogOfWalk/Models/VisitedCell+CoreData.swift`, add two `@NSManaged` properties after `locality`:

```swift
@objc(VisitedCell)
public class VisitedCell: NSManagedObject {
    @NSManaged public var cellX:          Int32
    @NSManaged public var cellY:          Int32
    @NSManaged public var cellSizeMeters: Double
    @NSManaged public var firstVisited:   Date?
    @NSManaged public var locality:       String?
    @NSManaged public var state:          String?
    @NSManaged public var country:        String?

    @nonobjc public class func fetchRequest() -> NSFetchRequest<VisitedCell> {
        NSFetchRequest<VisitedCell>(entityName: "VisitedCell")
    }
}
```

- [ ] **Step 4: Write a failing test for persistence**

In `FogOfWalk/FogOfWalkTests/ExplorationStoreTests.swift`, add (near the other `addCells`/Core Data tests):

```swift
func testVisitedCellPersistsStateAndCountry() async {
    await MainActor.run {
        let store = ExplorationStore(container: makeInMemoryContainer())
        store.configure()
        let ctx = store.viewContext

        let cell = VisitedCell(context: ctx)
        cell.cellX          = 5
        cell.cellY          = 5
        cell.cellSizeMeters = kCellSizeMeters
        cell.firstVisited   = Date()
        cell.state          = "California"
        cell.country        = "United States"
        try? ctx.save()

        let request = NSFetchRequest<VisitedCell>(entityName: "VisitedCell")
        let fetched = try? ctx.fetch(request)
        XCTAssertEqual(fetched?.first?.state, "California")
        XCTAssertEqual(fetched?.first?.country, "United States")
    }
}
```

- [ ] **Step 5: Run it to verify it fails to compile/run before the schema exists**

If steps 1–3 haven't been done yet, this fails with "value of type 'VisitedCell' has no member 'state'". Since steps 1–3 precede this in the task, instead just run it now to confirm it **passes** (this task's schema change already landed):

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test -only-testing:FogOfWalkTests/ExplorationStoreTests/testVisitedCellPersistsStateAndCountry`
Expected: PASS

- [ ] **Step 6: Build and run the full unit test suite**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test -only-testing:FogOfWalkTests`
Expected: PASS (no regressions — this is a purely additive schema change, existing rows get `nil` for both new attributes via automatic lightweight migration)

- [ ] **Step 7: Commit**

```bash
git add FogOfWalk/FogOfWalk/FogOfWalk.xcdatamodeld FogOfWalk/FogOfWalk/Models/VisitedCell+CoreData.swift FogOfWalk/FogOfWalkTests/ExplorationStoreTests.swift
git commit -m "feat: add state/country attributes to VisitedCell"
```

---

### Task 2: Capture state/country during geocoding, backfill existing cells

**Files:**
- Modify: `FogOfWalk/FogOfWalk/Models/LocalityGeocoder.swift`
- Test: `FogOfWalk/FogOfWalkTests/LocalityGeocoderTests.swift`

**Interfaces:**
- Consumes: `VisitedCell.state`/`.country` (Task 1).
- Produces: `LocalityGeocoder.geocodeCluster(_:)` now also sets `cell.state`/`cell.country`; `geocodeUntaggedCells(context:)`'s backfill predicate now also catches cells with `locality` set but `state`/`country` still nil.

- [ ] **Step 1: Update the mock geocoder/placemark to support state/country**

In `FogOfWalk/FogOfWalkTests/LocalityGeocoderTests.swift`, replace the `MockGeocoder` and `MockPlacemark` definitions:

```swift
final class MockGeocoder: GeocoderProtocol, @unchecked Sendable {
    let localityToReturn: String
    let stateToReturn: String?
    let countryToReturn: String?
    private(set) var callCount = 0
    var onCall: (() -> Void)?

    init(locality: String = "MockCity", state: String? = nil, country: String? = nil,
         onCall: (() -> Void)? = nil) {
        self.localityToReturn = locality
        self.stateToReturn    = state
        self.countryToReturn  = country
        self.onCall           = onCall
    }

    func reverseGeocodeLocation(_ location: CLLocation) async throws -> [CLPlacemark] {
        callCount += 1
        onCall?()
        let placemark = MockPlacemark(locality: localityToReturn,
                                       administrativeArea: stateToReturn,
                                       country: countryToReturn)
        return [placemark]
    }
}

/// Minimal CLPlacemark subclass that overrides locality/administrativeArea/country.
private final class MockPlacemark: CLPlacemark, @unchecked Sendable {
    private let localityValue: String?
    private let administrativeAreaValue: String?
    private let countryValue: String?

    init(locality: String?, administrativeArea: String? = nil, country: String? = nil) {
        self.localityValue = locality
        self.administrativeAreaValue = administrativeArea
        self.countryValue = country
        // init(placemark:) is the designated iOS initializer for CLPlacemark.
        super.init(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D()))
    }

    required init?(coder: NSCoder) { nil }

    override var locality: String? { localityValue }
    override var administrativeArea: String? { administrativeAreaValue }
    override var country: String? { countryValue }
}
```

This is additive (new parameters default to `nil`) — every existing `MockGeocoder(...)` call site in this file keeps compiling unchanged.

- [ ] **Step 2: Update `insertCell` to accept state/country**

In the same file, replace the `insertCell` helper:

```swift
@discardableResult
func insertCell(
    in ctx: NSManagedObjectContext,
    x: Int32 = 0, y: Int32 = 0,
    cellSizeMeters: Double = 50,
    locality: String? = nil,
    state: String? = nil,
    country: String? = nil
) -> VisitedCell {
    let cell = VisitedCell(context: ctx)
    cell.cellX          = x
    cell.cellY          = y
    cell.cellSizeMeters = cellSizeMeters
    cell.firstVisited   = Date()
    cell.locality       = locality
    cell.state          = state
    cell.country        = country
    try! ctx.save()
    return cell
}
```

- [ ] **Step 3: Fix the now-stale "already tagged" backfill test**

`testSkipsAlreadyTaggedCellsDuringBackfill` currently inserts a cell with only `locality` set and expects the backfill to skip it. After this task's predicate change (Step 5 below), a cell with `locality` set but `state`/`country` nil will legitimately get re-geocoded — so this test must set all three fields to stay a valid "fully tagged, skip me" case. Update it:

```swift
func testSkipsAlreadyTaggedCellsDuringBackfill() async {
    let mock = MockGeocoder(locality: "ShouldNotOverwrite")

    await MainActor.run {
        let container = makeInMemoryContainer()
        let ctx       = container.viewContext
        insertCell(in: ctx, x: 0, locality: "ExistingLocality",
                   state: "ExistingState", country: "ExistingCountry")
        let geocoder = LocalityGeocoder(geocoder: mock, requestDelay: .zero)
        geocoder.geocodeUntaggedCells(context: ctx)
    }

    // Give tasks time to run
    try? await Task.sleep(for: .milliseconds(200))

    await MainActor.run {
        XCTAssertEqual(mock.callCount, 0, "No geocode call should be made for fully-tagged cells")
    }
}
```

- [ ] **Step 4: Write the new failing tests**

Add to `FogOfWalk/FogOfWalkTests/LocalityGeocoderTests.swift`:

```swift
func testEnqueueSetsStateAndCountry() async {
    let expectation = XCTestExpectation(description: "geocoder called")
    let mock = MockGeocoder(locality: "TestCity", state: "TestState", country: "TestCountry",
                             onCall: { expectation.fulfill() })

    var cellObjectID: NSManagedObjectID?
    var ctx: NSManagedObjectContext?

    await MainActor.run {
        let container = makeInMemoryContainer()
        ctx           = container.viewContext
        let cell      = insertCell(in: ctx!, locality: nil)
        cellObjectID  = cell.objectID
        let geocoder  = LocalityGeocoder(geocoder: mock, requestDelay: .zero)
        geocoder.enqueue(cell)
    }

    await fulfillment(of: [expectation], timeout: 5)
    try? await Task.sleep(for: .milliseconds(100))

    await MainActor.run {
        guard let id = cellObjectID, let context = ctx,
              let cell = try? context.existingObject(with: id) as? VisitedCell else {
            XCTFail("Could not fetch cell")
            return
        }
        XCTAssertEqual(cell.state, "TestState")
        XCTAssertEqual(cell.country, "TestCountry")
    }
}

func testBackfillRegeocodesCellsMissingStateOrCountry() async {
    // A cell already tagged with `locality` under the old scheme (state/country nil)
    // must be picked up by the backfill and re-geocoded to fill in state/country.
    let expectation = XCTestExpectation(description: "geocoded cell missing state/country")
    let mock = MockGeocoder(locality: "SameCity", state: "NewState", country: "NewCountry",
                             onCall: { expectation.fulfill() })

    var cellID: NSManagedObjectID?
    var context: NSManagedObjectContext?

    await MainActor.run {
        let container = makeInMemoryContainer()
        context       = container.viewContext
        let cell      = insertCell(in: context!, locality: "SameCity", state: nil, country: nil)
        cellID        = cell.objectID
        let geocoder  = LocalityGeocoder(geocoder: mock, requestDelay: .zero)
        geocoder.geocodeUntaggedCells(context: context!)
    }

    await fulfillment(of: [expectation], timeout: 5)
    try? await Task.sleep(for: .milliseconds(100))

    await MainActor.run {
        guard let id = cellID, let ctx = context,
              let cell = try? ctx.existingObject(with: id) as? VisitedCell else {
            XCTFail("Could not fetch cell")
            return
        }
        XCTAssertEqual(cell.state, "NewState")
        XCTAssertEqual(cell.country, "NewCountry")
    }
}
```

- [ ] **Step 5: Run the new tests to verify they fail**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test -only-testing:FogOfWalkTests/LocalityGeocoderTests`
Expected: `testEnqueueSetsStateAndCountry` and `testBackfillRegeocodesCellsMissingStateOrCountry` FAIL (state/country not yet set by production code); `testSkipsAlreadyTaggedCellsDuringBackfill` FAILS too (predicate not yet broadened, so `mock.callCount` would actually already be 0 here since old predicate only checks `locality == nil` — confirm this one still passes; the two new tests are the ones expected to fail).

- [ ] **Step 6: Implement — capture state/country in `geocodeCluster`**

In `FogOfWalk/FogOfWalk/Models/LocalityGeocoder.swift`, update `geocodeCluster(_:)`:

```swift
private func geocodeCluster(_ cluster: PendingCluster) async {
    let location = CLLocation(latitude: cluster.coord.latitude, longitude: cluster.coord.longitude)
    do {
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let p = placemarks.first else { return }
        let name    = p.locality ?? p.subAdministrativeArea ?? p.administrativeArea ?? "Unknown"
        let state   = p.administrativeArea
        let country = p.country
        let ctx = cluster.context
        for id in cluster.objectIDs {
            guard let cell = try? ctx.existingObject(with: id) as? VisitedCell else { continue }
            cell.locality = name
            cell.state    = state
            cell.country  = country
        }
        try? ctx.save()
    } catch {
        // Silently swallow — cells stay nil and will be retried on next launch.
    }
}
```

- [ ] **Step 7: Implement — broaden the backfill predicate**

In the same file, update `geocodeUntaggedCells(context:)`:

```swift
let request = VisitedCell.fetchRequest()
request.predicate = NSPredicate(
    format: "cellSizeMeters == %f AND (locality == nil OR state == nil OR country == nil)",
    kCellSizeMeters
)
```

- [ ] **Step 8: Run the tests again to verify they pass**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test -only-testing:FogOfWalkTests/LocalityGeocoderTests`
Expected: PASS (all tests, including the updated `testSkipsAlreadyTaggedCellsDuringBackfill`)

- [ ] **Step 9: Run the full unit test suite**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test -only-testing:FogOfWalkTests`
Expected: PASS

- [ ] **Step 10: Commit**

```bash
git add FogOfWalk/FogOfWalk/Models/LocalityGeocoder.swift FogOfWalk/FogOfWalkTests/LocalityGeocoderTests.swift
git commit -m "feat: capture and backfill state/country during reverse geocoding"
```

---

### Task 3: Aggregate state/country stats in `DiscoveryStatsModel`

**Files:**
- Modify: `FogOfWalk/FogOfWalk/Models/DiscoveryStatsModel.swift`
- Modify: `FogOfWalk/FogOfWalk/Views/DiscoveryStatsView.swift:271` (field rename only, no behavior change)
- Test: `FogOfWalk/FogOfWalkTests/DiscoveryStatsModelTests.swift`

**Interfaces:**
- Consumes: `VisitedCell.state`/`.country` (Task 1).
- Produces: `LocalityStats.name: String` (renamed from `.locality`); `DiscoveryStatsModel.stateStats: [LocalityStats]` and `.countryStats: [LocalityStats]`, all-time only, sorted by count descending, `"Unknown"` for nil values — consumed by Task 4's UI.

- [ ] **Step 1: Rename `LocalityStats.locality` to `.name`**

In `FogOfWalk/FogOfWalk/Models/DiscoveryStatsModel.swift`, change:

```swift
struct LocalityStats: Identifiable {
    let locality: String
    let count: Int
    let center: CLLocationCoordinate2D
    let span: MKCoordinateSpan
    var id: String { locality }
}
```

to:

```swift
struct LocalityStats: Identifiable {
    let name: String
    let count: Int
    let center: CLLocationCoordinate2D
    let span: MKCoordinateSpan
    var id: String { name }
}
```

- [ ] **Step 2: Update the `buildStats` construction site**

In the same file, inside `refresh(context:)`, change:

```swift
func buildStats(_ dict: [String: [CellID]]) -> [LocalityStats] {
    dict.map { name, ids in
        LocalityStats(
            locality: name,
            count: ids.count,
            center: localityCentroid(ids),
            span: localitySpan(ids)
        )
    }
    .sorted { $0.count > $1.count }
}
```

to:

```swift
func buildStats(_ dict: [String: [CellID]]) -> [LocalityStats] {
    dict.map { name, ids in
        LocalityStats(
            name: name,
            count: ids.count,
            center: localityCentroid(ids),
            span: localitySpan(ids)
        )
    }
    .sorted { $0.count > $1.count }
}
```

- [ ] **Step 3: Fix the one production call site of the renamed field**

In `FogOfWalk/FogOfWalk/Views/DiscoveryStatsView.swift`, in `LocalityRow.row`, change:

```swift
Text(stat.locality)
    .font(.subheadline)
    .lineLimit(1)
```

to:

```swift
Text(stat.name)
    .font(.subheadline)
    .lineLimit(1)
```

- [ ] **Step 4: Fix all test call sites of the renamed field**

`FogOfWalk/FogOfWalkTests/DiscoveryStatsModelTests.swift` has 14 occurrences of `.locality` as a `LocalityStats` field access (as opposed to `VisitedCell.locality` or the `model.locality(for:)` method, which must NOT change). Every one of these occurrences is followed by `,`, `}`, or `==` — `VisitedCell.locality` assignments are followed by whitespace/`=`, and `model.locality(for:` is followed by `(`, so this targeted substitution is safe:

Run:
```bash
sed -i '' -E \
  -e 's/\.locality,/\.name,/g' \
  -e 's/\.locality \}/\.name }/g' \
  -e 's/\.locality ==/\.name ==/g' \
  FogOfWalk/FogOfWalkTests/DiscoveryStatsModelTests.swift
```

Then verify no `cell.locality` or `model.locality(for:` lines were touched:

Run: `grep -n "\.locality\b" FogOfWalk/FogOfWalkTests/DiscoveryStatsModelTests.swift`
Expected output: only line 36 (`cell.locality       = locality`, inside the `insertCell` helper) and the `model.locality(for: ...)` call sites remain — no `.locality,`/`.locality }`/`.locality ==` left.

- [ ] **Step 5: Update the `insertCell` helper to support state/country**

In the same file, replace `insertCell`:

```swift
@discardableResult
func insertCell(
    in ctx: NSManagedObjectContext,
    x: Int32 = 0, y: Int32 = 0,
    cellSizeMeters: Double = 50,
    firstVisited: Date,
    locality: String? = nil,
    state: String? = nil,
    country: String? = nil
) -> VisitedCell {
    let cell = VisitedCell(context: ctx)
    cell.cellX          = x
    cell.cellY          = y
    cell.cellSizeMeters = cellSizeMeters
    cell.firstVisited   = firstVisited
    cell.locality       = locality
    cell.state          = state
    cell.country        = country
    try! ctx.save()
    return cell
}
```

- [ ] **Step 6: Write the new failing tests**

Add to `FogOfWalk/FogOfWalkTests/DiscoveryStatsModelTests.swift`:

```swift
// MARK: - State breakdown (all-time only)

func testStateGroupingAggregatesCorrectly() async {
    await MainActor.run {
        let container = makeInMemoryContainer()
        let ctx       = container.viewContext
        let now       = Date()

        insertCell(in: ctx, x: 0, y: 0, firstVisited: now, state: "California")
        insertCell(in: ctx, x: 1, y: 0, firstVisited: now, state: "California")
        insertCell(in: ctx, x: 2, y: 0, firstVisited: now, state: "Nevada")

        let model = DiscoveryStatsModel()
        model.refresh(context: ctx)

        XCTAssertEqual(model.stateStats.count, 2)
        XCTAssertEqual(model.stateStats.first?.name, "California")
        XCTAssertEqual(model.stateStats.first?.count, 2)
        XCTAssertEqual(model.stateStats.last?.name, "Nevada")
        XCTAssertEqual(model.stateStats.last?.count, 1)
    }
}

func testNilStateAppearsAsUnknown() async {
    await MainActor.run {
        let container = makeInMemoryContainer()
        let ctx       = container.viewContext
        let now       = Date()

        insertCell(in: ctx, x: 0, y: 0, firstVisited: now, state: nil)

        let model = DiscoveryStatsModel()
        model.refresh(context: ctx)

        XCTAssertEqual(model.stateStats.first?.name, "Unknown")
    }
}

func testStateStatsIncludeOldCells() async {
    await MainActor.run {
        let container = makeInMemoryContainer()
        let ctx       = container.viewContext
        let now       = Date()

        insertCell(in: ctx, x: 0, y: 0, firstVisited: now.addingTimeInterval(-30 * 86400), state: "Oregon")

        let model = DiscoveryStatsModel()
        model.refresh(context: ctx)

        XCTAssertTrue(model.stateStats.map { $0.name }.contains("Oregon"),
            "State stats are all-time — old cells must still be included")
    }
}

func testStateStatsEmptyWhenNoData() async {
    await MainActor.run {
        let container = makeInMemoryContainer()
        let model     = DiscoveryStatsModel()
        model.refresh(context: container.viewContext)
        XCTAssertTrue(model.stateStats.isEmpty)
    }
}

// MARK: - Country breakdown (all-time only)

func testCountryGroupingAggregatesCorrectly() async {
    await MainActor.run {
        let container = makeInMemoryContainer()
        let ctx       = container.viewContext
        let now       = Date()

        insertCell(in: ctx, x: 0, y: 0, firstVisited: now, country: "United States")
        insertCell(in: ctx, x: 1, y: 0, firstVisited: now, country: "United States")
        insertCell(in: ctx, x: 2, y: 0, firstVisited: now, country: "Canada")

        let model = DiscoveryStatsModel()
        model.refresh(context: ctx)

        XCTAssertEqual(model.countryStats.count, 2)
        XCTAssertEqual(model.countryStats.first?.name, "United States")
        XCTAssertEqual(model.countryStats.first?.count, 2)
        XCTAssertEqual(model.countryStats.last?.name, "Canada")
        XCTAssertEqual(model.countryStats.last?.count, 1)
    }
}

func testNilCountryAppearsAsUnknown() async {
    await MainActor.run {
        let container = makeInMemoryContainer()
        let ctx       = container.viewContext
        let now       = Date()

        insertCell(in: ctx, x: 0, y: 0, firstVisited: now, country: nil)

        let model = DiscoveryStatsModel()
        model.refresh(context: ctx)

        XCTAssertEqual(model.countryStats.first?.name, "Unknown")
    }
}

func testCountryStatsEmptyWhenNoData() async {
    await MainActor.run {
        let container = makeInMemoryContainer()
        let model     = DiscoveryStatsModel()
        model.refresh(context: container.viewContext)
        XCTAssertTrue(model.countryStats.isEmpty)
    }
}
```

- [ ] **Step 7: Run the new tests to verify they fail**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test -only-testing:FogOfWalkTests/DiscoveryStatsModelTests`
Expected: the 6 new tests FAIL with "value of type 'DiscoveryStatsModel' has no member 'stateStats'" (or similar) — everything else should still PASS after Steps 1–5's rename.

- [ ] **Step 8: Implement — add the published properties**

In `FogOfWalk/FogOfWalk/Models/DiscoveryStatsModel.swift`, add next to `localityByPeriod`:

```swift
var stateStats: [LocalityStats] = []
var countryStats: [LocalityStats] = []
```

- [ ] **Step 9: Implement — accumulate and compute state/country stats in `refresh(context:)`**

In the same file, in the "Single pass" accumulator declarations, add:

```swift
var allStateCells:     [String: [CellID]] = [:]
var allCountryCells:   [String: [CellID]] = [:]
```

In the `for cell in cells` loop, after the existing `allLocalityCells[locality, default: []].append(cellID)` line, add:

```swift
let state   = cell.state ?? "Unknown"
let country = cell.country ?? "Unknown"
allStateCells[state, default: []].append(cellID)
allCountryCells[country, default: []].append(cellID)
```

After the `localityByPeriod = [...]` assignment near the end of `refresh(context:)`, add:

```swift
stateStats   = buildStats(allStateCells)
countryStats = buildStats(allCountryCells)
```

- [ ] **Step 10: Run the tests again to verify they pass**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test -only-testing:FogOfWalkTests/DiscoveryStatsModelTests`
Expected: PASS

- [ ] **Step 11: Run the full unit test suite**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test -only-testing:FogOfWalkTests`
Expected: PASS

- [ ] **Step 12: Commit**

```bash
git add FogOfWalk/FogOfWalk/Models/DiscoveryStatsModel.swift FogOfWalk/FogOfWalk/Views/DiscoveryStatsView.swift FogOfWalk/FogOfWalkTests/DiscoveryStatsModelTests.swift
git commit -m "feat: aggregate all-time state/country breakdowns in DiscoveryStatsModel"
```

---

### Task 4: Add States/Countries sections to Discovery Stats UI

**Files:**
- Modify: `FogOfWalk/FogOfWalk/Views/DiscoveryStatsView.swift`

**Interfaces:**
- Consumes: `DiscoveryStatsModel.stateStats`/`.countryStats: [LocalityStats]` (Task 3); existing `LocalityRow` (`stat: LocalityStats`, `maxCount: Int`, `action: (() -> Void)?`); existing `onNavigate: ((MapNavigationTarget) -> Void)?` and `MapNavigationTarget(center:span:)`.

- [ ] **Step 1: Add a shared list-section view**

`localitySection`, and the two new sections, all render "a list of `LocalityRow`s with an empty-state fallback" — add a small private view to avoid duplicating that ~15-line block twice. In `FogOfWalk/FogOfWalk/Views/DiscoveryStatsView.swift`, add near the other private views at the bottom of the file (after `LocalityRow`):

```swift
// MARK: - LocalityListSection

private struct LocalityListSection: View {
    let title: String
    let emptyText: String
    let data: [LocalityStats]
    var onNavigate: ((MapNavigationTarget) -> Void)?
    var dismiss: () -> Void

    var body: some View {
        GroupBox {
            if data.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(data) { stat in
                        LocalityRow(
                            stat: stat,
                            maxCount: data.first?.count ?? 1,
                            action: onNavigate.map { navigate in {
                                navigate(MapNavigationTarget(center: stat.center, span: stat.span))
                                dismiss()
                            }}
                        )
                        if stat.id != data.last?.id {
                            Divider()
                        }
                    }
                }
            }
        } label: {
            Text(title)
                .font(.headline)
        }
    }
}
```

- [ ] **Step 2: Add the two new section computed properties**

In the same file, add after `localitySection`:

```swift
// MARK: - States

private var statesSection: some View {
    LocalityListSection(title: "States", emptyText: "No states explored yet.",
                         data: model.stateStats, onNavigate: onNavigate, dismiss: { dismiss() })
}

// MARK: - Countries

private var countriesSection: some View {
    LocalityListSection(title: "Countries", emptyText: "No countries explored yet.",
                         data: model.countryStats, onNavigate: onNavigate, dismiss: { dismiss() })
}
```

- [ ] **Step 3: Wire the new sections into the body**

In the same file, change the `body`'s `VStack`:

```swift
VStack(spacing: 24) {
    summaryCards
    weeklyChart
    localitySection
    allTimeSection
    landmarksSection
}
```

to:

```swift
VStack(spacing: 24) {
    summaryCards
    weeklyChart
    localitySection
    statesSection
    countriesSection
    allTimeSection
    landmarksSection
}
```

- [ ] **Step 4: Build**

There are no SwiftUI previews and no existing view-level unit tests for `DiscoveryStatsView` in this codebase (per `AGENTS.md` testing conventions) — a successful build is the verification step for this task.

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Run the full unit test suite (no regressions expected — no logic changed)**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test -only-testing:FogOfWalkTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add FogOfWalk/FogOfWalk/Views/DiscoveryStatsView.swift
git commit -m "feat: show States and Countries sections in Discovery Stats"
```

---

### Task 5: Carry state/country through the backup payload

**Files:**
- Modify: `FogOfWalk/FogOfWalk/Models/BackupService.swift`
- Modify: `FogOfWalk/FogOfWalk/Models/ExplorationStore.swift`
- Test: `FogOfWalk/FogOfWalkTests/BackupServiceTests.swift`
- Test: `FogOfWalk/FogOfWalkTests/ExplorationStoreTests.swift`

**Interfaces:**
- Consumes: `VisitedCell.state`/`.country` (Task 1).
- Produces: `BackupVisitedCell.state: String?`/`.country: String?` (default `nil`, so existing call sites without them keep compiling); `BackupPayload.currentSchemaVersion == 2`; `ExplorationStore.addCells(_:)` now also sets `state`/`country` on newly-inserted rows.

- [ ] **Step 1: Add state/country to the backup record type and bump the schema version**

In `FogOfWalk/FogOfWalk/Models/BackupService.swift`, change:

```swift
struct BackupVisitedCell: Codable, Equatable {
    let cellX: Int32
    let cellY: Int32
    let cellSizeMeters: Double
    let firstVisited: Date?
    let locality: String?
}
```

to:

```swift
struct BackupVisitedCell: Codable, Equatable {
    let cellX: Int32
    let cellY: Int32
    let cellSizeMeters: Double
    let firstVisited: Date?
    let locality: String?
    let state: String? = nil
    let country: String? = nil
}
```

(Default values keep every existing call site — production and test — compiling without changes; only sites that need to assert on state/country will pass them explicitly.)

And bump:

```swift
struct BackupPayload: Codable, Equatable {
    static let currentSchemaVersion = 2
    ...
```

- [ ] **Step 2: Write the failing tests**

In `FogOfWalk/FogOfWalkTests/BackupServiceTests.swift`, update `samplePayload()` to exercise the new fields:

```swift
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
```

(`testEncodeDecodeRoundTrip`'s existing `XCTAssertEqual(decoded, payload)` now exercises state/country round-tripping for free.)

Add a new test for export:

```swift
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
```

In `FogOfWalk/FogOfWalkTests/ExplorationStoreTests.swift`, add a new test for merge:

```swift
func testAddCellsCarriesStateAndCountryThrough() async throws {
    try await MainActor.run {
        let store = ExplorationStore(container: makeInMemoryContainer())
        store.configure()

        let record = BackupVisitedCell(cellX: 8, cellY: 8, cellSizeMeters: kCellSizeMeters,
                                        firstVisited: Date(timeIntervalSince1970: 1_000),
                                        locality: "Metropolis", state: "New York", country: "United States")

        _ = try store.addCells([record])

        let request = NSFetchRequest<VisitedCell>(entityName: "VisitedCell")
        request.predicate = NSPredicate(format: "cellX == 8 AND cellY == 8")
        let fetched = try? store.viewContext.fetch(request)
        XCTAssertEqual(fetched?.first?.state, "New York")
        XCTAssertEqual(fetched?.first?.country, "United States")
    }
}
```

- [ ] **Step 3: Run the new/updated tests to verify they fail**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test -only-testing:FogOfWalkTests/BackupServiceTests -only-testing:FogOfWalkTests/ExplorationStoreTests`
Expected: `testExportDataIncludesStateAndCountry` and `testAddCellsCarriesStateAndCountryThrough` FAIL (production code doesn't populate state/country yet); other tests still PASS since Step 1's defaults keep them compiling with `state`/`country` as `nil`.

- [ ] **Step 4: Implement — carry state/country through export**

In `FogOfWalk/FogOfWalk/Models/BackupService.swift`, update `exportData`:

```swift
let cellRecords = cells.map {
    BackupVisitedCell(cellX: $0.cellX, cellY: $0.cellY, cellSizeMeters: $0.cellSizeMeters,
                       firstVisited: $0.firstVisited, locality: $0.locality,
                       state: $0.state, country: $0.country)
}
```

- [ ] **Step 5: Implement — carry state/country through merge**

In `FogOfWalk/FogOfWalk/Models/ExplorationStore.swift`, in `addCells(_:)`, update the new-cell insert branch:

```swift
let entity = VisitedCell(context: ctx)
entity.cellX          = record.cellX
entity.cellY          = record.cellY
entity.cellSizeMeters = kCellSizeMeters
entity.firstVisited   = record.firstVisited ?? nowProvider()
entity.locality       = record.locality
entity.state          = record.state
entity.country        = record.country
byID[id] = entity
addedCount += 1
```

(Existing cells are left untouched, matching how `locality` is already handled — a merge never overwrites already-geocoded data.)

- [ ] **Step 6: Run the tests again to verify they pass**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test -only-testing:FogOfWalkTests/BackupServiceTests -only-testing:FogOfWalkTests/ExplorationStoreTests`
Expected: PASS

- [ ] **Step 7: Run the full test suite (unit + UI tests — this is the last task)**

Run: `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' test`
Expected: PASS

- [ ] **Step 8: Update AGENTS.md**

`AGENTS.md`'s "Backup export/import" section documents the JSON format with a sample `visitedCells` entry and describes `BackupVisitedCell`'s fields. Update the sample JSON and field list to include `state`/`country`, and note the schema version is now 2. Also update the "Core Data model" bullet in the project layout / `VisitedCell+CoreData.swift` description to mention `state`/`country` alongside `locality`.

- [ ] **Step 9: Commit**

```bash
git add FogOfWalk/FogOfWalk/Models/BackupService.swift FogOfWalk/FogOfWalk/Models/ExplorationStore.swift FogOfWalk/FogOfWalkTests/BackupServiceTests.swift FogOfWalk/FogOfWalkTests/ExplorationStoreTests.swift AGENTS.md
git commit -m "feat: carry state/country through backup export/import (schema v2)"
```
