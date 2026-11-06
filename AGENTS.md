# Fog of Walk — Agent Guide

iOS app that overlays a "fog of war" on Apple Maps and lifts it as the user physically walks through the world. Swift (Swift 5 language mode), SwiftUI + MapKit/UIKit, Core Data, XCTest. App target deploys to iOS 18.6; test targets to 26.2. Last verified with Xcode 27.

<!-- workspace-instructions:v2 -->
## Workspace instructions

At task start, locate the `agent-workspace` checkout using `AGENT_WORKSPACE_PATH`
(the checkout itself), then `WORKSPACE_ROOT/agent-workspace`, then the direct
sibling of this product's main Git checkout. For a managed worktree, obtain the
main checkout from `git worktree list --porcelain`; do not assume the worktree's
sibling is the workspace. Do not scan parent directories. Verify the candidate:

```sh
python3 <agent-workspace>/scripts/product-instructions.py resolve --project fog-of-walk --checkout <product-root>
```

If resolution fails, stop and report the missing or mismatched workspace. Read
the verified workspace `AGENTS.md` before product work, then only the relevant
initiative, runbook, and product documentation. Workspace rules own shared
delivery and initiative tracking; this product's instructions own its behavior.

Initiatives are GitHub issues in the workspace's Work Project. Read and update
them with `python3 <agent-workspace>/scripts/work-tracker.py`, as the workspace's
`knowledge/runbooks/work-tracking.md` describes; it needs authenticated GitHub
access, not write access to the workspace checkout. If GitHub is unavailable,
report the exact pending tracking update and continue independent authorized
product work. Reading workspace rules does not grant write access to that
checkout: request it when an authorized workspace edit needs it. Keep this
repository's patch and commit separate from the workspace's.
<!-- /workspace-instructions -->

For Fog-only work, also read the workspace `registry.yaml`. Durable product
context starts at `docs/README.md` and `docs/SYSTEM.md`.

---

## Orientation

- **What matters most:** a real location sample becomes a 50 m grid cell, the cell is
  persisted, and the fog over it clears. Everything else (landmarks, stats, backup) hangs
  off that path.
- **Codebase guide:** `docs/CODEBASE.md` holds the project layout, data flow, environment
  objects, location tracking, grid math, fog rendering, landmarks, backup, stats and the
  test helpers. Read the relevant section before changing that area.
- **One target, two apps.** The normal app and an isolated **Study** app (used for
  location-battery feasibility experiments) are built from the same target and differ only by
  bundle ID, switched at runtime. Read **Two app identities** in the codebase guide before
  touching `LocationService`, `FogOfWalkApp`, `MapContainerView`, or `SettingsView`.
- **Location/battery work:** after this file, read `docs/SYSTEM.md`, then the current proposal
  and prototype record linked from `docs/README.md`. Older proposals and evidence there are
  historical. Their next-step instructions don't apply.
- **Definition of done:** build and full XCTest suite pass (see **Build & test**). If the
  simulator is unavailable, say so. A compile-only build is not a test pass.

---

## Study app rules

- Normal Fog keeps legacy tracking whatever is persisted. `LocationService` ignores the
  `locationStudy.*` defaults unless `isStudyApp`. Gate every Study behavior on `isStudyApp`
  and test both identities (inject `isStudyApp:` in tests).
- Diagnostics observe; they never filter exploration. `StudySampleValidator` decisions are
  shadow-only. The live source has its own freshness filter.
- Diagnostic logs and motion files hold precise locations. They stay in the Study app's
  container (excluded from backup, 7-day retention, 16 MiB cap). Never commit them or raw traces.
- Lifecycle and next actions for this work live in the workspace initiative
  `fog-adaptive-location-tracking`. Physical installs and phone trials are owner-coordinated;
  follow `docs/evidence/automatic-pause-resume-prototype.md`, and never uninstall the Study app
  (that deletes its data).
- Build Study with the command-line overrides in `SETUP.md` section 3. Normal builds also
  override `CURRENT_PROJECT_VERSION`; the checked-in value is `1`.
- Preserve `callbackEpoch` when editing location delegate code: it drops late callbacks from
  the previous source or OFF state.

## Key constraints

- **`@MainActor` everywhere.** `CLLocationManagerDelegate` methods are `nonisolated` and hop
  back with `Task { @MainActor in ... }`, re-checking the callback epoch.
- **Callback wiring.** `locationService.onLocationUpdate` and `store.onNewCell` are set once,
  in `FogOfWalkApp.init`, through `ExplorationRecorder.connect`. Don't wire recording from a view:
  iOS can relaunch the app in the background without creating a scene, and samples delivered
  then would be dropped.
- **Fog refresh inputs.** `Coordinator.invalidateFogTiles()` is the only way to push new state
  to the renderer. Keep `visitedCellCount` and `highlightGeneration` as `MapContainerView`
  inputs if you restructure the view.
- **Discovery cost** must not grow with the visited set; tests assert this through
  `lastDiscoveryProbeCount`. Keep `GridMath.cellBox(around:radiusMeters:)` a strict superset
  of the radius disc.
- **Core Data context:** always `container.viewContext`, with
  `automaticallyMergesChangesFromParent = true`. `NSBatchDeleteRequest` results are merged back
  manually, and in-memory stores use a manual delete loop (batch delete raises `NSException`).
- **Core Data model changes** must be lightweight-migratable. Only a definitively unreadable
  store is copied aside and reset; never weaken that classification or delete originals as a
  fallback (details in the codebase guide).
- **No `fatalError`** for recoverable errors such as Core Data load failures.
- **`@Observable` / iOS 17 APIs** are required. Don't back-port to `ObservableObject`.
- **XCTest only; no SwiftUI previews.** There are no `import Testing`, `@Test`, `#expect`, or
  `#Preview` uses. Test rendering in the simulator.
- **No haptics.** This is deliberate: tracking runs for hours in the background, and a buzz per
  50 m cell is noise. Don't reintroduce them.
- **Concurrency:** the project is in Swift 5 mode with `MainActor` default isolation on the
  app target. The fog render path runs off-main; mark it `nonisolated` before any Swift 6
  migration. The app target has three known compiler warnings; don't add more.

---

## Testing conventions

- **XCTest only.**
- **`@MainActor @Observable` store/service tests are `async`** and wrap every interaction in
  `await MainActor.run { }`. This avoids an iOS 26+ simulator crash
  (`swift_task_deinitOnExecutorImpl` / TaskLocal heap corruption) when such an object is
  deallocated outside a Task. See the headers of `LandmarkStoreTests.swift` and
  `ExplorationStoreTests.swift`.
- **Renderer and pin-view tests are different:** `FogOverlayRendererTests` and
  `LandmarkAnnotationViewTests` mark the class `@MainActor` and use synchronous methods. Follow the
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
- **Rendering, map and fixture helpers** are listed under **Test infrastructure** in the
  codebase guide. Unit tests are hosted in the app, so `FogOfWalkApp.init` runs first.

---

## Build & test

```bash
# Build
xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build

# Full suite (unit + landmark gestures + UI launch test)
xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test

# Unit tests only (faster)
xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:FogOfWalkTests test
```

If that simulator doesn't exist, pick one from `xcrun simctl list devices available | grep iPhone`.
The latest landmark implementation full-suite result is in `docs/evidence/native-landmark-annotations.md`.
Study-specific evidence remains in `docs/evidence/automatic-pause-resume-prototype.md`.

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
   migration can infer (see Core Data load failure in the codebase guide), update the `+CoreData.swift` subclass and
   store, and carry user data through `BackupPayload`: add optional fields and bump
   `currentSchemaVersion`.
2. **New setting?** Add a `GridSettings` property with a `UserDefaults` `didSet`, following
   `highlightToday`/`showLandmarks`.
3. **New view?** Read environment objects with `@Environment(ExplorationStore.self)` etc., and keep
   views `@MainActor`-safe.
4. **New cell math?** Put it in `GridMath` as static functions with no stored state.
5. **Study-only behavior?** Gate it on `isStudyApp`, keep the normal default unchanged, test both
   identities, and never let diagnostics filter exploration.
6. **New landmark category?** Update the three category maps listed under Landmarks in the codebase guide.
7. **Every feature or bug fix needs tests.** Bug fixes need a regression test that would have
   caught the bug. Follow the patterns above.
8. **Run the full suite** (`xcodebuild ... test`), not just the new tests. Build and tests must
   pass before the task is done.
9. **Keep the docs current.** If you change behavior described here, in `docs/CODEBASE.md`
   or in `docs/SYSTEM.md`, update them in the same change.
