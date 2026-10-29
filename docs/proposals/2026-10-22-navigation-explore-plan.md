# Fog of Walk — Navigation and Explore: Simple Plan

**Status:** Owner-directed plan. Step 1 is implemented; the owner revised its heading behavior on 2026-10-28. Later steps remain proposals.

**Date:** 2026-10-22.

**Source:** [Original product brief, preserved as supplied](2026-10-22-navigation-explore-original.md).
A longer engineering evaluation of that brief (Fog PR #5, closed unmerged) was
reviewed and replaced by this plan.

Lifecycle and next actions live in the workspace initiative
`fog-walking-companion`.

## Principle

Fog is a fun app for one walker. It should help with three things: where am I,
what's under the fog, and where could I go next. Apple Maps already does
turn-by-turn navigation well, so Fog should not rebuild it. Every feature here
should be simple to use, mostly local, and cheap to maintain.

## Ground rules for every step

- **Recording is untouched.** Nothing here adds visited cells or discovers
  landmarks. Only real location samples clear fog, through the existing
  `ExplorationRecorder` path. Don't change the tracking policy, add a location stream or do
  background work. The owner-approved step 1 revision permits a foreground-only
  heading stream for the blue dot. If a feature needs the current location,
  read `LocationService.currentLocation`.
- **Study.** New controls appear only when `LocationService.usesMapLocation` is
  true. In Study's automatic pause/resume or tracking-OFF modes, hide them.
- **Offline.** Steps 1–3 work without a network, apart from map tiles. Only
  step 4 needs Apple's services.
- **No new persistent data or settings** unless a step says so. No haptics.
- **Done** means tests for the new behavior and a passing build and full XCTest
  suite, as `AGENTS.md` requires. The owner checks heading and readability on a
  phone.

## Step 1 — Recenter and heading

**Owner revision, 2026-10-28:** the map must stay oriented as the user left it
when they turn; only the blue dot's direction pointer turns. This supersedes
the original heading-up behavior and the restriction against a separate
foreground heading stream for this step.

A recenter button always requests MapKit's `.follow` mode. Repeated taps never
enter `.followWithHeading`. Panning stops following; tapping the button resumes
it. A stats-region jump stays where it was sent. Manual two-finger rotation
remains available, with an adaptive compass to reset north. The landmark overlay
keeps its rotation-aware gesture transform.

Keep MapKit's native blue dot and add a small blue direction pointer driven by
a heading-only Core Location manager while the map is visible and active. The
pointer compensates for manual map rotation. Stop heading updates in the
background, when the map is removed, and whenever Study disables MapKit location.
No extra location requests, background heading work, recording or persisted
settings are introduced. Hide the pointer when heading is unavailable or invalid.
The owner checks physical heading and readability on a phone.

## Step 2 — Fog peek

The fog sits above map labels at 92% opacity, so street names in unexplored
areas can't be read. That's exactly where you're trying to decide where to walk.
Add a **Peek** toggle that lowers the fog's opacity enough to read streets and
labels. Explored areas stay clearly distinct. Peek turns off when the app goes
to the background. It is display-only: no setting, no data change.

## Step 3 — Nearby discoveries

Add an **Explore** button that opens a small sheet listing the nearest three to
five undiscovered landmarks within walking range (about 2 km). Each row shows the
category icon, distance and compass direction, for example "Museum · 650 m NE".
Names stay hidden until discovery, which keeps the "?" mystery. Tapping a row
centers the map on that landmark's hint. "Directions in Maps" hands a
destination-only walking request to Apple Maps for anyone who wants turn-by-turn.

Use the bundled landmark database through the same ingest path the map uses for
a visible region (`LandmarkStore.addLandmarks`, which sweeps already-walked
cells). Anything still undiscovered afterward really hasn't been discovered.
Leave out airports. An empty area shows "Nothing undiscovered nearby." This
step doesn't change the `showLandmarks` setting.

## Step 4 — Route preview (optional; decide after steps 1–3)

Search for a place (`MKLocalSearch`, submit only). Make one walking
`MKDirections` request with alternate routes allowed, and draw the route(s) above
the fog, each labelled with its time and **≈ N new cells**. N counts the grid
cells the route passes through, minus the cells already visited. The blue dot
moving along the line is the navigation. The route stays until dismissed.
"Open in Maps" is there for spoken directions. A landmark from step 3 can also
be a destination.

The new-cell count needs a small, pure `GridMath` function that walks each
polyline segment across cells. It must not skip cells and must stay bounded on
long routes, and it gets unit tests. Requests happen only when the user asks.
Visited history never leaves the device. Showing one route is a perfectly good
result, since Apple often returns only one walking route.

## Left out on purpose

| Dropped from the original brief | Why |
| --- | --- |
| In-app turn-by-turn, progress tracking, deviation and rerouting, arrival | Rebuilds Apple Maps; the most code and the most risk. A route line plus the blue dot covers walking. |
| Fastest / Balanced / Maximum Exploration with detour caps | Depends on alternatives Apple often doesn't return. Step 4 shows whatever comes back, with new-cell counts. |
| Generated 15/30/60-minute walks | Needs custom routing the app doesn't have. The fog plus Peek already shows where to go. |
| "Unexplored street" highlighting | The fog already is that highlight. Peek makes it readable. |
| Separate heading-up mode | Owner revision: only the blue dot's direction pointer turns; recenter stays in `.follow`. |
| Saved places, Collections, custom start points | These don't exist in Fog and aren't needed. |
| Faithful route hand-off to other map apps, voice, lock-screen prompts | Not possible faithfully, or out of scope. Destination-only hand-off is enough. |
| Post-walk summary, landmark preferences, gamification | Need walk sessions and settings that don't exist. Revisit only if missed. |

## Open questions for the owner

1. Peek opacity: about 40–50% fog is the starting guess. Tune it on a real walk.
2. Do you want step 4 at all after using steps 1–3?
