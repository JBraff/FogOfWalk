# Native landmark annotation verification

**Date:** 2026-10-28; review fixes verified 2026-10-29. **Base:** `b517b06` (merged responsiveness proposal).
**Environment:** Xcode 27.1, iPhone 18 Pro simulator, iOS 27.0.

The [reviewed proposal](../proposals/2026-10-28-landmark-map-responsiveness.md)
fits the observed defects: native MapKit annotation positioning removes the
sibling touch surface and the bitmap's gesture scaling, rotation and settle
reset. No additional design decision was needed to implement option B.

## Implemented behavior

Each landmark has a lightweight annotation keyed by Wikidata ID and a reusable
custom view. Each view renders the existing pill/icon/name or dim question mark
into its own fixed-size image on data, reuse or appearance changes. An unavailable
category symbol falls back to the existing generic map-pin icon. Required display
priority preserves overlapping pins; clustering is disabled. Hints are disabled;
discovered selections open details and deselect for repeated taps. Discovery updates
annotation data, title notifications, enabled state and existing view imagery in place.

At settle, the existing visible-region query wins before a 2x-span buffer fills
remaining slots, with discovered buffer candidates preferred when capacity is
limited. Both the returned set and installed annotations are capped at 300.
Padding reads only stored rows and does not expand ingest. The >1-degree gate
uses the visible region. Selection scans the stored array once into bounded groups. No mid-gesture
refill, new spatial index, background persistence or location-policy change was added.

A `LandmarkMapView` child reads a render generation and the display setting and passes
explicit inputs, so count-neutral edits refresh the map without invalidating the root
screen or depending on a newly walked cell. Fog rendering,
heading updates, recentering, location recording and Study gating retain their
existing paths. `AGENTS.md` and `docs/SYSTEM.md` describe the new rendering path.

## Software verification

The full suite passed: **306 tests, 0 failures, 0 skipped**. `xcresulttool get
test-results summary` confirmed the totals and reported no runtime warnings.

```sh
xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -parallel-testing-enabled NO -collect-test-diagnostics never test
```

The app and tests built successfully. An unsigned device Release build also passed:

```sh
xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

The Release binary does not contain the Debug fixture's launch argument or
controller. Only the three previously documented app Swift concurrency warnings
remain. Test-source concurrency warnings remain pre-existing.

Coverage includes:

- Existing visible selection under the cap with 15,000 stored rows, visible hints
  ahead of buffer discoveries, 0/50/300 fixtures, the installed 300 cap, padding
  boundaries and the visible-span gate.
- Annotation identity across refresh, removal, reuse, fallback imagery, offscreen
  discovery and in-place visible hint discovery.
- Fifty real MapKit annotation anchors within 1 point through controlled settled
  pan, zoom and successive rotations, with unchanged glyph bounds and orientation.
- Real XCUITest taps, repeated taps, a drag beginning on a discovered icon that
  pans without selecting, an inert hint, discovery becoming tappable, a buffered
  pin entering at the edge, pinch and rotation. The passing test retains a
  screenshot showing the native pin above the fog. The fixture uses synthetic
  coordinates and an in-memory store and is compiled only in Debug.
- Existing recording, heading, recenter control and normal/Study isolation tests.

The old overlay/transform tests were replaced with regressions for the native
path. The gesture tests wait for MapKit's deferred selection and deceleration;
an initial XCUITest idle report can precede either. The fixture samples geometry
until settle without changing the map or pin positions.

## Review corrections (2026-10-29)

All ten review comments were evaluated and addressed:

- Discovered pins retain the original 30-point circular icon hit target, including
  outside a short image's bounds. Hints ignore all touches and have lower z priority;
  wide labels do not intercept neighbouring taps.
- Fixture launch bypasses production service construction, store opening, recorder
  wiring and location startup. Settings and landmark migration use memory-only defaults.
  The launch-gate regression proves the production factory is not invoked; defaults
  coverage proves all three standard preference keys remain untouched.
- The UI regression now taps outside a short "Zoo" image while a hint overlaps that
  target, verifies repeated selection and drags, and waits an inverted four-second
  expectation to rule out a deferred callback from an inert hint.
- Render generation observes landmark context changes and cache reloads. A count-neutral
  name/category/coordinate edit refreshes an existing annotation. A hosted SwiftUI
  regression proves the visible name changes without moving the region or rebuilding
  the parent view.
- A single bounded candidate scan preserves the legacy visible selection and buffer
  priorities. The 15,000-row regression checks each stored row is examined once.
- `LandmarkPin` uses the generated memberwise initializer. Initial bitmap drawing is
  deferred from construction until delegate configuration with the map's traits;
  pre-window preparation reuses that appearance. The Dark Mode regression checks image
  identity across preparation and a genuine appearance change. Waiting for `window`
  alone would risk returning an empty, zero-sized annotation to MapKit, so the delegate
  supplies its destination traits before insertion instead.

The initial implementation's 306-test result above is retained as history. The review-fix
full serial suite passed **312 tests, 0 failures, 0 skipped** on 2026-10-29, including the
new hosting, tap-target, appearance and isolation regressions. `xcresulttool` confirmed
these totals and no runtime warnings. The same full-suite command shown above was used.
An unsigned device Release build also passed, with only the three existing app Swift
warnings; its binary excludes the fixture controller and launch flag. Device smoothness
acceptance remains pending.

## Earlier heading/runtime failure

Before editing landmark code, the focused heading baseline reproduced a Swift
runtime abort under parallel execution. A serial baseline accepted the cached
heading/queued-session test but crashed in
`testSceneGeometryNotificationUpdatesOrientationWithoutLayout`: hosted tests
started before SwiftUI connected a window scene, and that test force-unwrapped
an empty scene list. The test now yields for scene connection and uses
`XCTUnwrap`; its heading assertions and production heading code are unchanged.
The final full serial suite includes all seven heading tests and passes.
The separate parallel XCTest runtime abort is not claimed to be fixed.

Automatic crash-diagnostic collection stalled early failed runs on this Xcode/runtime;
the completed full run disabled that collection. Result bundles, synthetic
screenshots and logs remain outside Git. No raw location traces were committed.

## Remaining physical comparison

One owner-coordinated Release phone comparison is still required before claiming
physical smoothness or completing acceptance. In the same dense area with pins on,
compare the previous build with this implementation: pan and release (including
drags starting on pins), pinch, rotate and follow. Check fixed glyph size, correct
anchors, no settle pop, edge entry, pins above fog, repeated detail taps and usable
recenter/compass controls. Preserve location recording throughout; do not uninstall
the Study app. No phone install or trial was performed for this change.

Padding has finite coverage and spare capacity: a sufficiently long gesture or a
visible set already filling the 300 cap can exhaust the buffer. If the phone check
shows an edge-entry gap, add a narrowly justified refill. Profile only if a hitch
remains. No measured device speedup or battery claim is made by these software tests.
