# Landmark map responsiveness: investigation and options

**Status:** Reviewed proposal; no implementation is included.
**Source:** Probes on `e64caa2`; landmark paths also checked on `9e468e7`.

## Recommendation

Build one prototype using **custom native MapKit annotations (B)**. Keep the
current pin appearance and behavior, but let MapKit position them. Do not build
an interim overlay repair or competing renderers unless that prototype fails a
specific requirement.

The investigation found correctness defects that explain blocked drags and
jumping pins. A performance study is not needed to choose the first fix. Keep
focused regression tests, do one phone comparison, and profile only if a hitch
remains. This simplifies the proposal following the
[independent review](https://github.com/JBraff/FogOfWalk/pull/9#pullrequestreview-5692082021).

## What is wrong

The pins are drawn into a single UIKit view above the map. During map movement,
the app transforms that entire image, then redraws it when movement settles.

- **Discovered pins intercept map touches.** The overlay's `hitTest` returns
  itself near a discovered pin. It is a sibling of the map, so a drag starting
  there does not reach the map's gesture recognizers. The simulator probe
  confirmed the routing; hints pass touches through.
- **Pins can snap back by the full pan distance.** The settle callback draws
  coordinates into the still-transformed overlay, then removes the transform.
  For a flat pan with an unchanged reference image, that puts anchors back at
  their pre-gesture screen positions until another redraw. The probe reproduced
  an 80-point error for an 80-point translation. Drawing after the identity reset
  removed that isolated error. Data-driven redraws during a gesture also need
  coordinated handling, so repairing this is more than swapping two lines.
- **The image itself scales and rotates.** Icons and labels change size and
  orientation during a gesture, then return to normal at the settled redraw.
- **Newly exposed pins wait for a refresh.** Moving the old image cannot display
  pins outside its original candidates and drawing bounds.

These findings do not establish CPU cost as the cause. The continuous landmark
callback transforms one layer; it does not explicitly redraw 300 labels every
frame. Selection scans all stored landmarks before applying the 300-pin cap,
and ingest runs on the main actor, but neither has been timed on the phone.

Sources: [hit testing and drawing](https://github.com/JBraff/FogOfWalk/blob/9e468e760f94f8de7fdfe653950e067945beacc2/FogOfWalk/FogOfWalk/Views/LandmarkOverlayView.swift),
[gesture and settle callbacks](https://github.com/JBraff/FogOfWalk/blob/9e468e760f94f8de7fdfe653950e067945beacc2/FogOfWalk/FogOfWalk/Views/MapContainerView.swift),
[selection](https://github.com/JBraff/FogOfWalk/blob/9e468e760f94f8de7fdfe653950e067945beacc2/FogOfWalk/FogOfWalk/Models/LandmarkStore.swift).
Exact probe source and verification limits remain in the
[evidence record](../evidence/landmark-rendering-investigation.md).

## Options

| Option | Benefit | When to use it |
| --- | --- | --- |
| A. Repair the existing bitmap overlay | Fix touch routing and redraw/reference coordination | Only if B stalls and an interim fix is needed; much of this work would be discarded by B, and glyph scaling remains |
| **B. Custom native annotations** | Remove the sibling touch interception and manual bitmap tracking; keep custom pin appearance | **First prototype** |
| C. Retained custom pin layers | Position each constant-size pin independently | Fallback if B cannot meet a specific requirement; more custom projection and interaction code |

Use the existing `MKMapView`, not a migration to SwiftUI `Map` + `Annotation`:
the fog relies on its custom `MKOverlayRenderer`, which this change should retain.
A hybrid of annotation pins and a separate hint overlay is another possible
fallback if annotation count proves problematic, but it would reintroduce
scaling/rotation for hints and need an explicit behavior tradeoff.

## The smallest useful B prototype

1. Represent landmarks as lightweight annotations keyed by Wikidata ID. Reuse
   custom `MKAnnotationView`s with the existing icon, pill, name and hint styling.
   Set hint views' `isEnabled = false`. Open details for discovered pins and
   deselect afterwards so repeated taps work. Set `displayPriority = .required`
   explicitly to preserve visible pins; do not introduce clustering. When a hint
   becomes discovered, update its annotation data and existing view's styling
   and `isEnabled` in place (or replace only that annotation); configure reused
   views from the current data so offscreen discoveries update correctly too.
2. At settle, select already-ingested landmarks in a padded region, initially
   **2x the visible span**, and diff by ID rather than removing/readding all pins.
   Keep at most 300 landmark annotations, selected in this order: **visible
   discovered pins, visible hints, buffer-only discovered pins, buffer-only hints**.
   Buffer candidates only fill capacity left after visible candidates. Preserve
   today's `landmarks(in:)` selection within the visible region. Refresh on relevant
   data changes and toggles too. Keep the >1-degree gate based on the visible
   region, and keep display off by default.
3. Start without mid-gesture refill, a display link, a new spatial index or
   background persistence work. Add refill only if the edge-entry check reveals
   gaps. Padding only selects existing data: it must not enlarge or bypass the
   current ingest request. The cap bounds the returned candidates and installed
   annotations; it does **not** eliminate the existing all-landmarks scan.
4. Preserve the existing `MKUserLocation` delegate branch returning
   `HeadingUserLocationView`, `HeadingMapView` heading updates, follow-only
   recenter control, Study gating and fog renderer. Check fog stacking and pin
   overlap in the prototype as ordinary visual checks.

Apple's [annotation guidance](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/AnnotatingMaps/AnnotatingMaps.html)
describes map-attached markers with fixed size/orientation and reusable views.
That is the reason for choosing this prototype; no speedup has been measured.

## Validation

- **Keep automated correctness tests:** a drag starting on a pin pans the map;
  a discovered-pin tap opens details, including repeated taps, while a drag does
  not; hints are inert; anchors stay within 1 point across settle in controlled
  flat-map cases; glyph dimensions stay constant through zoom; the 300 cap holds
  and visible selection matches today's `landmarks(in:)` result even
  with many buffer-only discoveries; an onscreen hint becomes tappable with
  discovered styling when discovered; the heading user-location view, display toggle
  and Study isolation remain intact. Use interaction tests for actual gestures,
  not just direct calls to `hitTest`. Keep 0/50/300 visible pins and roughly
  15,000 stored rows as fixtures where relevant, not a profiling matrix.
- **Build and run the full XCTest suite.** The evidence record distinguishes
  the earlier 303-test pass from the newer-base heading-test/runtime failure.
  That failure needs separate diagnosis; it is not a landmark-rendering finding.
- **One Release phone comparison, baseline versus B:** in a dense area, pan,
  pinch, rotate and follow with pins on. Confirm no pop at settle, fixed-size
  pins, pins entering at edges, pins above fog, working taps and usable controls.
  The baseline pan-and-release check can quickly confirm whether the reported
  jump is the predicted snap back. Preserve location recording throughout.
- **Profile only if that check still shows a hitch.** Use Instruments on that
  case. Do not require A/B/C implementations, multi-device timing runs, signpost
  infrastructure or percentile reports to approve this correctness fix.
