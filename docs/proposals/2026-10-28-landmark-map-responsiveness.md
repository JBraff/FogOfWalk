# Landmark map responsiveness: investigation and options

**Status:** Proposal for review; no rendering approach is selected or implemented.
**Investigated:** 2026-10-28, probe baseline `e64caa21b93348cca2954614b589c35496675aae`.
**PR base:** `9e468e760f94f8de7fdfe653950e067945beacc2`; its heading-control changes
were reviewed before delivery. Landmark rendering and hit testing are unchanged.

## Recommendation

Prototype **B: native MapKit annotations with custom pin views** first. It removes
manual map tracking and is designed to keep point markers attached to coordinates
at a constant screen size. Use **A: repair the existing overlay** if a small,
interim fix is needed. Choose **C: retained custom pin layers** only if a native
annotation prototype cannot preserve the required presentation or interaction.

The reported delay, jumping and difficulty dragging have multiple causes. Two
small simulator probes confirm a touch-routing defect and a redraw coordinate
mismatch. They do **not** establish the contribution of each to the owner's phone
experience or measure frame time. A CPU-only optimization would leave these
correctness problems in place.

This PR supplies options and reproducible evidence for another agent to evaluate.
It changes documentation only. The [probe record](../evidence/landmark-rendering-investigation.md)
contains the exact diagnostic source, commands, results and limitations.

## What the code does

The map and `LandmarkOverlayView` are siblings. Fog is a native MapKit overlay;
pins are a single transparent UIKit drawing surface above the map.

| When | Work performed | Cost / consequence |
| --- | --- | --- |
| Continuous visible-region callback | Convert two reference coordinates and apply one transform to the entire pin layer | Constant-count application work; no explicit redraw or pin query in this callback |
| Region settles | Filter stored landmarks, build up to 300 pins, synchronously draw, reset transform, establish new reference | Main-thread burst; also the redraw-order defect below |
| Landmark count, discovery count or display setting changes | Refresh pin array and request drawing through `updateUIView` | May occur during an active gesture |
| Eligible settled region | Schedule SQLite query, Core Data inserts and discovery checks | Task inherits MainActor; runs even with pin display off |
| Touch near discovered pins | Project pins and return the sibling overlay from `hitTest` | Removes the map from that touch's view ancestry |

Sources at the inspected revision:
[map coordinator](https://github.com/JBraff/FogOfWalk/blob/e64caa21b93348cca2954614b589c35496675aae/FogOfWalk/FogOfWalk/Views/MapContainerView.swift#L239),
[pin view](https://github.com/JBraff/FogOfWalk/blob/e64caa21b93348cca2954614b589c35496675aae/FogOfWalk/FogOfWalk/Views/LandmarkOverlayView.swift#L65),
[display query](https://github.com/JBraff/FogOfWalk/blob/e64caa21b93348cca2954614b589c35496675aae/FogOfWalk/FogOfWalk/Models/LandmarkStore.swift#L423),
[ingest service](https://github.com/JBraff/FogOfWalk/blob/e64caa21b93348cca2954614b589c35496675aae/FogOfWalk/FogOfWalk/Services/LandmarkSearchService.swift#L56).
Some comments describe pin drawing as per-frame; the current continuous gesture
callback actually transforms an existing bitmap. Do not diagnose it as 300 label
redraws per gesture frame without a trace.

## Findings and confidence

### 1. Discovered pins can prevent a drag from reaching the map — confirmed routing

`LandmarkOverlayView.hitTest` returns itself within 30 points of a discovered
pin's icon center, even when the eventual gesture will be a drag. Its only
recognizer is a tap recognizer. Because the map is a sibling, the map's gesture
recognizers do not receive touches hit-tested into this overlay. A failed tap
recognizer does not retarget the touch to the sibling map.

The simulator probe confirms that the same starting point hits the overlay for
a discovered pin and the map subtree for an undiscovered hint. This is a direct
explanation for map areas that feel unresponsive when many discovered pins are
visible. It does not explain a hints-only map stuttering.

Apple documents recognizer scope in
[`UIView.addGestureRecognizer`](https://developer.apple.com/documentation/uikit/uiview/addgesturerecognizer(_:)):
touches belong to the attached view and its descendants. Changing
`cancelsTouchesInView` or simultaneous-recognition policy alone cannot fix the
sibling hit-test ownership.

### 2. Settle redraw uses a transform that is immediately discarded — confirmed mechanism

`regionDidChangeAnimated` currently performs this sequence:

1. Refresh pins and call `layer.displayIfNeeded()`.
2. Reset the pin layer's transform to identity.
3. Establish the next gesture's reference coordinates.

But `draw` projects each coordinate **into the transformed overlay** with
`mapView.convert(coordinate, toPointTo: self)`. UIKit compensates for the current
transform while computing that local point. Resetting the transform afterwards
leaves the new bitmap in the wrong coordinate basis.

In the simulator probe, the map coordinate projects to x=200 and the overlay has
a +80-point translation. The drawing conversion returns x=120. After resetting
the transform, that drawn anchor is displayed at x=120, 80 points off its map
position. Resetting **before** drawing returns the anchor to x=200. The probe
recreates the production ordering with the real view and MapKit conversion; it
does not drive an end-to-end finger gesture through the coordinator.

A repair must also coordinate redraws requested during a gesture by ingest,
discovery, settings or layout changes. Swapping only the two settle operations
is not a complete lifecycle solution.

### 3. Whole-bitmap transforms resize and rotate the icons — established by code

`gestureTransform` scales and rotates the entire layer, including icons and name
text. A 2x map zoom doubles their displayed size; a 90-degree turn rotates their
text. The settled redraw returns the glyphs to their ordinary size/orientation.
Even perfect transform arithmetic cannot provide constant-size, upright markers
with that representation. The two-reference-point similarity transform also
cannot generally represent a changing pitched camera's perspective.

The current main branch uses a follow-only recenter control and a heading pointer
around the blue dot; turning the phone no longer rotates the map automatically.
Manual rotation still exercises this pin transform. Preserve that newer behavior.

The existing successive-rotation integration test protects the earlier fix in
`c524b1a` (reference coordinates measured in the untransformed map). That fix is
already present. Do not regress it or mistake this proposal for the same fix.

### 4. New pins wait for a refresh — established by code

The candidate array is selected for the last refreshed region, and drawing is
limited to the overlay bitmap's bounds. Continuous map motion transforms those
pixels; it does not acquire newly visible pins. Newly exposed areas can stay
empty until `regionDidChangeAnimated`, even when their landmarks are already
stored. Previously unseen data may wait longer: ingest runs only at settle and
is allowed when **30 seconds OR 500 meters** have elapsed since the prior query.
A zoom-only change within that budget can therefore delay ingest too.

Keep these separate: display refresh of already-known pins can be improved
without changing ingest policy. An option that changes when new data is ingested
would require a separate scope decision.

### 5. Main-thread bursts may compound the problem — unmeasured hypothesis

`landmarks(in:)` scans **all N stored landmarks**, then caps the returned pins at
300. The cap bounds drawing and hit testing, not this O(N) selection. Historical
stores may contain most of the roughly 15,000 bundled entries. Each redraw
projects up to K=300 coordinates; discovered pins additionally measure and draw
labels. SF Symbol images are already cached.

The main-actor ingest task performs a bounded SQLite read, inserts/saves and
possibly a second save for discoveries. Cancellation does not interrupt the
synchronous SQLite call. The comment claiming this fits well under a frame is
not device timing evidence. Ingest still runs with display off, so compare warm
and newly ingested regions before attributing all extra cost to pin drawing.

There is no measured FPS, hitch rate, energy improvement or proven implicit
animation delay in this investigation. Do not add a display link, lower the pin
cap, or move managed objects to a detached task on that assumption.

## Options

| Option | What it addresses | Main limitations / risks | Relative scope |
| --- | --- | --- | --- |
| **A. Repair existing bitmap overlay** | Blocked drags, incorrect settle position, inconsistent redraw/reference updates | Whole-image resizing/rotation and late edge content remain unless architecture expands | Smallest; useful interim repair |
| **B. Custom native annotations — preferred prototype** | Map-attached motion, constant-size upright pins, native view reuse, removes sibling interception and manual transform lifecycle | Must verify fog stacking, collisions, selection, appearance and bounded candidate refresh | Medium; replaces pin presentation |
| **C. Retained custom pin layers** | Independent pin positions with constant-size contents, explicit draw and hit-test control | Own frame scheduling, projection, culling, accessibility and gesture integration; main-thread cost scales with K | Largest ongoing maintenance |

### A. Repair the current overlay

Make the visual overlay noninteractive and recognize landmark taps on the map
(or a shared ancestor with explicit control filtering). A tap must preserve
panning, pinching, rotation and double-tap zoom; test actual drags starting over
icons. Look up discovered pins using positions in the same coordinate space as
the event. Do not forward synthetic touches to MapKit's private recognizers.

Centralize a full refresh: disable actions, reset to identity, update candidates,
draw in the untransformed basis, and establish matching reference coordinates.
Use the same operation for settle, data changes and layout changes. Keep the
bitmap's reference camera and its actual drawing synchronized.

This is a plausible small repair for usability. It cannot by itself meet the
constant-size/upright-pin requirement or ensure fresh edge content during motion.
Adding inverse transforms per glyph or repeated per-frame full redraws would
substantially change this option's cost and complexity.

### B. Replace the sibling pin canvas with custom MapKit annotations

Use lightweight annotation objects keyed by Wikidata identifier, derived from
`LandmarkPin` values. Reusable custom `MKAnnotationView` instances preserve the
existing discovered icon, pill and label, and undiscovered question-mark hint.
Use native annotation selection for discovered details and keep hints inert.
Preserve the current `MKUserLocation` branch returning `HeadingUserLocationView`
in `viewFor annotation`, and add a separate landmark branch. Retain
`HeadingMapView`, its heading-marker updates, the follow-only recenter control,
Study map-location gating and the fog overlay. Returning `nil` for user location
would regress the custom direction pointer added after the probe baseline.

Diff annotation identities and update changed presentation in place. Do not
remove/re-add all annotations at every camera callback. Preload a modest buffer
of **already ingested** candidates and refresh as the viewport approaches its
edge, coalescing selection work rather than scanning Core Data every frame.
Keep at most 300 installed landmark annotations, with visible discovered pins
prioritized before hints and buffer-only candidates. Keep membership stable
where possible to avoid replacement churn; refresh on discovery and toggles.
The existing >1-degree zoom gate still applies to the visible region.

A buffer does not guarantee arbitrarily fast pans show unseen pins; refill
latency and dense regions must be measured. Native reuse also does not fix an
O(N) candidate query automatically. Profile before adding a separate render
index; do not reuse the undiscovered-only discovery index as if it contained all
pins.

Apple's [annotation guidance](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/AnnotatingMaps/AnnotatingMaps.html)
describes coordinate attachment and fixed marker size/orientation through camera
changes. This makes B the best architectural fit, not a measured performance
win yet.

The prototype must demonstrate visibility over the actual `.aboveLabels` fog,
including during camera changes. Configure collision/display priority deliberately:
MapKit's automatic hiding must not silently remove pins that the current canvas
would display. Do not enable clustering or switch to standard balloon markers.
Check dark/light appearance, label offsets, overlapping selections, repeated taps,
no drop animations, and map controls above content. Reject B if these require
private MapKit view hierarchy manipulation.

### C. Keep a sibling overlay, but use retained per-pin layers or views

Keep the container untransformed. Cache each pin's icon/label contents and move
only its anchor using `MKMapView.convert` into the untransformed container. K
projections and K position updates per visual frame replace full bitmap drawing;
contents stay constant-size and upright under pan, zoom, rotation and pitch.
Reuse pins by identifier, disable implicit position animations, and invalidate
cached appearance when traits, name or discovery state change.

Coalesce camera callbacks to at most one update per display frame. Start with
delegate-driven updates; add a common-mode display link only if measurements
show it is needed, and stop it when idle, hidden or backgrounded. Candidate
selection uses the same capped buffered policy as B and never runs as part of
every projection update. Cache screen hit regions for a map-attached tap recognizer.

This provides the most presentation control but retains custom synchronization,
gesture and accessibility responsibilities. With 300 pins it may spend more CPU
on continuous projection than today's two-point transform. Measure before
choosing it over B.

### Approaches not recommended as the first fix

Moving icons into the fog tile renderer couples interactive, screen-sized content
to geographic tiles, background rendering and tile seams. It still needs a
separate hit-test/accessibility path. Hiding pins during gestures, reducing the
300 cap or enabling clustering changes the requested behavior. Moving database
work off-main might reduce measured ingest hitches, but cannot repair the touch
routing or coordinate-basis errors; it also needs queue-owned persistence and
immutable values rather than cross-actor managed objects.

## Evaluation contract for the reviewing agent

First check the diagnosis against the pinned source and rerun the two isolated
probes. They intentionally assert the existing bad behavior; permanent regression
tests for an implementation must instead assert the desired behavior. Review the
native prototype's fog layering and interaction before approving a migration.

Compare baseline, A and B with the same synthetic data and camera paths; test C
only if B fails an explicit requirement. Use Release on a physical phone for
responsiveness evidence. Record device, OS, build, refresh rate and data counts.
Keep personal location traces and raw device logs out of commits.

| Dimension | Required cases |
| --- | --- |
| Density | 0, 50 and 300 visible pins; hints-only, discovered-only and mixed; approximately 15,000 stored rows with few visible |
| Input | Drag beginning on a pin and on empty map; continuous and repeated pans; pinch; rotation; pitched map; follow while turning the phone; animated stats navigation |
| Refresh | Cached pin entering from each edge during motion; ingest/discovery during motion; >1-degree zoom boundary; toggle off/on; portrait/landscape and appearance changes |
| Compatibility | Question-mark hints inert; discovered details open on tap; no accidental details after a drag; pins above fog; controls usable; default off; cap preserved; both app identities |

Instrument candidate selection, draw/layout/projection, ingest/save and camera
callbacks separately with signposts and Time Profiler/Animation Hitches. Report
p50/p95 work durations, frame hitches, callback counts, query counts and settled
redraw time. Measure warm cached regions separately from cold ingest and compare
landmarks off/on. For 60 Hz and 120 Hz, the **whole frame** budgets are 16.7 ms and
8.3 ms; these are context, not a promised pin-work budget or measured result.

Proposed correctness checks: no lost drag from a pin; anchor error within 1 point
in controlled flat-map integration cases before/after settle; no systematic
anchor or size jump; constant glyph dimensions through zoom; already-cached pins
appear during sustained movement after bounded refill. Capture refill latency
explicitly rather than declaring it instantaneous. Physical follow-mode checking
must preserve normal tracking and Study isolation and remains owner-coordinated.

The existing tests cover transform math, successive rotations, visibility gating,
cap/discovered priority and static pin drawing. They do not verify settle drawing
under a nonidentity transform, actual drag routing, fixed glyph size, continuous
viewport refill or frame budgets. Add those relevant regressions for the selected
implementation and require a successful build and full XCTest suite. Simulator
success alone does not establish smoothness on the owner's phone.
