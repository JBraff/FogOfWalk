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
        closure wired at app launch (both identities)
                      |
             ExplorationRecorder
               -> ExplorationStore -> Core Data VisitedCell     -> LocalityGeocoder
               -> LandmarkStore    -> bundled landmarks.sqlite (ingest near new cells)
                                   -> Core Data Landmark (discovery)
                      |
             map Coordinator -> CellSnapshot -> FogOverlayRenderer (MapKit tile threads)

Map region change -> LandmarkSearchService -> bundled landmarks.sqlite -> LandmarkStore
```

`LocationService` turns Core Location callbacks into single location samples.
`ExplorationRecorder` converts each sample to a `CellID` through `GridMath`,
handles day rollover, persists a newly visited cell through `ExplorationStore`,
ingests nearby bundled landmarks, and checks landmark discovery for that cell. It
is wired when the app launches, not by the map, so recording also works when iOS
relaunches the app in the background without a visible scene. When the map is
on screen, its coordinator publishes an immutable `CellSnapshot` to the renderer,
which draws the overlay on MapKit's background rendering threads.

## Data ownership

- `ExplorationStore` is the source of truth for visited cells and exploration
  counts. It owns Core Data access for the visited-cell history.
- `LandmarkStore` owns landmark rows copied from the bundled Wikidata database
  and their discovery state. Rows are copied when the map shows a region and
  around each newly walked cell. Successful walk-time ingests are cached per launch;
  failed inserts reset the identifier cache, leave their areas retryable, and are
  logged as `landmark_ingest_failed` in a Study capture.
- `LocalityGeocoder` annotates visited cells with locality, state, and country
  for the statistics sheet. Newly walked cells are geocoded ahead of the launch
  backfill of older untagged cells. Country statistics exclude unresolved labels without
  removing visits from exploration totals. Missing countries (including legacy empty or
  "Unknown" labels) are retried by the bounded backfill on later launches and replaced
  only when a country is returned; existing known labels are preserved.
- `GridSettings` owns persisted presentation settings. Its default storage is standard
  UserDefaults; isolated fixtures can select memory-only settings.
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
a minimum on-screen radius of 3 points. Landmarks are lightweight native MapKit
annotations with reusable custom views above the fog. Their icons and labels keep a
fixed screen size and orientation during map movement. Hints are disabled and ignore
all touches; discovered pins sit above them and retain a 30-point hit radius centred
on the drawn icon. The user location dot and heading pointer sit above discovered pins,
including during selection. Wide labels do not claim touches outside the icon circle.
Discovered pins open details and deselect immediately to allow repeated taps. Initial
rasterization uses resolved map traits; unresolved traits defer drawing until attachment.
Pre-window preparation reuses a resolved bitmap until the view's actual appearance changes.
An attached view with unresolved supplied traits uses its own appearance, and attachment
redraws a pin whose data changed while detached. Deferred views stay disabled and outside
accessibility until drawn; reuse clears their old geometry. Interaction state is reapplied
even when the bitmap is unchanged. The user-location view owns its stacking priority, and
the delegate reapplies it when dequeuing a view.

At settle, the coordinator preserves the existing visible-region selection, then fills
spare capacity from already-ingested landmarks within twice the visible span. Visible
pins take priority over buffer candidates; discoveries take priority over hints when a
region's candidates exceed capacity. The full installed set stays within 300 annotations,
with required display priority and no clustering. The >1-degree gate uses the visible
region. Padding never expands ingest requests. Selection scans the stored landmark array
once into bounded candidate groups. A dedicated `LandmarkMapView` child observes a render
generation, advanced for landmark context changes (including count-neutral edits) and cache
reloads, plus the display toggle. It supplies explicit representable inputs so only the map
needs a landmark refresh. No manual bitmap transform or mid-gesture refill is used.

For Debug gesture tests, the fixture launch gate runs before production `AppServices`
construction. The fixture opens only its own in-memory store, uses memory-only preferences
and creates no production location services. Normal launch still constructs and connects
recording synchronously before any scene, including a background relaunch.

## Map orientation

Turning the phone changes the direction pointer around MapKit's native blue dot,
without rotating the map. The recenter button always requests location-follow mode;
repeated taps cannot enter heading-follow mode. Manual rotation remains available,
and the adaptive compass returns the map to north-up. The recenter arrow is outlined
when not following and filled when following, with the same state exposed to VoiceOver.
The map observes scene geometry to update heading orientation even for a direct
landscape-left/right flip that does not change its size.

`HeadingMapView` owns a heading-only Core Location manager, separate from exploration.
It runs only while the map has a window, the scene is active, location permission
and heading hardware are available, and `LocationService.usesMapLocation` is true.
Backgrounding, removing the map or selecting Study OFF/automatic pause-resume stops
heading updates and clears the pointer. Invalid readings hide the pointer; magnetic
heading is used when true heading is unavailable. Each callback captures the current
session ID before the main-actor hop: callbacks queued before a stop/restart are
ignored, while the first cached reading in the new session is accepted. This manager
never requests location samples or changes recording.

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
including the native dot and follow mode. Both identities record through the
same app-owned `ExplorationRecorder`, wired before the map is created. Normal Fog and missing or unknown selections keep legacy behavior. See the
[prototype record](evidence/automatic-pause-resume-prototype.md) for the focused
trial and evidence limits.

## Operational constraints

- The grid coordinate system is globally aligned at `(0°, 0°)` and uses a 50 m
  cell size for all new visits.
- Core Data model changes must be lightweight-migratable. An unreadable store
  (corrupt, or a model change migration can't open) is copied aside (including its WAL
  and SHM) before being recreated empty, and the user is told. Other load errors may be
  transient, so that store is left untouched. Generic migration errors require a definitive
  unreadable cause; unknown or mixed causes preserve storage. That case and any backup or
  reset failure disable writes for that launch; originals are never deleted as a fallback. The UI
  reports unavailable storage.
- XCTest is the test framework. Tests for main-actor observable stores use the
  repository's established async pattern to avoid an iOS simulator deallocation
  crash.
- The Xcode project has no shared scheme. Build and test commands in `AGENTS.md`
  therefore rely on the local autogenerated `FogOfWalk` scheme.

For implementation-specific constraints, build commands, and agent behavior,
read the repository's `AGENTS.md`.
