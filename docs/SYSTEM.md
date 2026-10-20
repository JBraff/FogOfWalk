# Fog of Walk system architecture

Fog of Walk is an iOS application that clears a fog-of-war overlay from Apple
Maps as the user physically explores. It represents exploration as fixed 50 m
grid cells and persists those cells locally with Core Data. Everything runs
on-device. The only network use is Apple's reverse geocoding for locality names.

## System shape

```text
CLLocationManager (legacy)   CLLocationUpdate.liveUpdates (Study app only)
            \                  /
             LocationService.onLocationUpdate
                      |
        map Coordinator (normal app) | app-owned closure (Study app)
                      |
             ExplorationRecorder
               -> ExplorationStore -> Core Data VisitedCell     -> LocalityGeocoder
               -> LandmarkStore    -> Core Data Landmark (discovery)
                      |
             CellSnapshot -> FogOverlayRenderer (MapKit tile threads)

Map region change -> LandmarkSearchService -> bundled landmarks.sqlite -> LandmarkStore
```

`LocationService` turns Core Location callbacks into single location samples.
`ExplorationRecorder` converts each sample to a `CellID` through `GridMath`,
handles day rollover, persists a newly visited cell through `ExplorationStore`,
and checks landmark discovery for that cell. The map coordinator then publishes
an immutable `CellSnapshot` to the renderer, which draws the overlay on MapKit's
background rendering threads.

## Data ownership

- `ExplorationStore` is the source of truth for visited cells and exploration
  counts. It owns Core Data access for the visited-cell history.
- `LandmarkStore` owns landmark rows copied from the bundled Wikidata database
  and their discovery state. Rows are copied only when the map shows a region,
  so discovery in an area the user has never viewed waits until it is viewed.
- `LocalityGeocoder` annotates visited cells with locality, state, and country
  for the statistics sheet.
- `GridSettings` owns persisted presentation settings.
- `BackupService` performs manual, versioned export/import and merge of
  exploration and discovery state. It does not provide automatic sync.

## Two app identities

One Xcode target builds both the normal app (`com.jeremybraff.fogofwalk`) and
an isolated **Study** app (`com.jeremybraff.fogofwalk.study`, set through
command-line build-setting overrides). Study behavior is selected at runtime by
bundle ID. That covers the alternative location source, a tracking-OFF control,
opt-in local diagnostic capture, and post-run motion history. The normal app always
uses legacy tracking, whatever settings are persisted.

## Concurrency and rendering

The app target defaults to `MainActor`. The location service's delegate callbacks
return to the main actor before mutating app state. A callback epoch discards
late callbacks from a previous Study source or OFF state. MapKit renders fog
tiles on background threads, so `FogOverlayRenderer` reads only the immutable
`CellSnapshot` under its lock. Visited cells are drawn at every zoom level with
a minimum on-screen radius of 3 points. Landmark pins are a sibling UIKit view
and follow map gestures separately from the fog overlay.

## Location and correctness constraints

Exploration is based on actual location samples. The application never invents a
route between sparse samples. Standard location updates prioritize continuity:
background updates stay enabled, automatic pausing remains disabled, and
significant-change monitoring remains a recovery/relaunch safety net rather than
the primary tracker. The Study-only feasibility proposal is documented in
[Automatic stationary pause and walking resume](proposals/2026-10-15-automatic-stationary-pause-and-resume.md).
It evaluates framework-managed stationary/resume behavior without changing the
production default. The earlier measurement-first study is historical. Proving
a battery-saving percentage is not a prerequisite for this feasibility answer.
The earlier explored-area adaptive-location proposal is deprecated.

The isolated Study app can select a persisted `CLLocationUpdate.liveUpdates(.fitness)`
source. `LocationService` retains its background and Always service sessions,
keeps the sequence open while the framework suspends updates for a stationary
user, and cancels old generations when sources or permissions change. This arm
disables location requests from the legacy manager and MapKit user location,
including the native dot and follow mode. The app owns Study exploration
recording and wires it before the map is created. `ExplorationRecorder` gives
Study the same cell, day-rollover, and discovery path the normal map coordinator
uses. Normal Fog and missing or unknown selections keep legacy behavior. See the
[prototype record](evidence/automatic-pause-resume-prototype.md) for the focused
trial and evidence limits.

## Operational constraints

- The grid coordinate system is globally aligned at `(0°, 0°)` and uses a 50 m
  cell size for all new visits.
- Core Data model changes must be lightweight-migratable. A store that fails to
  load is moved aside and recreated empty.
- XCTest is the test framework. Tests for main-actor observable stores use the
  repository's established async pattern to avoid an iOS simulator deallocation
  crash.
- The Xcode project has no shared scheme. Build and test commands in `AGENTS.md`
  therefore rely on the local autogenerated `FogOfWalk` scheme.

For implementation-specific constraints, build commands, and agent behavior,
read the repository's `AGENTS.md`.
