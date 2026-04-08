# Fog of Walk — Agent Guide

iOS app that overlays a "fog of war" on Apple Maps and lifts it as the user physically walks through the world. Written in Swift, targeting iOS 17+.

---

## Project layout

```
FogOfWalk/
  FogOfWalk.xcodeproj
  FogOfWalk/
    FogOfWalkApp.swift          # @main — creates the three environment objects
    ContentView.swift           # Root view: MapContainerView + StatsView sheet
    Info.plist                  # Location permission strings, UIBackgroundModes: [location], single-scene
    FogOfWalk.xcdatamodeld/     # Core Data model (single VisitedCell entity, codeGenerationType="none")
    Models/
      GridCell.swift            # CellID, kCellSizeMeters constant (50m), GridMath namespace
      GridSettings.swift        # @MainActor @Observable — persists highlight period to UserDefaults
      ExplorationStore.swift    # @MainActor @Observable — Core Data + in-memory cache
      VisitedCell+CoreData.swift # NSManagedObject subclass (cellX, cellY, cellSizeMeters, firstVisited)
    Services/
      LocationService.swift     # @MainActor @Observable wrapping CLLocationManager
    Views/
      MapContainerView.swift    # UIViewRepresentable: MKMapView + FogView sibling
      FogView.swift             # UIView: grey fog with radial-gradient holes per visited cell
      StatsView.swift           # HUD: cell count, city %, pause indicator, settings button
      SettingsView.swift        # Sheet: highlight period picker, delete-all action
  FogOfWalkTests/
    FogOfWalkTests.swift        # GridCellTests — CellID arithmetic, GridMath edge cases
    ExplorationStoreTests.swift # Core Data add/delete/count via in-memory store
    FogViewTests.swift          # Pixel-level rendering tests with coordinate mocks
  FogOfWalkUITests/
    FogOfWalkUITests.swift      # UI automation tests
    FogOfWalkUITestsLaunchTests.swift # Launch screenshot tests
SETUP.md                        # One-time Xcode project setup instructions
```

---

## Architecture

### Data flow
```
CLLocationManager → LocationService.onLocationUpdate closure
  → Coordinator.handle(location:)
    → ExplorationStore.addCell(_:)                   [Core Data + in-memory Set]
      → FogView.update(cells:cellSize:)              [calls setNeedsDisplay]
```

### Environment objects
All three are injected at the `WindowGroup` level via `.environment(...)` and accessed with `@Environment(T.self)`:

| Type | Role |
|------|------|
| `ExplorationStore` | Source of truth for visited cells; wraps Core Data |
| `GridSettings` | Single setting: `highlightPeriod` (recent-walk highlight window) |
| `LocationService` | Location permission + streaming; exposes `onLocationUpdate` closure |

### Coordinate system
`GridMath` divides the globe into a uniform rectangular grid. `CellID(x: Int32, y: Int32)` is the grid address. Converting a `CLLocationCoordinate2D` to a `CellID` and back is pure arithmetic — no map SDK required. The grid is always aligned to `(0,0)` at (0°, 0°).

Cell size is fixed at `kCellSizeMeters = 50.0` (defined in `GridCell.swift`). The `VisitedCell` Core Data entity retains the `cellSizeMeters` column for existing data; all new rows are written with 50.0.

### Fog rendering
`FogView` is a plain `UIView` sibling of `MKMapView` (not an `MKOverlay`). On each `draw(_:)`:
1. Flood-fill the entire view with semi-transparent grey.
2. For each visited cell visible in `rect`, punch a radial gradient hole using `.clear` blend mode.
3. Cells outside `rect` are skipped (perf guard).

`MapContainerView.Coordinator` implements `mapViewDidChangeVisibleRegion(_:)` (throttled to 50 ms) and `regionDidChangeAnimated(_:)` to call `refreshFog` continuously during pan/zoom.

---

## Key constraints and gotchas

- **Cell count cap:** `GridMath.cells(in:)` returns `[]` when a region would produce >10 000 cells. At world zoom the fog stays fully opaque — this is intentional and correct.
- **`@MainActor` everywhere:** `ExplorationStore`, `GridSettings`, and `LocationService` are all `@MainActor`. `CLLocationManagerDelegate` methods on `LocationService` are `nonisolated` and dispatch back via `Task { @MainActor in ... }`.
- **Closure rewiring:** `locationService.onLocationUpdate` is reassigned in `updateUIView` (not just `makeUIView`) so it always captures the live coordinator after SwiftUI rebuilds.
- **Core Data context:** Always use `container.viewContext` (main-queue context). `automaticallyMergesChangesFromParent = true` is set. `NSBatchDeleteRequest` results are merged back manually via `NSManagedObjectContext.mergeChanges(fromRemoteContextSave:into:)`.
- **iOS 17+ only:** Required for `@Observable`. Do not back-port to `ObservableObject`.
- **No Swift Testing / #Preview:** The test target uses XCTest. There are no SwiftUI previews — test rendering in the simulator.
- **Haptic feedback:** `UIImpactFeedbackGenerator.light` fires on each new cell discovery.
- **City % calculation:** `StatsView` reverse-geocodes every 500m+ to get a city name and `CLCircularRegion`. The percentage is relative to that circle, not actual administrative boundaries — it's an approximation.
- **`cos(latitude)` correction:** `totalCellCount` divides the longitude span by `cos(lat)` to correct for meridian convergence. Without this, city % is wrong at non-equatorial latitudes.

---

## Testing conventions

- **XCTest only** — do not use Swift Testing (`#expect`, `@Test`, etc.).
- **ExplorationStore tests must be `async`** — use `await MainActor.run { }` for all store interactions. iOS 26 beta crashes if `@MainActor @Observable` objects are deallocated outside a Swift Task context.
- **In-memory Core Data:** use the `makeInMemoryContainer()` helper (defined in `ExplorationStoreTests.swift`) for all tests that need a Core Data store.
- **FogView pixel tests:** use the `pixelColor(at:in:)` helper with a `scale=1` renderer. Use `installCoordinateMock()` for deterministic coordinate projection without a live `MKMapView`.
- **`NSBatchDeleteRequest` on in-memory stores:** raises `NSException` (not a Swift `Error`). Production code checks for `NSInMemoryStoreType` before choosing between batch and manual delete. Do not attempt batch delete in tests.

---

## Known platform quirks

- **iOS 26 beta — `@Observable` dealloc crash:** `@MainActor @Observable` objects crash when deallocated in non-Task XCTest context. Workaround: make test methods `async` and wrap work in `await MainActor.run { }`.
- **iOS 26 beta — `NSBatchDeleteRequest` on in-memory stores:** throws `NSException` instead of returning an error. Workaround: check the store type and fall back to manual `context.delete()` loop for in-memory stores.
- **`FogView.coordinateToPoint` closure:** exists specifically for unit testing. The override lets tests inject deterministic coordinate→point mapping. Production code path uses `mapView.convert(_:toPointTo:)`.

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

### Simulating movement
In the running simulator: **Features → Location → City Bicycle Ride** (or Apple). Watch the fog lift in real time.

---

## Adding features — checklist

1. New persistent data? Add an entity to `FogOfWalk.xcdatamodeld`, create a `+CoreData.swift` subclass, update `ExplorationStore`.
2. New setting? Add a property to `GridSettings` with a `UserDefaults` `didSet`.
3. New view? Access environment objects with `@Environment(ExplorationStore.self)` etc. Keep views `@MainActor`-safe.
4. New math on cells? Put it in `GridMath` (static functions, no stored state).
5. **Every feature or bug fix must include tests.** Add or update unit tests for any new logic, model changes, or view behavior. If fixing a bug, add a regression test that would have caught it.
6. New tests? Follow the async/`MainActor` pattern for anything touching `ExplorationStore`. Use `makeInMemoryContainer()`. For rendering tests, use `pixelColor(at:in:)` and `installCoordinateMock()`.
7. Always run the full test suite (`xcodebuild ... test`), not just the new tests.
8. After any change: build **and tests** must succeed before considering the task done.
