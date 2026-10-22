# Fog of Walk — Navigation and Explore Mode

**Status:** Revised proposal for engineering and product review; not accepted architecture or implementation authorization.

**Date:** 2026-10-22.

**Basis:** Code inspection at `6a03ae1ee74cd2b6b6569c93ce70d12c197f2409`, the [system architecture](../SYSTEM.md), and the platform references linked below.

**Source:** [Original product brief, preserved as supplied](2026-10-22-navigation-explore-original.md).

This document evaluates and rewrites the original brief. Proposed delivery slices
below describe dependencies and acceptance, not current initiative milestones.
Initiative authorization, lifecycle, progress and next actions belong in
`agent-workspace/work/initiatives/`. This proposal does not extend the separate
`fog-adaptive-location-tracking` initiative or authorize its production rollout.

## 1. Product outcome and recommendation

Help someone walking in an unfamiliar city answer three questions:

1. Where am I, and which way is my phone pointing?
2. Which available walking route to my destination offers worthwhile new territory?
3. Where could I walk next if I have no destination?

Keep the existing map and automatic exploration recording central. Ship orientation
controls independently. Then add search and exploration comparison of walking routes
returned by Apple, followed by basic foreground guidance. Develop destination-free
suggestions on that foundation. Generating custom detours and timed loops requires
a separate feasibility decision; it should not delay useful map controls.

The original brief's direction is sound, but its P0 combines several new systems.
The code has neither routing nor a navigation session model. The most practical
first routing release can **score available routes**, not promise to find the best
exploration route through an arbitrary street network.

### Evaluation of the original assumptions

| Original area | Finding and recommended revision |
| --- | --- |
| Orientation and recentering | Strong immediate value. Initial native following exists, but an explicit recenter control and heading handling are missing. Keep these first. |
| Saved places and Collections | Neither exists in Fog. Remove them as initial dependencies; consider a discovered landmark as a later destination entry point. |
| Fastest, Balanced, Maximum Exploration | Apple may return only one route. Start with honest comparison of returned candidates; replace “Maximum” with “More to explore” and reserve custom detours for a feasibility gate. |
| Area uncovered | The grid is fixed in degrees, and rendered holes change with zoom. Use estimated new cells first; do not multiply every cell by 2,500 m² or measure screen pixels. |
| Unexplored streets | Fog knows visited cells, not a street graph or whether every street in a cell was walked. Initially highlight unvisited portions of validated route geometry. |
| Pleasant and accessible routes | The bundled dataset has landmark coordinates and categories, not entrances, access restrictions, pavement, opening hours or scenic ratings. Use walking directions and conservative filtering; avoid unsupported quality claims. |
| Landmark visits | Existing “discovered” means a visited cell was within a category radius. It does not establish entry into a building or a visit to an attraction. |
| Offline support | Cell storage and the bundled landmark database are local. Map tiles and reverse geocoding depend on Apple services; Fog has no downloadable basemap or offline routing engine. Preserve local behavior without promising complete offline maps. |
| Basic navigation | Route geometry and step text are available from MapKit. Progress matching, deviation handling, arrival and session lifecycle would be new Fog behavior. |
| Timed walks and summaries | Feasible candidates for later work, not small UI additions. There is no stored ordered walk trace, walk session or measured distance history to reuse. |

## 2. Existing capabilities to reuse

These are observations about the inspected revision, not proposed new behavior.

| Capability | Current implementation and consequence |
| --- | --- |
| Map | [`MapContainerView`](../../FogOfWalk/FogOfWalk/Views/MapContainerView.swift) wraps `MKMapView`. It enables `.follow` when user-location display is first enabled. `MapNavigationTarget` in [`ContentView`](../../FogOfWalk/FogOfWalk/ContentView.swift) only changes the visible region; it is not a route. Retain this map integration. |
| Recording | [`ExplorationRecorder.connect`](../../FogOfWalk/FogOfWalk/Services/ExplorationRecorder.swift) owns the single `onLocationUpdate` closure and runs from app initialization, including scene-less launches. Navigation must never replace that closure or make recording depend on a view. |
| Location | [`LocationService`](../../FogOfWalk/FogOfWalk/Services/LocationService.swift) publishes the latest location. Normal Fog uses legacy tracking with a 15 m distance filter and automatic pause disabled. Heading is not currently exposed. |
| Study isolation | Study uses the same compiled target and runtime identity checks. Its automatic pause/resume and tracking-OFF modes disable MapKit user location. New controls must respect `usesMapLocation`, source generations and OFF state. |
| Exploration | [`GridMath`](../../FogOfWalk/FogOfWalk/Models/GridCell.swift) maps each actual sample to a nominal 50 m cell; east–west width shrinks with latitude. [`ExplorationStore`](../../FogOfWalk/FogOfWalk/Models/ExplorationStore.swift) holds the visited set. Route estimates should read a snapshot of that set. |
| Fog and pins | [`FogOverlay`](../../FogOfWalk/FogOfWalk/Views/FogOverlay.swift) renders above map labels. [`LandmarkOverlayView`](../../FogOfWalk/FogOfWalk/Views/LandmarkOverlayView.swift) is a sibling view whose gesture transform handles translation and scale. Route layering and camera rotation need deliberate integration. |
| Landmarks | [`BundledLandmarkSource`](../../FogOfWalk/FogOfWalk/Services/BundledLandmarkSource.swift) queries a bundled Wikidata database of 14,943 entries. [`LandmarkStore`](../../FogOfWalk/FogOfWalk/Models/LandmarkStore.swift) ingests nearby entries and tracks radius-based discovery. Locally ingested rows are not the complete nearby dataset. |
| Display preferences | [`GridSettings`](../../FogOfWalk/FogOfWalk/Models/GridSettings.swift) controls today's highlight and landmark pins. Pins default off; undiscovered pins are question-mark hints. Explore suggestions must not silently change those preferences. |
| Persistence and statistics | [`BackupService`](../../FogOfWalk/FogOfWalk/Models/BackupService.swift) exports/merges cells and discovered landmarks. [`DiscoveryStatsModel`](../../FogOfWalk/FogOfWalk/Models/DiscoveryStatsModel.swift) estimates distance from cell count × 50 m; that is not measured route distance. There is no walk-session history or automatic sync. |

## 3. Requirements that apply to every delivery slice

**R1 — Recording and data integrity.** Route generation, selection, previews,
progress matching and arrival must never add visited cells or mark landmarks
discovered. Navigation consumes actual location samples; its projected or snapped
positions must not enter `ExplorationRecorder`. Do not interpolate exploration
between sparse samples. Preserve existing backup/import semantics, migrations,
storage-error handling and the ability to record without a visible map.

**R2 — Location ownership.** Keep normal Fog's tracking policy unchanged. Use the
existing location service; do not introduce a second navigation location manager,
increase GPS accuracy or start another location stream as a side effect. Ending a
route stops guidance, not exploration tracking. Navigation-specific freshness and
accuracy checks must not filter the recording path. Preserve callback epoch checks.

**R3 — Permissions and Study behavior.** Work within the current permission state;
do not require Always permission merely to compare a route. Existing locked-screen
recording still depends on the app's authorization and platform behavior. Initially,
new orientation/navigation controls target normal Fog and Study's Legacy mode.
When Study disables MapKit location, make those controls unavailable with an
explanation; never enable MapKit or heading consumers to satisfy them. A switch
to live/OFF during guidance must end guidance and release new consumers. Supporting
the live arm's map/navigation UI is separate work.

**R4 — Offline continuity.** Keep cell recording, saved history, cached exploration
display and bundled landmark lookup usable without network access. New search and
routing can require connectivity. Retain an already loaded route's geometry and
instructions in memory through connectivity loss; show that recalculation is
unavailable. Map tiles may be missing. First release does not promise route recovery
after process termination, basemap downloads or offline route calculation.

**R5 — Performance and privacy.** Search/routing requests occur only after user
interaction, with cancellation and stale-response rejection. Do not route on every
GPS update or map pan. Use local visited-cell scoring; never upload exploration
history to rank routes. Explain that search terms and route endpoints go to Apple's
services. Avoid raw location/query logs or new analytics infrastructure. Follow the
repository's precise-location restrictions for any device evidence.

**R6 — Map usability.** Preserve the existing HUD, stats, settings, permission and
storage notices, fog updates and landmark taps. New controls must support VoiceOver,
Dynamic Type and sufficient contrast. Distinguish selected routes and unvisited
segments with more than color alone. No haptics.

## 4. Orientation: the first independent release

Provide a visible recenter control and an approximate device-heading indicator on
the existing map, north-up by default. Device heading is not the person's gaze;
course is direction of travel and must not be substituted as “facing direction.”
Core Location distinguishes these signals and heading requires physical hardware;
the simulator cannot establish compass quality. See Apple's
[heading and course guidance](https://developer.apple.com/documentation/corelocation/getting-heading-and-course-information).

The recenter control returns to the current usable location and resumes following.
Panning or choosing a stats-region/route overview leaves following until the user
explicitly resumes it. Ordinary SwiftUI updates must not reset the camera. Keep
zoom sensible and the user's position visible above expanded panels.

Prefer native MapKit tracking primitives where they match this interaction. A
native tracking button is a candidate, not a requirement: its mode changes must
not introduce heading-up behavior unintentionally. North-up with a heading marker
may require a small custom presentation and heading support in `LocationService`.
Acquire heading only while the foreground map needs it; stop it on background,
permission loss or a Study mode change. Hide or soften the marker for unavailable,
invalid or stale readings; do not display a confidently wrong arrow.

Heading-up is deferred. Before adding it, verify rotation/pitch behavior of the
landmark sibling overlay and hit testing. Its current scale/translation transform
is not evidence that rotation is correct. Explicitly validate any retained manual
rotation behavior as part of map QA.

**Acceptance:** pan → recenter → follow works repeatedly without snapping back
after a subsequent pan; a stats-region jump remains where requested; denied or
missing location has an understandable state; heading remains useful while standing
at an intersection on a phone; background tracking and both identities retain
their prior behavior. No route infrastructure is required to ship this slice.

## 5. Destination routes: compare what is available

### Search and request lifecycle

Add address/place-name search with `MKLocalSearch` and resolve a result before
requesting walking directions from a fresh, sufficiently accurate current location.
Wait for a usable fix rather than silently routing from a stale one. Define freshness
and accuracy thresholds in the implementation design and test their boundaries.
The initial UI can use explicit search submission; autocomplete is optional.
Apple documents that [local search is server-based](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/EnablingSearch/EnablingSearch.html).

Keep loading, empty results, permission denial, no walking route, offline, timeout
and service-throttling states distinct. Changing the query/destination cancels old
work and invalidates its responses. Starting with a significantly changed location
requires refreshing the preview. A discovered landmark can be added as a destination
entry point after search works. Saved places, Collections and custom origins are
new features and outside this first slice.

### Provider routes before custom optimization

Use one `MKDirections` request with walking transport and alternate routes enabled
per explicit comparison. Apple returns additional routes only when available; the
flag is not a promise of three. See
[`requestsAlternateRoutes`](https://developer.apple.com/documentation/mapkit/mkdirections/request/requestsalternateroutes).

Recommended first-release limits are one in-flight comparison request and a
15-second cancellable request deadline, with explicit retry and no automatic retry
loop. These are proposed Fog limits, not Apple's quotas. Validate responsiveness
and throttling behavior before choosing final constants.

MapKit's public request supports origin, destination and transportation options,
but exposes neither Fog's cell costs nor a pedestrian graph for custom optimization.
See [`MKDirections.Request`](https://developer.apple.com/documentation/mapkit/mkdirections/request).
The architectural inference is to rank returned candidates locally. Do not describe
this as a globally optimal route search or rely on APIs newer than iOS 18.6 without
an availability path. The inspected SDK declarations are an aid, not a substitute
for building and testing at the deployment floor.

Display one to three meaningfully different candidates. Always retain the shortest
estimated-time candidate as **Fastest available**. Prefer **More to explore** over
“Maximum Exploration.” Do not force labels or duplicate a route to fill three slots.
Recommended detour limits, applied to unrounded time estimates, are:

| Candidate | Maximum extra time over fastest available |
| --- | --- |
| Balanced, if useful | Smaller of 20% or 5 minutes |
| More to explore, if useful | Smaller of 50% or 15 minutes |

These are ceilings, not targets. Remove dominated alternatives: a slower route with
no additional estimated new cells offers no exploration benefit. Suppress geometric
near-duplicates even if the provider names differ. The feasibility check must choose
and document a minimum useful cell gain and geometric-overlap threshold using
representative examples; labels remain provisional until that check passes.

The original 12-minute/15-minute “Balanced” example exceeds its own 20% limit.
With that limit, 12/14/18 minutes could qualify, if the actual unrounded estimates,
route differences and cell gains support the labels. When only one useful candidate
exists, explain that the **available routes** offer little additional exploration;
that does not prove the surrounding neighborhood is fully explored.

### Exploration estimates

For a candidate route, derive the unique set of grid cells intersected by its
polyline and subtract a consistent snapshot of existing visited cells. Repeated
segments and loops count each potential new cell once. Describe the result as
**estimated new cells along the route**, not guaranteed cells that will be recorded.
GPS sampling can miss cells; map matching and estimate geometry must not change
what actual exploration records.

Use the existing `GridMath` cell definition. A pure, bounded segment-to-grid
calculation is new work: cover long segments, negative coordinates, cell-boundary
ties, duplicates, latitude, antimeridian wrapping and degenerate geometry. Do not
use only route vertices, a fixed sampling interval that skips narrow cells, or the
test-only `GridMath.cells(in:)` helper with its 10,000-cell cap. Unsupported geometry
must show an unavailable estimate, not zero exploration or an enormous allocation.

Color/style unvisited portions by the same cell definition. An optional percentage
must measure route length through unvisited cells, not the percentage of vertices
or unique cells. Defer square-meter area: it needs latitude-aware cell geometry and
clear separation from the renderer's overlapping, zoom-dependent holes. Avoid
claims about “unwalked streets” when only cell membership is known.

Compare all alternatives against one snapshot. If the visited set changes before
selection, refresh local estimates without repeating network requests. While a walk
is active, estimate potential new cells only on the remaining route against the
latest visited set, with bounded updates.

### Map presentation and fog

Keep the route readable above the `.aboveLabels` fog overlay and coordinate its
ordering with pins and the user marker. Show selected/unselected states, distance,
estimated duration and potential new cells in a compact expandable panel. Explicit
preview should frame the route without fighting follow mode.

First release keeps normal fog intact and draws the route over it. If physical
usability testing shows street detail is essential, add a narrow, temporary preview
treatment as a separate rendering change. It must never alter visited-cell caches,
today's highlights, stats, persistence or backups, and must disappear on dismissal.
Navigation must not call exploration writes to make a preview visible.

**Acceptance:** all-new/all-visited/overlapping-route fixtures produce sensible,
stable estimates; duplicates disappear; 20% and 50% boundaries use unrounded times;
one route is valid output; late/cancelled replies cannot replace the current preview;
search, preview and dismissal leave exploration data unchanged.

## 6. Basic foreground guidance

Reuse the selected route for a compact panel showing the next useful instruction,
remaining route distance, approximate remaining time and estimated new cells ahead.
Mark completed and upcoming geometry differently. MapKit supplies
[route geometry](https://developer.apple.com/documentation/mapkit/mkroute/polyline)
and [step data](https://developer.apple.com/documentation/mapkit/mkroute/steps);
Fog still needs to decide which step applies as the person moves.

Introduce an app-owned, initially in-memory navigation session: idle, previewing,
guiding, position uncertain/off route, and finished. Keep selection stable. Match
usable samples to nearby route segments with continuity checks so crossings,
parallel streets and GPS jumps cannot skip arbitrarily far ahead. Snapping is a
display/progress calculation only. Do not reconstruct actual walked distance from
new-cell count, elapsed time or the provider's full route length.

For sustained deviation, offer **Recalculate** while retaining the destination and
chosen detour objective. Use accuracy-aware distance and persistence thresholds
rather than one bad sample; choose concrete thresholds during design and test
them. Keep the old route if recalculation fails or is cancelled. Do not automatically
switch alternatives as cells become visited. Near the endpoint, require a reliable
arrival condition or user confirmation, never a single stale GPS fix.

Guidance freshness/uncertainty must be visible. With poor location, avoid advancing
instructions or presenting remaining time as live. In the background, preserve
ordinary exploration recording without adding route polling or heading work.
Foreground resume reconciles with the latest actual sample; a missing trace cannot
prove the exact path walked while suspended. Ending guidance releases only its own
work. Voice, lock-screen alerts, automatic rerouting and background turn prompts
are later features.

**Acceptance:** a phone walk supports following, panning, recentering, deviation,
failed recalculation, lock/unlock and completion; unusable samples cannot cause
false guidance progress, and guidance-derived positions cannot create discoveries.
Real off-route samples continue normal exploration. Ending guidance leaves
recording operational.
Connectivity loss retains the loaded route and honest uncertainty. Process restart
returns to the normal map without claiming to resume an unpersisted session.

## 7. Explore Mode: validated suggestions before generated loops

Explore is explicit and opt-in. Keep the ordinary map unchanged when inactive.
Reuse route previews, cell scoring and guidance rather than introducing a second
navigation system.

The first candidate is a small set of nearby destinations, drawn from bundled
landmarks or resolved map-search results, ranked using their returned walking paths.
Highlight unvisited parts of those paths, not an inferred network of streets.
Offer up to three useful suggestions; one or none is acceptable. State “No useful
suggestions found” separately from “Already explored” and network failure. Cardinal
phrasing such as “Explore toward the west” is safer than “Turn right” without a
reliable heading and applicable route step.

Start with at most three candidate destinations and three walking-direction
requests per explicit refresh, one at a time, under a cancellable total time budget.
Choose that budget in the feasibility design. Do not expand the search indefinitely,
poll while walking or route toward arbitrary fog-cell centers, which may be water,
private property or disconnected terrain. Request only candidates intended for
display. Returned paths are required; straight lines are not walking directions.

### Landmark behavior

Query the bundled source within its supported bounds, then use existing discovery
state and visited-cell checks. Do not treat an entry absent from ingested Core Data
rows as certainly undiscovered; it may lie by an already visited cell. Reuse or
extract the existing discovery predicate for a read-only check. Preserve QIDs,
category radii, bounded lookup, the 1.0° ingest-span/500-row contract and the 300-pin
display limit. Missing data should produce an empty result, not a crash or a new
external POI dependency.

Describe candidates as “not yet discovered in Fog,” not “never visited.” Category
radii range from 100 to 500 m; passing nearby can count as discovery. A museum or
park coordinate is not necessarily its public entrance. Initially filter unsuitable
categories such as airports and reject candidates with unusable walking access.
Provider routing is a baseline, not proof of public access, safety, pleasantness or
opening hours. Do not add scenic/accessibility claims without supporting data.

Recommended product choice: explicitly enabling landmark suggestions may show a
candidate's name before discovery, but does not mark it discovered or change the
global `showLandmarks` setting. Keep existing question-mark hints outside Explore.
This is a proposed change to the discovery experience that needs reviewer attention.
Territory-only suggestions can omit landmarks; do not require another POI database.

Reject excessive repeated geometry and needless backtracking where detectable.
Prefer useful exploration gain within a reasonable route, not tiny gains from
zigzags. No available data establishes which neighborhood is “interesting.”

### Generated exploration walks: gated extension

Retain 15/30/60-minute round-trip and one-way walks as the longer-term outcome.
Do not promise them in the first Explore release. A bounded experiment may compose
walking legs through a few candidate waypoints; each leg must be provider-routed.
Check joined endpoints, repeated sections, detour budgets and unambiguous step
transitions. Independent legs may simply retrace the same roads and do not prove
that useful loops can be generated.

Before committing this feature, demonstrate that the bounded approach produces
useful loops in a street grid, an irregular neighborhood and a barrier/park setting
within a practical latency and request budget. Define a duration tolerance and
return-radius tolerance, then test them; show a duration estimate, not an exact
return-time guarantee. If it fails, retain simple suggestions and evaluate a routing
provider/graph separately. Do not build a street graph or switch providers implicitly.
Round trips can precede one-way endpoints if the evidence supports that choice.

## 8. Proposed architecture and external integrations

Keep SwiftUI plus the existing UIKit map. Suggested responsibilities are small,
testable boundaries, not mandated class names:

- **Search/directions adapter:** MapKit requests, cancellation, deadlines and errors;
  produces immutable route geometry, steps and provider estimates for local use.
- **Exploration scorer:** pure geometry plus a visited-cell snapshot; owns no Core
  Data objects and performs no writes. Reuse the grid definition, not renderer pixels.
- **Navigation session:** selection, progress, deviation and foreground lifecycle;
  observes location without stealing the recorder's single callback. If delivery
  needs fan-out, implement it at app ownership and regression-test recording first.
- **Map coordinator:** camera modes and ordered route overlays while retaining fog
  snapshot invalidation inputs and landmark behavior.

Bound expensive scoring work and keep it off the main actor when needed. Swift 5
mode and approachable concurrency do not make a plain async function a background
task. Use safe immutable inputs and explicit isolation; do not move Core Data
contexts between actors or add concurrency warnings.

The first releases require no persistent route, saved-place or session schema.
Later persistent user data needs a lightweight-migratable model and an explicit
backup compatibility decision. Do not store transient preview state as visited data.

External map handoff is deferred. Apple's
[Maps URLs](https://developer.apple.com/documentation/mapkit/unified-map-urls)
describe directions requests, and its
[navigation-app integration](https://developer.apple.com/documentation/mapkit/preparing-your-app-to-be-the-default-navigation-app)
includes waypoint inputs. Neither establishes preservation of Fog's selected
polyline and exploration objective. That limitation is an inference from the
documented interfaces, not a claim that all waypoint support is absent. If added,
test the exact walking route and supported OS versions. Otherwise offer only an
honestly labeled “Open destination in Maps” after a product decision. Google Maps,
a navigation SDK and route export are not initial dependencies.

## 9. Proposed delivery sequence and verification

These are independently reviewable scope recommendations. They are not estimates,
scheduled commitments or a newly authorized initiative.

| Slice | Deliverable | Evidence needed before proceeding |
| --- | --- | --- |
| A — Orientation | North-up heading, recenter and predictable follow/pan behavior | Interaction regressions, physical heading check and tracking/Study non-regression |
| B — Route feasibility and comparison | Search, one provider request, route overlays, new-cell estimates and useful alternatives | Candidate availability, honest one-route fallback, estimate fixtures, bounded latency and overlay readability; agree usefulness thresholds |
| C — Foreground guidance | Steps, stable progress, explicit recalculation and session end | Progress/deviation fixtures plus a focused physical walk including lock/unlock and loss of connectivity |
| D — Explore suggestions | A bounded set of routed suggestions using existing landmarks/resolved destinations | Candidate reachability, discovery semantics, limited requests, quality review and valid empty states |
| E — Generated walks | Timed round-trip walks, then one-way options if useful | Feasibility gate in section 7; agreed duration, endpoint and request-budget tolerances |

B may ship as route comparison before C; call it preview, not active navigation.
B and C can combine if review shows that is the smallest useful release. A must
not depend on proving E. The automatic pause/resume Study trial remains separate.

Every implementation slice requires a passing build and full XCTest suite under
the repository's [agent guide](../../AGENTS.md), plus regression tests appropriate
to the behavior. A compile-only result is not a test pass. Relevant checks include:

| Concern | Minimum verification |
| --- | --- |
| Persistence | Before/after assertions for search, selection, preview, cancel, reroute and arrival; previews cannot change cells, discovery dates or backup content |
| Recording | App-owned callback remains connected without a map; normal/Study Legacy/live/OFF cases, source changes, permissions and background/foreground transitions |
| Geometry | All-visited/all-new, repeated and long segments, boundaries, high latitude, wrap, invalid data, deduplication and detour-limit boundaries |
| Async work | Cancellation, stale generations, deadlines, throttling, network loss and stale current-location results |
| Guidance | Parallel roads, self-intersections, GPS jumps, sparse samples, uncertainty, sustained deviation and failed recalculation |
| Presentation | Fog/route ordering, today's highlight, pins and hit testing, zoom/pan/rotation behavior, safe areas, VoiceOver, text sizing and dark/light contrast |
| Physical behavior | Heading and walking usefulness on a phone; locked-screen exploration with normal authorization; loaded-route behavior offline |
| Resource use | No added background location/heading consumers or request loops; bounded memory/scoring on a large synthetic history; focused responsiveness and energy observation during a representative walk |

Use synthetic fixtures for deterministic tests and redact phone evidence. A short
physical observation can uncover regressions but does not establish a battery-saving
percentage or cross-device reliability. No new telemetry system is required for
this proposal. This documentation change itself makes no build, test or physical
verification claim about the proposed features.

## 10. Deferred scope and review questions

Keep heading-up, saved places/Collections, custom origins, arbitrary map destinations,
custom detour sliders, visited-landmark preferences, voice/lock-screen guidance,
automatic rerouting, external navigation and persistent post-walk summaries outside
the initial releases. A later summary needs real session accounting for time,
distance and actual new cells; the all-time visited set cannot reconstruct a walk.

Full offline maps/routing, extra POI sources, scenic/personalized routing, multi-stop
itineraries, cycling/driving and gamification remain separate proposals. Any wider
scope must preserve the same recording and data-integrity requirements.

The next reviewing agent should challenge these decisions explicitly:

1. Is orientation plus comparison of provider routes the right first product scope?
   Does the one-route fallback remain useful enough to ship?
2. Are new-cell counts understandable, and do the proposed detour ceilings and
   forthcoming usefulness thresholds match the owner's walking preferences?
3. Can the map show routes and heading clearly over fog while preserving pin behavior?
   Is a temporary street-detail preview necessary for guidance?
4. Is foreground-only, in-memory guidance a sufficient first release, with restart
   recovery and background turn prompts explicitly deferred?
5. Should Explore reveal undiscovered landmark names only after explicit opt-in,
   and are the proposed category/access filters adequate?
6. Are the suggested request bounds and MapKit-only approach viable before adding
   custom detours, territory-only destinations or timed loops?

Review against the cited code revision and the original brief. Identify factual
errors separately from product tradeoffs; propose concrete corrections. Agreement
with this document does not by itself demonstrate routing feasibility, approve
Study adoption or create a workspace initiative.
