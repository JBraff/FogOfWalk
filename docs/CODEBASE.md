# Fog of Walk codebase guide

Implementation reference for contributors and coding agents: where code lives,
how data moves through it, and the details behind the rules in
[`AGENTS.md`](../AGENTS.md). [System architecture](SYSTEM.md) is the shorter,
enduring overview. Runtime code and tests remain authoritative. Update this guide
in the same change when behavior described here changes.

## Project layout

```
FogOfWalk/
  FogOfWalk.xcodeproj                # Synchronized folders; no shared scheme (see AGENTS.md Build & test)
  FogOfWalk/
    FogOfWalkApp.swift               # @main: creates the six environment objects; wires recording + re-arms tracking
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
      BackupService.swift            # Versioned JSON export/import: merge or atomic replace
    Services/
      LocationService.swift          # CLLocationManager wrapper: legacy tracking + Study source switching
      ExplorationRecorder.swift      # The recording path (location → cell → landmark ingest/discovery); connect()
      StationaryLocationSource.swift # Study-only CLLocationUpdate.liveUpdates source; StudyLocationSource enum
      LocationStudyDiagnostics.swift # Study-only opt-in JSONL capture; shadow sample validator
      StudyMotionReference.swift     # Study-only post-run Core Motion/pedometer history query
      BundledLandmarkSource.swift    # SQLite R-tree query over landmarks.sqlite
      LandmarkSearchService.swift    # Rate-limited landmark ingest as the map region changes
    Views/
      MapContainerView.swift         # UIViewRepresentable: MKMapView + FogOverlay + native landmark annotations +
                                     # top-right recenter and compass buttons; Coordinator
      HeadingMapView.swift           # Foreground compass updates only the blue dot's direction pointer
      FogOverlay.swift               # FogOverlay (MKOverlay), FogRenderer (pure CG), FogOverlayRenderer
      LandmarkAnnotationView.swift   # Lightweight annotations + reusable fixed-size discovered pins / inert "?" hints
      LandmarkInteractionFixture.swift # Debug-only in-memory map for XCUITest gestures
      LandmarkDetailView.swift       # Sheet for a tapped discovered pin
      StatsView.swift                # Bottom HUD: "N new today" (toggles highlight), landmark count, Paused, buttons
      DiscoveryStatsView.swift       # Stats sheet (Swift Charts)
      SettingsView.swift             # Backup export/import; Study-only "Location Study" section
      LocationPermissionBanner.swift # Banner for denied location or While Using → Always upgrade
  FogOfWalkTests/                    # XCTest unit tests: roughly one <Type>Tests.swift per production type, plus
                                     # FogOfWalkTests.swift (GridMath) and StudyTrackingControlTests.swift (Study OFF)
  FogOfWalkUITests/                  # Native landmark gesture regression + UI launch screenshot
docs/                                # Durable product docs; start at docs/README.md
scripts/
  fetch_landmarks.py                 # Wikidata SPARQL → JSON
  make_landmarks_db.py               # JSON → SQLite table + R-tree index
  landmarks_10.json, landmarks_preview.json   # Checked-in inputs
  landmarks.sqlite                   # Byte-identical copy of the shipped DB
SETUP.md                             # Project wiring, Study build, regenerating landmarks.sqlite
```

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
| Extra UI | none | Settings → Location Study: source picker, tracking-OFF control, diagnostic capture/export, motion query |

The rules for Study behavior are in `AGENTS.md`; the Study build-setting
overrides are in [`SETUP.md`](../SETUP.md) section 3.

### Data flow

```
CLLocationManager (legacy)                       CLLocationUpdate.liveUpdates(.fitness) (Study only)
  delegate: nonisolated → Task @MainActor,          LiveStationaryLocationSource → receiveLiveEvent
  epoch-checked, forwards locations.last            (valid, ≤15 s old, after session start, in order)
                 └───────────────► LocationService.onLocationUpdate ◄──────────────┘
                                          │
                 closure installed by ExplorationRecorder.connect in FogOfWalkApp.init (both identities)
                                          ▼
                           ExplorationRecorder.record(_:)
                             store.configure()                       (no-op after first call)
                             store.refreshForDayChangeIfNeeded()     (resets "today" at midnight)
                             store.addCell(GridMath.cellID(for:))    (Core Data save + caches; onNewCell → geocoder)
                             only when the cell is new:
                               landmarks.ingestLandmarks(near:...)   (bundled DB, once per bucket per launch)
                               landmarks.checkDiscovery(newCell:)
                             diagnostics.recordDownstream(...)       (no-op unless a Study capture runs)
                                          ▼
                           ContentView re-renders (visitedCellCount / highlightGeneration change)
                           → MapContainerView.updateUIView → Coordinator.invalidateFogTiles()
                           → fresh CellSnapshot → renderer.setNeedsDisplay()
```

Other flows:
- **Launch, `FogOfWalkApp.init`** (runs even for a scene-less background relaunch):
  `ExplorationRecorder.connect` wires recording and `store.onNewCell` → `LocalityGeocoder.enqueue`,
  then `restartIfAuthorized()` re-arms already-authorized tracking. The map is not involved.
- **Launch, `.task`** (needs a scene): `requestPermissionAndStart()`, backfill untagged cells,
  then `landmarkStore.sweepAllUndiscovered` (self-heals discoveries lost to a rolled-back save).
- **Foreground** (`scenePhase == .active`): `restartIfAuthorized()` and a day-rollover check.
  `ContentView` also listens for `.NSCalendarDayChanged` and `significantTimeChangeNotification`.
- **Landmark ingest (map):** `mapView(_:regionDidChangeAnimated:)` → `LandmarkSearchService.searchIfNeeded`
  (span ≤ 1.0°, 30 s / 500 m rate limit) → `BundledLandmarkSource` R-tree query (LIMIT 500) →
  `LandmarkStore.addLandmarks(_:visitedCells:)`, which immediately sweeps the new rows against
  already-walked cells. Walking also ingests around each new cell (see Landmarks).

### Environment objects

Six `@MainActor @Observable` objects are created in `AppServices.init` during
`FogOfWalkApp.init` (before any scene), injected at the
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
`updateUIView` calls it when the cached cell count or `recentCellsGeneration` changes.
Recording happens outside the map, so `ContentView` passes `visitedCellCount` and
`highlightGeneration` as inputs to guarantee SwiftUI re-runs `updateUIView`. Keep those
inputs if you restructure the view. The recenter button requests only `.follow`, including repeated taps, so turning the phone
never rotates the map. `HeadingMapView` uses a separate heading-only `CLLocationManager`
to rotate a pointer around MapKit's native blue dot. It starts only with location permission,
heading hardware, a visible window, an active scene and `usesMapLocation` enabled; backgrounding,
removing the map or Study OFF/live-source selection stops it and clears the pointer. It never
requests locations or feeds recording. Manual map rotation is still supported; the pointer
compensates for the camera heading and the adaptive compass resets north. The recenter
button shows an outline arrow when not following and a filled arrow when following.
Scene geometry observation handles orientation changes even without a layout pass.
Heading callbacks carry a session ID across the actor hop: the first cached reading in
a new session is accepted, and callbacks queued in a previous session are rejected.

Fog and landmark annotations pan and zoom natively. `LandmarkAnnotationView` keeps each
icon and label at a fixed screen size and orientation. There is no sibling pin surface or
manual gesture transform. At settle, `Coordinator.refreshLandmarks` diffs lightweight
annotations by Wikidata ID, reusing retained annotations and updating visible discovery
styling in place. A `LandmarkMapView` child observes `LandmarkStore.renderGeneration` and
the display setting and passes them as explicit representable inputs. This includes
count-neutral Core Data edits without making the root screen observe every landmark change.
Generation advances on landmark context changes and cache reloads.

### Landmarks

- Data: `landmarks.sqlite` (14,943 Wikidata items in 10 categories). Rows are copied into Core
  Data when the map shows a region, and by `LandmarkStore.ingestLandmarks(near:from:visitedCells:)`
  around each newly walked cell. The walk-time path caches each successfully ingested
  32×32-cell bucket per launch and retries failed inserts on later new cells, covering
  `maxDiscoveryRadius`, so landmarks are discovered during the walk even with no map on screen.
- Discovery hot path: `checkDiscovery(newCell:)` looks up undiscovered landmarks in 32×32-cell
  buckets (`LandmarkStore.bucket(for:)`, `>> 5`) within `maxDiscoveryRadius`, then does an
  equirectangular distance check. Its cost must not grow with the visited set. Tests assert this
  through `lastDiscoveryProbeCount`.
- Categories: a new category needs entries in `LandmarkStore.categoryRadius`,
  `LandmarkAnnotationView.categoryIcon`, and `LandmarkDetailView.categoryLabel`.
- Rendering selects the existing `landmarks(in:)` visible result first, then fills spare
  capacity from a region with twice the visible span. Buffer-only discoveries precede
  buffer-only hints when capacity is tight. The visible >1-degree gate still hides pins;
  padding reads only already-ingested rows and never expands ingest. The installed set,
  including padding, is capped at 300. One pass scans the stored rows into bounded
  candidate arrays. Views use required display priority without clustering. Hints are
  disabled, ignore touches and sit below discovered pins. Discovered pins preserve the
  old 30-point hit radius centred on the drawn icon; wide name labels pass touches
  outside that circle. The user location view sits above discovered pins, including
  during selection. Selections open details and immediately deselect so repeated taps
  work. The delegate supplies resolved map traits before the first bitmap draw;
  unresolved traits defer drawing until attachment supplies the appearance; an attached
  view falls back to its own appearance. Attachment also redraws a pin that changed while
  detached. Deferred views stay disabled and outside accessibility until drawn; reuse
  clears old geometry. Interaction state is reapplied even when the bitmap is unchanged.
  A real-MapKit regression anchors a deferred view the production delegate configured,
  fresh or hand-recycled; it does not exercise MapKit's own reuse queue.
- Coupled limits: `GridMath.maxIngestSpanDegrees` (1.0°) ↔ `BundledLandmarkSource` `LIMIT 500`
  (re-measure density before raising the span). `LandmarkStore.maxRenderedPins` = 300.
- `showLandmarks` is **off by default**. Discovery always runs, and only pin display is gated
  (`Coordinator.refreshLandmarks`). Check the toggle before suspecting a discovery bug.
- If `landmarks.sqlite` is missing or unreadable, `LandmarkSearchService.bundledSource()` logs one
  line and falls back to `EmptyLandmarkSource`; landmarks then silently do nothing.

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

Settings decodes the chosen file before offering **Merge** or **Replace**. Merge retains
its existing behavior: `ExplorationStore.addCells(_:)` inserts missing cells and keeps the
earlier `firstVisited` date without replacing existing labels. A successful merge rebuilds
the active highlight using its stored cutoff, including date-only merges.
`LandmarkStore.restoreDiscovered(_:)` marks known identifiers discovered, keeps the earlier
date, and skips unknown identifiers. These two merge saves are not jointly atomic.

Replace requires a second destructive confirmation explaining that existing map squares,
labels and discovered landmarks will be replaced. `BackupService.replace` deletes the old
cells, inserts the file's cells with their exact dates, sizes and labels, and resets landmark
discovery to exactly the file's identifiers and dates. Undiscovered reference metadata is
retained. Missing landmark metadata is loaded by identifier from the bundled database; an
unresolvable identifier or duplicate record rejects the replacement before any mutation.
Empty backups intentionally clear all exploration and discovery history.

Both stores must share the same clean `viewContext`. Replacement uses ordinary managed-object
deletes and one save for both entities, with rollback on failure. It never uses batch deletes
or invokes new-cell recording/geocoding callbacks. Cache reloads happen after success: cell
and today counts, the active highlight (advancing its generation even with highlighting off
or unchanged cell count), landmark counts, and the undiscovered spatial index. The map
observes those generations; Discovery Stats queries the updated context when opened.
Decode or save failures leave history unchanged, and cancellation never invokes an import.

`SettingsView` exports through `ShareLink` and imports through `.fileImporter`. Backup is
manual only: there is no CloudKit or automatic sync.

### Discovery Stats

`DiscoveryStatsModel.refresh(context:)` makes one pass over all 50 m `VisitedCell`s and
produces:
- **Today**: since local midnight (the property is named `last24HourCount`, but it is not a
  rolling 24 hours).
- A 7-day chart, current and longest streaks, and estimated distance (cell count × 50 m).
- Locality lists per period, with longitude centers and spans unwrapped across the date line.
- First walk uses the earliest non-nil visit date; incomplete rows still count in totals.
- All-time **States**, limited to the 50 US states and normalized through `USState`.
- All-time **Countries**, excluding nil, blank, and "Unknown" labels. Unresolved cells still
  contribute to exploration totals.

Tapping a locality row navigates the map through `MapNavigationTarget`. There is **no
"% of city explored" feature**: it was removed along with `ExplorationStore.totalCellCount`
in commit 938ef32, so ignore older docs that describe it.

## Implementation details

- **Core Data load failure.** Only an unreadable store
  (`ExplorationStore.isUnreadableStoreError`: corrupt or not a database, or a model change
  migration can't handle) is reset. `ExplorationStore.init` then copies the store and its
  `-wal`/`-shm` sidecars to `<name>.corrupt-<timestamp>` (never overwriting an older copy),
  destroys the store, retries, and sets `recoveryNotice`. Any other load error (I/O,
  permissions, file protection, disk full) may be transient: the store is left untouched.
  Generic migration errors alone never authorize a reset; underlying and detailed causes
  are classified first, and unknown or mixed failures preserve storage.
  That case, a failed backup and a failed reset all leave `loadError` set, which disables
  writes; recovery never falls back to deleting originals, and `ContentView` shows a storage
  error instead of claiming history was reset. The copies are recoverable only by hand. A model
  change that lightweight migration can't infer takes the reset path, so the user's history is
  reset.
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
  pairing, `xcodebuild test` fails with a scheme-membership message (see Build & test in `AGENTS.md`).
- **Code with no production caller:** `GridMath.cells(in:)`/`cellBounds(in:)` (the 10,000-cell
  cap, used only by tests), `ExplorationStore.deleteAllCells`/`visitedCellCount(in:)`, and
  `Coordinator.replaceFogOverlay`. The running app has no individual history editor. That is a
  known gap for individual edits; confirmed backup replacement can replace the whole history.
- **Permission UI:** `LocationService.permissionPrompt` (`.denied` or `.upgradeToAlways`) drives
  `LocationPermissionBanner`. Dismissal is per prompt, so a later different problem still shows.
- **Geocoding queue:** at most `LocalityGeocoder.maxQueueSize` (200) clusters. Newly walked
  cells go ahead of launch backfill and, when the queue is full, displace the newest backfill
  cluster (its cells stay untagged for a later launch).
- **Geocoding:** the launch backfill groups untagged cells into
  `LocalityGeocoder.backfillClusterDegrees` (0.01°, ~1.1 km) clusters and writes one placemark's
  names into every nil field in the cluster. Missing countries remain retryable on later
  launches; legacy empty/"Unknown" countries are also retried and replaced only with a
  known country. Known countries are preserved. Missing state/locality still use the
  "Unknown" sentinel. Cells mislabelled by the old 0.5° clustering are not
  corrected. `CLGeocoder` and `MKPlacemark` are deprecated as of iOS 26, which is not yet a
  warning at the 18.6 floor.
- **Shared Info.plist:** both identities ship the same plist, including the Study-worded
  `NSMotionUsageDescription`.

## Test infrastructure

- **Rendering helpers:** `renderFog(...)` lives in `FogOverlayRendererTests`;
  `RenderingTestHelpers` shares the RGBA `pixelBuffer(for:)` and top-left-coordinate
  `pixelColor(at:in:)` accessors between fog and pin tests. `LandmarkMapGeometryTests` checks real MapKit pin placement; `LandmarkInteractionTests`
  uses the Debug-only `-landmark-interaction-fixture` launch argument for real gestures on
  an in-memory map. The launch flag skips production service construction, so the fixture
  never opens the normal store or starts tracking. Fixture settings and migration flags
  are memory-only (`defaults: nil`). The fixture is excluded from Release builds.
  `LandmarkMapObservationTests` hosts SwiftUI to verify scoped, count-neutral updates;
  `LandmarkFixtureIsolationTests` covers the launch gate and unchanged standard defaults.
  `LandmarkTestSupport` holds the deadline-bounded `waitForLandmarkUI` poll and the shared
  `anchorError(of:for:in:)` placement check. `makeLandmarkCoordinator()` is memory-only
  unless a test passes `defaults: .standard`.
- **Hosted tests:** unit tests run inside `Fog-Of-Walk.app`, so `FogOfWalkApp.init` (real Core Data
  store, real `CLLocationManager`) runs first. A few tests touch `UserDefaults.standard`: the
  Wikidata migration flag and `showLandmarks`.
- **iOS 26+ simulator, `@Observable` dealloc crash:** see the async test pattern in `AGENTS.md`.
- **`NSBatchDeleteRequest` on in-memory stores** raises `NSException` instead of returning an
  error. Production code checks `NSInMemoryStoreType` and falls back to `context.delete()`.
