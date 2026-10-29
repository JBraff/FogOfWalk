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
  priorities. The 15,000-row regression checks the selected rows and cap. A probe-count
  assertion was subsequently removed because it could not detect an additional helper scan.
- `LandmarkPin` uses the generated memberwise initializer. Initial bitmap drawing is
  deferred from construction until delegate configuration with the map's traits;
  pre-window preparation reuses that appearance. The Dark Mode regression checks image
  identity across preparation and a genuine appearance change. Resolved map traits
  allow drawing before insertion; the remaining unresolved-trait case is covered below.

The initial implementation's 306-test result above is retained as history. The review-fix
full serial suite passed **312 tests, 0 failures, 0 skipped** on 2026-10-29, including the
new hosting, tap-target, appearance and isolation regressions. `xcresulttool` confirmed
these totals and no runtime warnings. The same full-suite command shown above was used.
An unsigned device Release build also passed, with only the three existing app Swift
warnings; its binary excludes the fixture controller and launch flag. Device smoothness
acceptance remains pending.

## Further review corrections (2026-10-29)

Seven additional comments were addressed:

- Discovered and selected pins use a priority strictly below the user location view;
  hints remain below discovered pins. The blue dot and heading pointer use `.max` for
  normal and selected priority. The SDK defines `.defaultSelected` as equal to `.max`,
  so pins use `.defaultUnselected` for both states instead. Regression assertions check
  strict priority ordering, rather than relying on those names.
- The circular hit target now uses a single `iconCenter` from the drawn pill geometry.
  The overlap fixture uses that property. The regression independently measures the
  pill's bitmap alpha and checks all four directions at 29 and 31 points, including
  the previously missed area above the icon.
- Explicit `.unspecified` traits no longer trigger a placeholder Light Mode draw.
  A resolved bitmap is reused through pre-window preparation; an unresolved new view
  draws on attachment. A real Dark Mode window regression verifies attachment produces
  an image that subsequent preparation and configuration reuse.
- Context change handling iterates each notification's `NSSet` directly, stopping at
  the first landmark, without allocating and hashing Swift object sets. A regression
  verifies cell recording and geocoder-style metadata writes leave the render generation
  unchanged while a landmark insertion advances it.
- The display probe counter and its assertion were removed. Selection/cap regressions
  remain; the single stored-row traversal is a code-review finding, not a runtime
  complexity claim proved by that counter.
- Hosted SwiftUI tests register teardown immediately, restore the previous key window,
  and wait on expectations for scene connection and displayed names. The fixed 400 ms
  settle and short attempt-count timeout were removed.

The updated full serial suite passed **314 tests, 0 failures, 0 skipped** on
2026-10-29. `xcresulttool` confirmed the totals and no runtime warnings. The unsigned
device Release build passed with only the same three app Swift warnings; the Debug
fixture controller and launch flag remain absent from its binary. The owner phone
comparison is still pending.

## MapKit lifecycle and test coverage corrections (2026-10-29)

Ten further comments prompted these corrections and stronger checks:

- The unresolved-trait regression now calls the production `viewFor` delegate on an
  unattached map, then lets a real `MKMapView` request and position that prepared view
  when attached to a Dark Mode scene. It covers fresh and reused views, confirms a
  real image/accessibility target appears, and checks the coordinate anchor within
  one point. This replaces the earlier plain-controller attachment test; that test
  did not establish MapKit sizing or anchoring behavior. The tested simulator correctly
  reanchors after deferred drawing, so no provisional bitmap was introduced.
- Reuse clears bounds, the centre offset and icon centre. A view awaiting its image
  remains disabled and outside accessibility. Attachment configures only views with
  no image; trait changes still refresh existing images through the registered handler.
- The user-location delegate reapplies normal and selected `.max` priority on every
  dequeue. A regression deliberately lowers both priorities on a recycled view and
  confirms the production delegate restores them.
- The fifty-pin geometry fixture saves/restores the previous key window and registers
  teardown immediately. It waits for all fifty rendered anchors to settle instead of
  sleeping 400 ms. Its settings and migration preferences are now memory-only.
- Hosted SwiftUI readiness requires an image and a stable parent-body count before
  the edit; the updated name also requires an image. The shared deadline-bounded wait
  expires its poller before the waiter and cancels/joins it before reporting a failure,
  preventing a late fulfillment from obscuring a timeout.
- Both rendering test suites now share the existing pixel-buffer and top-left pixel
  accessors in `RenderingTestHelpers.swift`. Pin tests measure the pill's opaque rows
  and columns independently, including a wide label; the icon centre comes from the
  same pill rectangle that is drawn.

The full serial suite passed again: **314 tests, 0 failures, 0 skipped**, with no
runtime warnings in `xcresulttool`. The unsigned device Release build passed with
only the three existing app Swift warnings and excludes the fixture controller and
launch flag. These checks cover simulator MapKit behavior; the physical phone
comparison remains pending.

## Attachment, interaction and test-helper corrections (2026-10-29)

A fourth review prompted these corrections:

- Attachment now also redraws a drawn view whose pin changed while it was detached;
  an unchanged view keeps its bitmap. An attached view whose supplied traits are
  unresolved uses its own appearance instead of waiting for an attachment that has
  already happened. Interaction and accessibility state is reapplied before the
  unchanged-bitmap check, so a later configure can restore it.
- New unit tests cover each change, plus behaviour that previously had no direct test:
  a reused deferred view keeps zero bounds until attachment draws it, and reattaching
  an unchanged view keeps its bitmap. The detach/reattach test holds the appearance
  fixed so only the attachment hook can redraw.
- The hosted observation test makes three separately displayed edits and fails if the
  parent rebuilds as many times as there were edits. A parent observing landmarks
  rebuilds at least once per edit; up to two unrelated SwiftUI passes are tolerated, so
  the 250 ms readiness quiet window no longer decides the result.
- `waitForLandmarkUI` is a single main-actor polling loop with no separate waiter, so
  nothing can fulfill late, and a timeout fails at the deadline with its description.
  The anchor calculation used by three placement checks is `anchorError(of:for:in:)`.
- `makeLandmarkCoordinator()` now defaults to memory-only settings; only the
  default-off test passes `defaults: .standard`. The redundant save/restore of the
  standard preference and the geometry fixture's no-op reset were removed.
- `HeadingUserLocationView.applyStackingPriority()` owns the user-location priority;
  its initializer and the dequeue path both call it.

Coverage limits stay as before. The real-MapKit deferred regression covers MapKit sizing
and anchoring a view the production delegate configured, fresh or hand-recycled; it
does not use MapKit's own reuse queue. Late-drawn anchoring has been observed only on
the simulator; the phone comparison should confirm that pins entering view are not
offset or briefly missing.

The full serial suite passed: **318 tests, 0 failures, 0 skipped**, with no runtime
warnings in `xcresulttool`. The unsigned device Release build passed with only the
three existing app Swift warnings and its binary excludes the fixture launch flag.
The physical phone comparison remains pending.

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
