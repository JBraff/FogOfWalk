# Fog of Walk — Agent Guide

iOS app that overlays a "fog of war" on Apple Maps and lifts it as the user physically walks through the world. Swift (Swift 5 language mode), SwiftUI + MapKit/UIKit, Core Data, XCTest. App target deploys to iOS 18.6; test targets to 26.2. Last verified with Xcode 27.

## Workspace navigation and active work

<!-- workspace-instructions:v1 -->

At task start, locate the independent `agent-workspace` checkout: use
`AGENT_WORKSPACE_PATH` if set (the checkout itself), else
`$WORKSPACE_ROOT/agent-workspace` if set, else the direct sibling of this
product's **main Git checkout**. For a managed worktree, derive the main checkout
from `git worktree list --porcelain` before using the sibling fallback. Do not
scan parent trees. Verify the candidate with
`python3 <workspace>/scripts/product-instructions.py resolve --project fog-of-walk --checkout <product-root>`;
if it is missing or mismatched, stop and report that fact. Then read its
`AGENTS.md` and `registry.yaml`, even for Fog-only work. Load only the
relevant initiative, runbook, and Fog documentation. Durable product context
starts at `docs/README.md` and `docs/SYSTEM.md`.

Workspace rules govern shared delivery, initiative tracking, and verified
completion; this guide governs Fog behavior. Keep current-work lifecycle,
milestones, blockers, and next actions in the authorized workspace initiative.
For authorized record updates, obtain workspace write access, then run
`./scripts/render-portfolio.sh` and `./scripts/validate.sh` there. If access is
unavailable, report the exact pending tracking update and continue independent
authorized product work.

---

## Orientation

- **What matters most:** a real location sample becomes a 50 m grid cell, the cell is
  persisted, and the fog over it clears. Everything else (landmarks, stats, backup) hangs
  off that path. The path is described under **Data flow**.
- **One target, two apps.** The normal app and an isolated **Study** app (used for
  location-battery feasibility experiments) are built from the same target and differ only by
  bundle ID. Read **Two app identities** before touching `LocationService`, `FogOfWalkApp`,
  `MapContainerView`, or `SettingsView`.
- **Location/battery work:** after this file, read `docs/SYSTEM.md`, then the current proposal
  and prototype record linked from `docs/README.md`. Older proposals and evidence there are
  historical. Their next-step instructions don't apply.
- **Definition of done:** build and full XCTest suite pass (see **Build & test**). If the
  simulator is unavailable, say so. A compile-only build is not a test pass.

---

## Project layout

```
FogOfWalk/
  FogOfWalk.xcodeproj                # Synchronized folders; no shared scheme (see Build & test)
  FogOfWalk/
    FogOfWalkApp.swift               # @main: creates the six environment objects; wires Study recording
    ContentView.swift                # Root: MapContainerView + StatsView HUD + sheets; day-rollover listeners
    Info.plist                       # Location + motion purpose strings, UIBackgroundModes [location],
                                     # single scene, CFBundleDisplayName = $(FOG_APP_DISPLAY_NAME)
    landmarks.sqlite                 # Bundled Wikidata landmark DB (~4 MB, R-tree indexed)
    FogOfWalk.xcdatamodeld/          # Three model versions; .xccurrentversion = "FogOfWalk 3.xcdatamodel"
                                     # (v2 added Landmark + fetch index; v3 added VisitedCell.state/country)
    Models/
      GridCell.swift                 # kCellSizeMeters (50 m), CellID, GridMath
      ExplorationStore.swift         # Visited cells: Core Data + in-memory caches, today/total counts
      VisitedCell+CoreData.swift     # cellX/Y, cellSizeMeters, firstVisited, locality, state, country
      LandmarkStore.swift            # Landmark rows, bucketed discovery, one-time Wikidata-ID migration
      Landmark+CoreData.swift        # identifier (Wikidata QID), name, category, lat/lon, radius, dates
      WikidataLandmark.swift         # Value type read from landmarks.sqlite
      CellSnapshot.swift             # Immutable row-bucketed cell sets, read by the renderer off-main
      GridSettings.swift             # highlightToday, showLandmarks (UserDefaults-backed)
      LocalityGeocoder.swift         # Reverse-geocodes cells → locality/state/country (CLGeocoder)
      DiscoveryStatsModel.swift      # Stats sheet model: counts, streaks, locality/state/country lists
      USState.swift                  # 50-state normalization for the States list
      BackupService.swift            # Versioned JSON export/import with merge semantics
    Services/
      LocationService.swift          # CLLocationManager wrapper: legacy tracking + Study source switching
      ExplorationRecorder.swift      # Shared location → cell → discovery path for both app identities
      StationaryLocationSource.swift # Study-only CLLocationUpdate.liveUpdates source; StudyLocationSource enum
      LocationStudyDiagnostics.swift # Study-only opt-in JSONL capture; shadow sample validator
      StudyMotionReference.swift     # Study-only post-run Core Motion/pedometer history query
      BundledLandmarkSource.swift    # SQLite R-tree query over landmarks.sqlite
      LandmarkSearchService.swift    # Rate-limited landmark ingest as the map region changes
    Views/
      MapContainerView.swift         # UIViewRepresentable: MKMapView + FogOverlay + LandmarkOverlayView; Coordinator
      FogOverlay.swift               # FogOverlay (MKOverlay), FogRenderer (pure CG), FogOverlayRenderer
      LandmarkOverlayView.swift      # UIView sibling: discovered pins + "?" hints, tap hit-testing
      LandmarkDetailView.swift       # Sheet for a tapped discovered pin
      StatsView.swift                # Bottom HUD: "N new today" (toggles highlight), landmark count, Paused, buttons
      DiscoveryStatsView.swift       # Stats sheet (Swift Charts)
      SettingsView.swift             # Backup export/import; Study-only "Location Study" section
      AlwaysLocationBanner.swift     # Prompt to upgrade While Using → Always
  FogOfWalkTests/                    # XCTest unit tests: roughly one <Type>Tests.swift per production type, plus
                                     # FogOfWalkTests.swift (GridMath) and StudyTrackingControlTests.swift (Study OFF)
  FogOfWalkUITests/                  # Template only: FogOfWalkUITests has no test methods; the launch test
                                     # just attaches a screenshot
docs/                                # Durable product docs; start at docs/README.md
scripts/
  fetch_landmarks.py                 # Wikidata SPARQL → JSON
  make_landmarks_db.py               # JSON → SQLite table + R-tree index
  landmarks_10.json, landmarks_preview.json   # Checked-in inputs
  landmarks.sqlite                   # Byte-identical copy of the shipped DB
SETUP.md                             # Project wiring, Study build, regenerating landmarks.sqlite
```

---

## Architecture

### Two app identities

The same `FogOfWalk` target builds both apps. Behavior switches at **runtime** on bundle ID
(`Bundle.main.bundleIdentifier == LocationStudyDiagnostics.studyBundleID`). There is no
compile-time flag, so Study code is compiled into the normal binary too.

| | Normal Fog | Study app |
|---|---|---|
| Bundle ID | `com.jeremybraff.fogofwalk` (checked-in) | `com.jeremybraff.fogofwalk.study` (build override) |
| Display / product name | `Fog-Of-Walk` / `Fog-Of-Walk` | `Fog Walk Study` / `Fog-Walk-Study` |
| Tracking source | Legacy `CLLocationManager` only | Persisted choice: Legacy, or `liveUpdates` ("Automatic pause/resume") |
| Who records cells | Map `Coordinator` (closure set in `updateUIView`) | `ExplorationRecorder` closure set in `FogOfWalkApp.init`, before any view exists |
| Extra UI | none | Settings → Location Study: source picker, tracking-OFF control, diagnostic capture/export, motion query |

Rules:
- Normal Fog keeps legacy tracking whatever is persisted. `LocationService` ignores the
  `locationStudy.*` defaults unless `isStudyApp`. Gate every Study behavior on `isStudyApp`
  and test both identities (inject `isStudyApp:` in tests).
- Diagnostics observe; they never filter exploration. `StudySampleValidator` decisions are
  shadow-only. The live source has its own freshness filter (below).
- Diagnostic logs and motion files hold precise locations. They stay in the Study app's
  container (excluded from backup, 7-day retention, 16 MiB cap). Never commit them or raw traces.
- Lifecycle and next actions for this work live in the workspace initiative
  `fog-adaptive-location-tracking`. Physical installs and phone trials are owner-coordinated;
  follow `docs/evidence/automatic-pause-resume-prototype.md`, and never uninstall the Study app
  (that deletes its data).

Study builds use command-line build-setting overrides (normal builds also override
`CURRENT_PROJECT_VERSION`; the checked-in value is `1`):

```text
PRODUCT_BUNDLE_IDENTIFIER=com.jeremybraff.fogofwalk.study
FOG_APP_DISPLAY_NAME="Fog Walk Study"
PRODUCT_NAME=Fog-Walk-Study
CURRENT_PROJECT_VERSION=<next Study build number>
```

### Data flow

```
CLLocationManager (legacy)                       CLLocationUpdate.liveUpdates(.fitness) (Study only)
  delegate: nonisolated → Task @MainActor,          LiveStationaryLocationSource → receiveLiveEvent
  epoch-checked, forwards locations.last            (valid, ≤15 s old, after session start, in order)
                 └───────────────► LocationService.onLocationUpdate ◄──────────────┘
                                          │
          normal: Coordinator.handle(location:)          Study: closure from FogOfWalkApp.init
                                          ▼
                           ExplorationRecorder.record(_:)
                             store.configure()                       (no-op after first call)
                             store.refreshForDayChangeIfNeeded()     (resets "today" at midnight)
                             store.addCell(GridMath.cellID(for:))    (Core Data save + caches; onNewCell → geocoder)
                             landmarks.checkDiscovery(newCell:)      (only when the cell is new)
                             diagnostics.recordDownstream(...)       (no-op unless a Study capture runs)
                                          ▼  returns true on new cell or day rollover
                           Coordinator.invalidateFogTiles() → fresh CellSnapshot → renderer.setNeedsDisplay()
```

Other flows:
- **Launch** (`FogOfWalkApp` `.task`): `requestPermissionAndStart()`, wire `store.onNewCell` →
  `LocalityGeocoder.enqueue`, backfill untagged cells, then `landmarkStore.sweepAllUndiscovered`
  (self-heals discoveries lost to a rolled-back save).
- **Foreground** (`scenePhase == .active`): `restartIfAuthorized()` and a day-rollover check.
  `ContentView` also listens for `.NSCalendarDayChanged` and `significantTimeChangeNotification`.
- **Landmark ingest:** `mapView(_:regionDidChangeAnimated:)` → `LandmarkSearchService.searchIfNeeded`
  (span ≤ 1.0°, 30 s / 500 m rate limit) → `BundledLandmarkSource` R-tree query (LIMIT 500) →
  `LandmarkStore.addLandmarks(_:visitedCells:)`, which immediately sweeps the new rows against
  already-walked cells.

### Environment objects

Six `@MainActor @Observable` objects are created in `FogOfWalkApp.init`, injected at the
`WindowGroup` with `.environment(...)`, and read with `@Environment(T.self)`:

| Type | Role |
|------|------|
| `ExplorationStore` | Source of truth for visited cells, today/total counts, highlight cache; wraps Core Data |
| `GridSettings` | `highlightToday` (gold tint on today's cells) and `showLandmarks` (pin display) |
| `LocationService` | Permission, tracking, Study source/OFF control; exposes `onLocationUpdate` |
| `LocalityGeocoder` | Background reverse-geocoding queue for new and untagged cells |
| `LandmarkStore` | Landmark rows and discovery state; owns the Wikidata migration |
| `LandmarkSearchService` | Rate-limited ingest from the bundled landmark DB |

`LocationStudyDiagnostics.shared` is a singleton, not an environment object.
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the app target makes every app type implicitly
`@MainActor` unless marked otherwise. The explicit annotations on these six are redundant
but harmless.

### Location tracking

Legacy policy (`LocationService.init`), used by normal Fog and by Study's Legacy arm:
`kCLLocationAccuracyNearestTenMeters`, `distanceFilter = 15` m, `activityType = .fitness`,
`pausesLocationUpdatesAutomatically = false`, background location indicator on. Auto-pause
is off on purpose: with `.fitness`, iOS paused delivery while stationary and did not resume in
the background until the app was reopened. With Always permission it runs standard updates
plus significant-change monitoring as a relaunch safety net. While Using starts foreground-only
updates and requests Always. Only the last sample of each delegate batch is forwarded, and
paths between sparse samples are never inferred.

Study `liveUpdates` source: `LiveStationaryLocationSource` keeps the async sequence open while
the framework reports `stationary` (breaking the loop would disable automatic resume) and holds a
`CLBackgroundActivitySession` plus `CLServiceSession(authorization: .always)`. Selecting it stops
the legacy manager's location services and MapKit user location (no blue dot or follow).
The manager remains the authorization delegate. `callbackEpoch` (an `OSAllocatedUnfairLock`)
is bumped on every source/OFF switch so late callbacks from the previous arm are dropped.
Preserve it when editing delegate code.

The HUD's **Paused** label is effectively Study-only. Legacy never pauses. The label appears
when Study consumers are stopped or the live source reports stationary.

### Coordinate system

`GridMath` divides the globe into a uniform grid in **degrees**, aligned to `(0,0)` at
(0°, 0°): step = `kCellSizeMeters / 111_111` degrees on both axes. `CellID(x: Int32, y: Int32)`
is the address, and conversion is pure arithmetic. Cells are therefore narrower east-west at
higher latitudes. `GridMath.cellBox(around:radiusMeters:)` compensates with `cos(latitude)` and
must stay a strict superset of the radius disc (read its doc comment before editing).
Cell size is fixed at 50 m. The `cellSizeMeters` column remains for old rows, and every fetch
filters on `cellSizeMeters == kCellSizeMeters`.

### Fog rendering

`FogOverlay` is a world-spanning `MKOverlay` added `.aboveLabels`. `FogOverlayRenderer.draw`
runs on MapKit's background tile threads and reads its `CellSnapshot` under an `NSLock`. The
pure drawing lives in the `FogRenderer` struct so it can be unit-tested without MapKit:
1. Fill the tile with fog (`systemGray`, alpha 0.92).
2. Punch a soft radial-gradient hole per visited cell using `.destinationOut`. The hole is
   solid to 70% of its radius, then fades to clear, and is drawn without
   `.drawsAfterEndLocation`, so its cost is bounded by the hole.
3. Draw a gold tint over today's cells when `highlightToday` is on.

Hole radius is 0.9 × the projected cell size, floored at `kMinCellScreenPoints` (3 pt) ÷
`zoomScale`, so **visited cells stay visible at every zoom level, including world zoom**. The
renderer applies no cell-count cap. The `radius > 0.5` guards are inert because of that floor.

`Coordinator.invalidateFogTiles()` is the only way to push new state to the renderer.
`updateUIView` calls it when the cached cell count or `recentCellsGeneration` changes, and
`ContentView` passes `highlightGeneration` so SwiftUI re-runs `updateUIView` on highlight
rebuilds. Fog pans and zooms natively. `LandmarkOverlayView` is a plain `UIView` sibling, so
`mapViewDidChangeVisibleRegion(_:)` applies a manual `CATransform3D` during gestures (math in
the static, tested `Coordinator.gestureTransform`) and `regionDidChangeAnimated` resets it.

### Landmarks

- Data: `landmarks.sqlite` (14,943 Wikidata items in 10 categories). Rows are copied into Core Data only when
  the map shows a region (see Landmark ingest). An area walked with the app in the background and
  never viewed on the map has no landmark rows yet. Its landmarks are discovered when the area is
  first viewed, and `firstDiscovered` records that later time.
- Discovery hot path: `checkDiscovery(newCell:)` looks up undiscovered landmarks in 32×32-cell
  buckets (`LandmarkStore.bucket(for:)`, `>> 5`) within `maxDiscoveryRadius`, then does an
  equirectangular distance check. Its cost must not grow with the visited set. Tests assert this
  through `lastDiscoveryProbeCount`.
- Categories: a new category needs entries in `LandmarkStore.categoryRadius`,
  `LandmarkOverlayView.categoryIcon`, and `LandmarkDetailView.categoryLabel`.
- Coupled limits: `GridMath.maxIngestSpanDegrees` (1.0°) ↔ `BundledLandmarkSource` `LIMIT 500`
  (re-measure density before raising the span). `LandmarkStore.maxRenderedPins` = 300.
- `showLandmarks` is **off by default**. Discovery always runs, and only pin display is gated
  (`Coordinator.refreshLandmarks`). Check the toggle before suspecting a discovery bug.
- If `landmarks.sqlite` is missing or unreadable, `LandmarkSearchService.makeBundled()` silently
  falls back to `EmptyLandmarkSource`.

### Backup export/import

`BackupService` (`Models/BackupService.swift`) is a stateless `enum`. It encodes and decodes a
versioned JSON `BackupPayload` holding `visitedCells` plus discovered `landmarks`
(`identifier` + `firstDiscovered` only, since metadata is re-derived from the bundled DB on
import). `BackupPayload.currentSchemaVersion` is `2`. Files with any `schemaVersion <= current`
decode (new fields are optional and default to `nil`, as `state`/`country` did in v2). Only
files from a newer version are rejected. A sample `visitedCells` entry:

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

Import merges and never overwrites. `ExplorationStore.addCells(_:)` inserts missing cells and
keeps the earlier `firstVisited` date. `LandmarkStore.restoreDiscovered(_:)` marks known
identifiers discovered, keeps the earlier date, and skips unknown identifiers. The two merges
are not jointly atomic. `SettingsView` exports through `ShareLink` and imports through
`.fileImporter`. Backup is manual only: there is no CloudKit or automatic sync.

### Discovery Stats

`DiscoveryStatsModel.refresh(context:)` makes one pass over all 50 m `VisitedCell`s and
produces:
- **Today**: since local midnight (the property is named `last24HourCount`, but it is not a
  rolling 24 hours).
- A 7-day chart, current and longest streaks, and estimated distance (cell count × 50 m).
- Locality lists per period.
- All-time **States**, limited to the 50 US states and normalized through `USState`.
- All-time **Countries**.

Tapping a locality row navigates the map through `MapNavigationTarget`. There is **no
"% of city explored" feature**: it was removed along with `ExplorationStore.totalCellCount`
in commit 938ef32, so ignore older docs that describe it.

---

## Key constraints and gotchas

- **`@MainActor` everywhere.** `CLLocationManagerDelegate` methods are `nonisolated` and hop
  back with `Task { @MainActor in ... }`, re-checking the callback epoch.
- **Callback wiring.** The normal app reassigns `locationService.onLocationUpdate` in every
  `updateUIView` so it always captures the live coordinator. The Study app sets it once in
  `FogOfWalkApp.init`, and `updateUIView` must not overwrite it (the `!isStudyApp` guard).
- **Core Data context:** always `container.viewContext`, with
  `automaticallyMergesChangesFromParent = true`. `NSBatchDeleteRequest` results are merged back
  manually, and in-memory stores use a manual delete loop (batch delete raises `NSException`).
- **Core Data load failure.** `ExplorationStore.init` copies the main `.sqlite` file to `.bak`,
  deletes it, and retries. `loadError` is then set, but no UI reads it. A model change that is not
  a lightweight (inferable) migration takes this path and the user silently starts empty.
- **`@Observable` / iOS 17 APIs** are required. Don't back-port to `ObservableObject`.
- **XCTest only; no SwiftUI previews.** There are no `import Testing`, `@Test`, `#expect`, or
  `#Preview` uses. Test rendering in the simulator.
- **No haptics.** This is deliberate: tracking runs for hours in the background, and a buzz per
  50 m cell is noise. Don't reintroduce them.
- **Concurrency settings:** `SWIFT_VERSION = 5.0` (isolation violations are warnings),
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (app target only), and
  `SWIFT_APPROACHABLE_CONCURRENCY = YES`. Under approachable concurrency a plain
  `nonisolated async func` called from the main actor still runs on the caller's actor;
  reaching the global executor needs `@concurrent` or `Task.detached`. The fog render path
  (`FogOverlayRenderer.draw` → `FogRenderer`/`CellSnapshot`/`CellID`/`GridMath`) runs off-main
  even though those types are inferred `@MainActor`. That works only because Swift 5 mode
  doesn't enforce isolation. Mark the path `nonisolated` before any Swift 6 migration.
- **Known compiler warnings (don't add more):** the app target has three:
  1. `CellID`'s main-actor `Hashable` conformance is used in `CellSnapshot.init`.
  2. `LandmarkStore.maxRenderedPins` is used as a default argument.
  3. `EmptyLandmarkSource()` is used as a default argument in `LandmarkSearchService.init`.

  The test target has about 140 Swift 6-mode concurrency warnings (captured `var`s in
  `MainActor.run` closures, isolated conformances). They are pre-existing.
- **Product rename at the build-settings level.** `PRODUCT_NAME = "Fog-Of-Walk"`,
  `PRODUCT_MODULE_NAME = FogOfWalk`, and `TEST_HOST` points at `Fog-Of-Walk.app`, so the bundle is
  `Fog-Of-Walk.app` while `@testable import FogOfWalk` still resolves. If a rename breaks this
  pairing, `xcodebuild test` fails with a scheme-membership message (see Build & test).
- **Code with no production caller:** `GridMath.cells(in:)`/`cellBounds(in:)` (the 10,000-cell
  cap, used only by tests), `ExplorationStore.deleteAllCells`/`visitedCellCount(in:)`, and
  `Coordinator.replaceFogOverlay`. The running app cannot delete location history. That is a
  known gap, and backup import only merges.
- **Silent states:** `LocationService.isPermissionDenied` has no UI consumer, so a user who
  denies location sees no prompt and the fog never lifts.
- **Geocoding:** live geocoding needs `store.onNewCell`, which is wired in the launch `.task`.
  The launch backfill groups untagged cells into 0.5° (~55 km) buckets and writes one
  placemark's names into every nil field in the bucket. `CLGeocoder` and `MKPlacemark` are
  deprecated as of iOS 26, which is not yet a warning at the 18.6 floor.
- **Shared Info.plist:** both identities ship the same plist, including the Study-worded
  `NSMotionUsageDescription`.

---

## Testing conventions

- **XCTest only.**
- **`@MainActor @Observable` store/service tests are `async`** and wrap every interaction in
  `await MainActor.run { }`. This avoids an iOS 26+ simulator crash
  (`swift_task_deinitOnExecutorImpl` / TaskLocal heap corruption) when such an object is
  deallocated outside a Task. See the headers of `LandmarkStoreTests.swift` and
  `ExplorationStoreTests.swift`.
- **Renderer and pin-view tests are different:** `FogOverlayRendererTests` and
  `LandmarkOverlayViewTests` mark the class `@MainActor` and use synchronous methods. Follow the
  pattern of the file you're extending.
- **`makeInMemoryContainer()` is copy-pasted, not shared.** Copies live in
  `ExplorationStoreTests`, `LandmarkStoreTests`, `DiscoveryStatsModelTests`,
  `LocalityGeocoderTests`, `BackupServiceTests`, and `StationaryLocationSourceTests`. Use the
  file's own copy, and don't add a shared base class as a drive-by refactor.
- **LocationService tests** inject `MockLocationManager` (`LocationServiceTests.swift`),
  `isStudyApp:`, a fresh `UserDefaults(suiteName:)` (never `.standard` for `locationStudy.*`
  keys), a fake `LocationDiagnosticRecording`, and `makeStationarySource:`. `LiveTestHarness` in
  `StationaryLocationSourceTests.swift` is the template. Simulated events cannot prove physical
  background wake-up.
- **Async timing:** `LandmarkSearchServiceTests` uses a sleep-and-poll loop (the debounce doesn't
  fit expectations well), while `LocalityGeocoderTests` uses `XCTestExpectation`.
- **Rendering helpers:** `renderFog(...)` and `pixelColor(at:in:)` (`FogOverlayRendererTests`) for
  fog, `installCoordinateMock()` (`LandmarkOverlayViewTests`) for pins.
- **Hosted tests:** unit tests run inside `Fog-Of-Walk.app`, so `FogOfWalkApp.init` (real Core Data
  store, real `CLLocationManager`) runs first. A few tests touch `UserDefaults.standard`: the
  Wikidata migration flag and `showLandmarks`.

## Known platform quirks

- **iOS 26+ simulator, `@Observable` dealloc crash:** see the async test pattern above.
- **`NSBatchDeleteRequest` on in-memory stores** raises `NSException` instead of returning an
  error. Production code checks `NSInMemoryStoreType` and falls back to `context.delete()`.

---

## Build & test

```bash
# Build
xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build

# Full suite (unit + UI launch test)
xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test

# Unit tests only (faster)
xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:FogOfWalkTests test
```

If that simulator doesn't exist, pick one from `xcrun simctl list devices available | grep iPhone`.
The latest recorded full-suite result is in `docs/evidence/automatic-pause-resume-prototype.md`.

- **"CoreSimulator is out of date" / "Unable to load simulator devices":** Xcode was updated and
  its first-launch components aren't installed. Fixing this takes admin rights
  (`sudo xcodebuild -runFirstLaunch`, or open Xcode once), so the owner has to do it. Report it.
  Meanwhile you can compile-check with
  `-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`, but that doesn't run
  the tests.
- **No shared scheme.** `FogOfWalk.xcodeproj/xcshareddata/` doesn't exist, so `-scheme FogOfWalk`
  resolves through Xcode's autocreated user scheme. That fails on a fresh clone until Xcode
  generates it, and there is no CI. If `xcodebuild test` fails with "FogOfWalkTests isn't a
  member of the specified test plan or scheme" and no source changed, suspect the autocreated
  scheme, not the code.
- **Simulating movement:** in the running simulator, use **Features → Location → City Bicycle
  Ride**.

---

## Adding features — checklist

1. **New persistent data?** Add a new model version to `FogOfWalk.xcdatamodeld` that lightweight
   migration can infer (see Core Data load failure), update the `+CoreData.swift` subclass and
   store, and carry user data through `BackupPayload`: add optional fields and bump
   `currentSchemaVersion`.
2. **New setting?** Add a `GridSettings` property with a `UserDefaults` `didSet`, following
   `highlightToday`/`showLandmarks`.
3. **New view?** Read environment objects with `@Environment(ExplorationStore.self)` etc., and keep
   views `@MainActor`-safe.
4. **New cell math?** Put it in `GridMath` as static functions with no stored state.
5. **Study-only behavior?** Gate it on `isStudyApp`, keep the normal default unchanged, test both
   identities, and never let diagnostics filter exploration.
6. **New landmark category?** Update the three category maps listed under Landmarks.
7. **Every feature or bug fix needs tests.** Bug fixes need a regression test that would have
   caught the bug. Follow the patterns above.
8. **Run the full suite** (`xcodebuild ... test`), not just the new tests. Build and tests must
   pass before the task is done.
9. **Keep this guide current.** If you change behavior described here or in `docs/SYSTEM.md`,
   update the docs in the same change.
