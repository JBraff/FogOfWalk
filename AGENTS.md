# Fog of Walk — Agent Guide

iOS app that overlays a "fog of war" on Apple Maps and lifts it as the user physically walks through the world. Written in Swift. App target deploys to iOS 18.6; test targets to 26.2.

---

## Project layout

```
FogOfWalk/
  FogOfWalk.xcodeproj              # No shared scheme — see Build & run below
  FogOfWalk/
    FogOfWalkApp.swift              # @main — creates the six environment objects
    ContentView.swift                # Root view: MapContainerView + StatsView + sheets
    Info.plist                       # Location permission strings, UIBackgroundModes: [location], single-scene
    landmarks.sqlite                 # Bundled landmark DB — see SETUP.md for how it's wired
    FogOfWalk.xcdatamodeld/          # Core Data model — two versions (v1, v2) inside one .xcdatamodeld;
                                      # .xccurrentversion selects "FogOfWalk 2.xcdatamodel"
    Models/
      GridCell.swift                 # CellID, kCellSizeMeters (50m), GridMath namespace
      GridSettings.swift             # @MainActor @Observable — highlightToday, showLandmarks
      ExplorationStore.swift         # @MainActor @Observable — Core Data + in-memory cache
      VisitedCell+CoreData.swift     # NSManagedObject subclass (cellX, cellY, cellSizeMeters, firstVisited, locality, state, country)
      LandmarkStore.swift            # @MainActor @Observable — discovery state, Wikidata migration
      BackupService.swift            # Versioned JSON export/import + merge-import into both stores
      CellSnapshot.swift             # Immutable, thread-safe snapshot of visited/recent cells for the renderer
      LocalityGeocoder.swift         # Reverse-geocodes cells in the background, bucketed queue
      DiscoveryStatsModel.swift      # Streaks, locality breakdowns, estimated distance
    Services/
      LocationService.swift          # @MainActor @Observable wrapping CLLocationManager
      BundledLandmarkSource.swift    # Reads landmarks.sqlite via an R-tree spatial query
      LandmarkSearchService.swift    # @MainActor — debounced region search, feeds LandmarkStore
    Views/
      MapContainerView.swift         # UIViewRepresentable: MKMapView + FogOverlay (MKOverlay) + LandmarkOverlayView sibling
      FogOverlay.swift                # FogOverlay (MKOverlay), FogRenderer (pure struct), FogOverlayRenderer (MKOverlayRenderer)
      LandmarkOverlayView.swift       # UIView sibling: discovered-landmark icons + undiscovered "?" hints
      LandmarkDetailView.swift        # Sheet shown when a discovered pin is tapped
      StatsView.swift                 # HUD: today count, discovered-landmark count, paused indicator, stats button
      SettingsView.swift              # Sheet: export/import backup (BackupService)
      DiscoveryStatsView.swift        # Sheet: streaks, locality breakdowns, "N% of city explored"
      AlwaysLocationBanner.swift      # Prompts upgrading When-In-Use → Always
  FogOfWalkTests/                     # 13 files: FogOfWalkTests.swift, ExplorationStoreTests.swift,
                                       # FogOverlayRendererTests.swift, CellSnapshotTests.swift,
                                       # GestureTransformTests.swift, LocationServiceTests.swift,
                                       # LocalityGeocoderTests.swift, DiscoveryStatsModelTests.swift,
                                       # LandmarkStoreTests.swift, LandmarkSearchServiceTests.swift,
                                       # LandmarkOverlayViewTests.swift, BundledLandmarkSourceTests.swift,
                                       # BackupServiceTests.swift
  FogOfWalkUITests/
    FogOfWalkUITests.swift            # UI automation tests
    FogOfWalkUITestsLaunchTests.swift # Launch screenshot tests
scripts/
  fetch_landmarks.py                  # Queries Wikidata SPARQL for landmark candidates
  make_landmarks_db.py                # Builds landmarks.sqlite (table + R-tree index) from the JSON output
  landmarks_10.json, landmarks_preview.json  # Checked-in inputs to make_landmarks_db.py
SETUP.md                              # How the checked-in project is wired, build/run, regenerating landmarks.sqlite
```

There is no `FogView.swift` — it was removed; see below. `SettingsView.swift` exists again as of the backup export/import feature (below), reintroducing a settings screen after its earlier removal.

---

## Architecture

### Data flow
```
CLLocationManager → LocationService.onLocationUpdate closure
  → Coordinator.handle(location:)
    → store.refreshForDayChangeIfNeeded()             [resets "today" state at midnight]
    → ExplorationStore.addCell(_:)                     [Core Data + in-memory Set]
      → Coordinator.invalidateFogTiles()               [pushes a fresh CellSnapshot to the renderer]
    → LandmarkStore.checkDiscovery(newCell:)            [O(1)-ish: only landmarks near this one cell]
```

`FogOverlayRenderer.draw(_:zoomScale:in:)` runs on MapKit's own background tile-rendering
threads, reading the `CellSnapshot` under an `NSLock`. Fog tracks pan/zoom natively as an
`MKOverlay` — there is no manual `CATransform3D` for it. `LandmarkOverlayView` is a plain
`UIView` sibling that *does* need a manual `CATransform3D` during gestures (applied in
`mapViewDidChangeVisibleRegion(_:)`), because it isn't an `MKOverlay`.

### Environment objects
All six are injected at the `WindowGroup` level via `.environment(...)` and accessed with `@Environment(T.self)` (`FogOfWalkApp.swift`):

| Type | Role |
|------|------|
| `ExplorationStore` | Source of truth for visited cells and today/total counts; wraps Core Data |
| `GridSettings` | `highlightToday: Bool` (today's-walk highlight) and `showLandmarks: Bool` (pin display toggle) |
| `LocationService` | Location permission + streaming; exposes `onLocationUpdate` closure |
| `LocalityGeocoder` | Reverse-geocodes newly walked cells in the background |
| `LandmarkStore` | Discovery state for landmarks; owns the Wikidata migration |
| `LandmarkSearchService` | Debounced region search against the bundled landmark DB |

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the app target means every type in it is
implicitly `@MainActor` unless annotated otherwise — the explicit `@MainActor` on these six is
belt-and-suspenders, not the only thing making them main-actor.

### Coordinate system
`GridMath` divides the globe into a uniform rectangular grid. `CellID(x: Int32, y: Int32)` is the grid address. Converting a `CLLocationCoordinate2D` to a `CellID` and back is pure arithmetic — no map SDK required. The grid is always aligned to `(0,0)` at (0°, 0°).

Cell size is fixed at `kCellSizeMeters = 50.0` (defined in `GridCell.swift`). The `VisitedCell` Core Data entity retains the `cellSizeMeters` column for existing data; all new rows are written with 50.0.

### Fog rendering
`FogOverlay` (`Views/FogOverlay.swift`) is an `MKOverlay`, not a `UIView`. `FogOverlayRenderer`
(an `MKOverlayRenderer`) draws it on MapKit's background tile threads, guarded by an `NSLock`
around its `CellSnapshot`. The pure geometry/gradient logic lives in the `FogRenderer` struct so
it can be unit-tested without a live `MKOverlayRenderer`.

Per visited cell, the renderer punches a clip-bounded radial gradient hole rather than filling
the whole clip region and relying on `.drawsAfterEndLocation` — both gradients (`holeGradient`,
`highlightGradient`) already terminate at alpha 0, so filling the full clip was always a
no-op that cost a full-tile rasterization per cell. Sub-pixel cells are skipped via the
`radius > 0.5` guard (`FogOverlay.swift:103`, `:126`) — note this guard is inert at every zoom
level MapKit actually renders at, because renderer-space is zoom-invariant; treat it as
harmless, not load-bearing.

`Coordinator.invalidateFogTiles()` replaces the old `FogView.update(cells:cellSize:)` call —
it builds a fresh `CellSnapshot` and marks the renderer's tiles dirty.
`mapViewDidChangeVisibleRegion(_:)` no longer touches fog at all; it only applies a
`CATransform3D` to `LandmarkOverlayView` during gestures. Tests live in
`FogOverlayRendererTests.swift`; there is no `FogViewTests.swift`.

### Backup export/import

`BackupService` (`Models/BackupService.swift`) is a stateless `enum` — plain namespaced static
functions, not a store. It encodes/decodes a versioned JSON `BackupPayload`
(`visitedCells` + discovered `landmarks` only — undiscovered landmarks and all landmark
metadata besides `identifier`/`firstDiscovered` are intentionally excluded, since metadata is
re-derived from bundled reference data on the importing device) and orchestrates merging it
into both stores. `BackupPayload.currentSchemaVersion` is `2`; a sample `visitedCells` entry
looks like:

```json
{
  "cellX": 1,
  "cellY": 2,
  "cellSizeMeters": 50.0,
  "firstVisited": "2023-11-14T22:13:20Z",
  "locality": "Springfield",
  "state": "Illinois",
  "country": "United States"
}
```

`BackupVisitedCell.state`/`.country` (added alongside `locality` when the Discovery Stats sheet
started breaking down visited cells by state/country) default to `nil`, so a schema-version-1
backup file — missing those keys entirely — still decodes cleanly.

- `ExplorationStore.addCells(_:)` inserts cells absent locally and keeps the earlier
  `firstVisited` date for cells that already exist.
- `LandmarkStore.restoreDiscovered(_:)` marks known-by-`identifier` landmarks discovered and
  keeps the earlier `firstDiscovered` date; unknown identifiers are skipped without error.

`SettingsView` (`Views/SettingsView.swift`), reachable via a gear button in `StatsView`, drives
export through `ShareLink` and import through `.fileImporter`. This is manual/on-demand only —
there is no automatic or continuous sync (no CloudKit).

---

## Key constraints and gotchas

- **Cell count cap:** `GridMath.cells(in:)` returns `[]` when a region would produce >10 000 cells. At world zoom the fog stays fully opaque — this is intentional and correct.
- **`@MainActor` everywhere:** all six environment objects (see table above) are `@MainActor`. `CLLocationManagerDelegate` methods on `LocationService` are `nonisolated` and dispatch back via `Task { @MainActor in ... }`.
- **Closure rewiring:** `locationService.onLocationUpdate` is reassigned in `updateUIView` (not just `makeUIView`) so it always captures the live coordinator after SwiftUI rebuilds.
- **Core Data context:** Always use `container.viewContext` (main-queue context). `automaticallyMergesChangesFromParent = true` is set. `NSBatchDeleteRequest` results are merged back manually via `NSManagedObjectContext.mergeChanges(fromRemoteContextSave:into:)`.
- **`@Observable` / iOS 17 APIs:** required — do not back-port to `ObservableObject`. This is about not regressing, not about the deployment floor (see the top of this file for the actual floor).
- **No Swift Testing / #Preview:** confirmed zero hits repo-wide for `import Testing`, `@Test`, `#expect`. The test target uses XCTest only. There are no SwiftUI previews — test rendering in the simulator.
- **No haptics.** Deliberate: tracking runs for hours in the background, so a buzz per newly
  walked 50 m cell is noise rather than feedback. Don't reintroduce one.
- **`showLandmarks` is off by default.** Landmark *discovery* (`LandmarkStore.checkDiscovery`) always runs regardless of this setting — only pin *display* in `LandmarkOverlayView` is gated on it (`Coordinator.refreshLandmarks`). Don't mistake missing pins for a discovery bug; check the toggle first.
- **City % calculation:** `DiscoveryStatsModel` / `LocalityGeocoder` reverse-geocode cells to get a city name and `CLCircularRegion`. The percentage is relative to that circle, not actual administrative boundaries — it's an approximation.
- **`cos(latitude)` correction:** `ExplorationStore.totalCellCount` divides the longitude span by `cos(lat)` to correct for meridian convergence. Without this, city % is wrong at non-equatorial latitudes.
- **Build settings that affect concurrency:** `SWIFT_VERSION = 5.0` (Swift 5 language mode — cross-actor isolation violations are **warnings**, not errors), `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the app target only (this is why `BundledLandmarkSource` is implicitly `@MainActor` with no annotation), `SWIFT_APPROACHABLE_CONCURRENCY = YES` — which means a plain `nonisolated async func` called from a `@MainActor` context still runs **on the caller's actor**; reaching the global executor requires `@concurrent` or `Task.detached`.
- **The product is renamed at the build-settings level.** `PRODUCT_NAME = "Fog-Of-Walk"` with `PRODUCT_MODULE_NAME` pinned to `FogOfWalk` and `TEST_HOST` repointed at `Fog-Of-Walk.app` — so the built app bundle is `Fog-Of-Walk.app` while `@testable import FogOfWalk` still resolves. If a rename or scheme edit ever breaks this pairing, the test target fails to launch with a message about scheme membership, not anything pointing at the actual cause — see the no-shared-scheme note under Build & run.
- **No known way to delete location history in the running app.** `ExplorationStore.deleteAllCells`, `visitedCellCount`, `totalCellCount`, and `Coordinator.replaceFogOverlay` exist but have no production caller — this is a known gap, not a feature to build around. (The Settings screen added for backup export/import does *not* address this — it only exports/imports/merges, it never deletes.)

---

## Testing conventions

- **XCTest only** — do not use Swift Testing (`#expect`, `@Test`, etc.).
- **`@MainActor @Observable` store tests must be `async`**, wrapping every interaction in `await MainActor.run { }`. This works around an iOS 26 simulator crash (`swift_task_deinitOnExecutorImpl` / TaskLocal heap corruption) that occurs when such an object is deallocated outside a Swift `Task` context. See the header comments in `LandmarkStoreTests.swift` and `ExplorationStoreTests.swift` for the full explanation.
- **Renderer tests are different:** `FogOverlayRendererTests.swift` marks the whole test class `@MainActor` and uses plain synchronous test methods — no `async`/`await MainActor.run`. Follow whichever pattern matches the class you're extending.
- **`makeInMemoryContainer()` is copy-pasted**, not shared, across `ExplorationStoreTests.swift`, `LandmarkStoreTests.swift`, `DiscoveryStatsModelTests.swift`, and `LocalityGeocoderTests.swift`. Use the copy in the file you're editing; don't introduce a shared base class as a drive-by refactor.
- **`LandmarkSearchServiceTests.swift` polls instead of using `XCTestExpectation`** — a small sleep-and-poll loop, since the service's debounce timing doesn't map cleanly onto expectations.
- **`installCoordinateMock()`** (`LandmarkOverlayViewTests.swift`) injects a deterministic `coordinateToPoint` for **pin** tests — it has nothing to do with fog/renderer tests, which instead use `renderFog(...)` and `pixelColor(at:in:)` (`FogOverlayRendererTests.swift`).
- **`NSBatchDeleteRequest` on in-memory stores:** raises `NSException` (not a Swift `Error`). Production code checks for `NSInMemoryStoreType` before choosing between batch and manual delete. Do not attempt batch delete in tests.

---

## Known platform quirks

- **iOS 26 beta — `@Observable` dealloc crash:** `@MainActor @Observable` objects crash when deallocated in non-Task XCTest context. Workaround: make test methods `async` and wrap work in `await MainActor.run { }`.
- **iOS 26 beta — `NSBatchDeleteRequest` on in-memory stores:** throws `NSException` instead of returning an error. Workaround: check the store type and fall back to manual `context.delete()` loop for in-memory stores.

---

## Build & run

```bash
# Build (replace simulator ID if needed)
xcodebuild \
  -project FogOfWalk/FogOfWalk.xcodeproj \
  -scheme FogOfWalk \
  -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' \
  build

# Run tests
xcodebuild \
  -project FogOfWalk/FogOfWalk.xcodeproj \
  -scheme FogOfWalk \
  -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' \
  test
```

To find an available simulator if the ID above is stale:
```bash
xcrun simctl list devices available | grep iPhone
```

**There is no shared scheme.** `FogOfWalk.xcodeproj/xcshareddata/` doesn't exist — only
`xcuserdata/` — so `-scheme FogOfWalk` resolves via an autocreated user scheme, which would fail
on CI or a fresh clone (there is no CI in this repo: no `.github/`, `fastlane/`, or `Makefile`).
This is the exact mechanism that made the `Fog-Of-Walk` product rename (see above) a confusing
one-time break: renaming the target dropped the test target from the autocreated scheme, and
`xcodebuild test` failed with "FogOfWalkTests isn't a member of the specified test plan or
scheme" — a message that points nowhere near the actual cause. If `xcodebuild test` ever fails
that way again with no source changes, suspect the autocreated scheme, not the code.

### Simulating movement
In the running simulator: **Features → Location → City Bicycle Ride** (or Apple). Watch the fog lift in real time.

---

## Adding features — checklist

1. New persistent data? Add an entity to `FogOfWalk.xcdatamodeld` (as a new model version), create a `+CoreData.swift` subclass, update `ExplorationStore` and/or `LandmarkStore`.
2. New setting? Add a property to `GridSettings` with a `UserDefaults` `didSet`, following the `highlightToday` / `showLandmarks` pattern.
3. New view? Access environment objects with `@Environment(ExplorationStore.self)` etc. Keep views `@MainActor`-safe.
4. New math on cells? Put it in `GridMath` (static functions, no stored state).
5. **Every feature or bug fix must include tests.** Add or update unit tests for any new logic, model changes, or view behavior. If fixing a bug, add a regression test that would have caught it.
6. New tests? Follow the async/`MainActor` pattern for anything touching a `@MainActor @Observable` store. Use the file's own `makeInMemoryContainer()`. For pin-rendering tests, use `installCoordinateMock()`; for fog-rendering tests, use `renderFog(...)` and `pixelColor(at:in:)`.
7. Always run the full test suite (`xcodebuild ... test`), not just the new tests.
8. After any change: build **and tests** must succeed before considering the task done.
