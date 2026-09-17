# Adaptive Location Tracking Implementation Plan

**Status:** Proposed — no implementation changes have been made.

## Background

Fog of Walk records exploration in 50 m grid cells, so it needs reliable background
location updates at much finer granularity than iOS's low-power location services
normally provide. The current configuration deliberately prioritizes continuity:

- standard location updates with `kCLLocationAccuracyNearestTenMeters`;
- a 15 m distance filter;
- `pausesLocationUpdatesAutomatically = false`;
- background location updates enabled with Always authorization; and
- significant-change monitoring running as a relaunch/recovery safety net.

This configuration fixed a prior failure mode: with automatic pausing enabled and
`activityType = .fitness`, iOS could pause standard updates while the device was
stationary and fail to resume them reliably in the background. Keeping precise
standard location active is therefore intentional, but it also keeps the location
hardware active much more often and increases battery use.

Significant-change monitoring is not an acceptable replacement for this app's
primary tracker. It is low power, but delivers only after a substantial,
system-determined change in location. A person starting a walk—or driving from a
parking spot—could travel hundreds of metres before the app is woken. Because the
app presently unlocks only the cells represented by actual location samples (it
does not infer a route between samples), that would leave real gaps in the fog.

The proposed compromise is **adaptive standard tracking**: preserve precise,
continuous tracking whenever the user might be entering new territory, but ask for
less precise, less frequent standard updates only when the user is well inside a
verified fully explored area. Requested accuracy affects the radios Core Location
may use and therefore power consumption; the economical profile is intended to let
iOS avoid sustained GPS use without losing the ability to return to precise tracking
before unexplored cells are reached.

References:

- [Apple: Getting the current location of a device](https://developer.apple.com/documentation/CoreLocation/getting-the-current-location-of-a-device)
- [Apple: `pausesLocationUpdatesAutomatically`](https://developer.apple.com/documentation/corelocation/cllocationmanager/pauseslocationupdatesautomatically)

## Goal

Reduce battery use during repeat travel through fully explored areas without
reintroducing the prior background-tracking stop or causing obvious gaps in newly
explored territory. Core Location delivery is best-effort, so gap-free tracking is
an empirically validated target rather than a hard guarantee.

## Non-goals

- Replacing standard tracking with significant-change-only monitoring.
- Re-enabling automatic location pausing.
- Marking cells as visited from a coarse, low-confidence location sample.
- Interpolating or inventing a path between sparse samples.
- Changing location authorization, the background-location indicator, or the
  foreground re-arm behavior.

## Product and correctness invariants

1. **Request precision by default.** The runtime profile starts precise and stays
   precise unless the app has positively established that economical mode is safe.
   This says nothing about the quality of a delivered sample, which must always be
   validated independently.
2. **Trust the sample, not the configured profile.** `desiredAccuracy` is a
   best-effort request, and standard and significant-change updates share the same
   delegate callback. A sample may unlock a cell only when its coordinate,
   horizontal accuracy, and timestamp pass an explicit validator, regardless of
   the active tracking profile.
3. **No new cells from economical or untrusted samples.** A coarse sample can help
   prove the user is still in known territory, but cannot unlock a new 50 m cell.
   If it could be in new territory, the app switches to precise mode and waits for
   a fresh sample that passes the precise validator.
4. **Conservative coverage envelope.** "Nearby explored" must mean that every 50 m
   cell in a large protective envelope is already in `visitedCellsCache`, not merely
   that a route or a majority of cells has been walked.
5. **Always fail toward precision.** A missing or excessive location accuracy,
   stale or out-of-order timestamp, stale/invalid speed, invalid coordinate,
   uncertain coverage result, expired safety proof, or proximity to the envelope's
   frontier selects precise mode and cannot mutate exploration history.
6. **Retain the proven reliability safeguards.** Standard tracking keeps
   `pausesLocationUpdatesAutomatically = false`; significant-change monitoring
   remains active; foreground activation continues to re-arm tracking.
7. **Continuous remains the default.** Adaptive is an explicitly experimental,
   opt-in setting until the small tester group has established that it behaves well
   on physical devices. No quantified battery-saving claim is required for the
   initial release.

## Proposed architecture

### 1. Sample validator and coverage classifier

Create a pure `LocationSampleValidator` used by both Continuous and Adaptive modes.
It must reject invalid/non-finite coordinates, negative or non-finite horizontal
accuracy, accuracy above an explicit recording threshold, stale timestamps, and
out-of-order samples. `LocationService` should expose Core Location's
`accuracyAuthorization` so reduced-accuracy authorization can be observed and
tested, but the delivered sample's measured accuracy remains the final gate.

After changing from economical to precise, record the transition time and reject
any queued or cached location whose timestamp predates that transition. Requesting
the precise profile does not by itself make the next callback precise.

Create a pure, unit-testable grid helper—tentatively `ExploredAreaClassifier`—that
receives a coordinate, `Set<CellID>`, horizontal accuracy, and the applicable
safety margin. It answers whether the full coverage envelope around that coordinate
has been visited.

The helper should use the existing 50 m `GridMath` coordinate system and its
latitude-aware bounding-box math. It should enumerate only the small local box and
perform O(1) membership lookups in `visitedCellsCache`; it must not query Core Data
from the location callback. It must cap enumeration and fail to precision if the
box is too large. The current `GridMath.cellBox` clamps longitude scaling at 85°,
which can under-cover a true metre radius nearer the poles; the classifier must
either use safe wrap-aware geometry or refuse economical mode outside a documented
supported latitude. Antimeridian, polar, and invalid-input behavior must be tested.

The envelope is intentionally stricter than the current sample position. It must
cover at least:

- coarse-profile horizontal accuracy;
- the coarse profile's distance filter;
- a reacquisition allowance before a newly-requested precise GPS fix arrives; and
- a speed-based travel allowance when the last trusted precise location indicates
  walking, cycling, or driving.

This gives the app time to detect an approaching unexplored boundary, request
precision, and obtain a trustworthy sample before the user reaches it.

### 2. Tracking profiles

Keep one `CLLocationManager` and switch its configuration between explicit profiles.

| Profile | Desired accuracy | Distance filter | Permitted effect |
|---|---:|---:|---|
| `precise` | `kCLLocationAccuracyNearestTenMeters` | 15 m | May unlock cells and trigger fog/landmark work. |
| `economical` | initial candidate: `kCLLocationAccuracyHundredMeters` | initial candidate: 100 m | May validate continued presence in known territory; may not unlock a new cell. |

The exact economical values and envelope dimensions are initial candidates, not
promises. They must be set from physical-device coverage and energy trials. A larger
distance filter by itself mostly reduces application wakeups; the meaningful energy
opportunity is allowing a lower requested accuracy when exact GPS-level position is
irrelevant.

`LocationService` should expose the current runtime profile and one idempotent method
to apply a profile. The user's persisted preference and the runtime profile are
separate: selecting Adaptive permits economical mode but does not enter it until a
fresh, trusted precise sample proves it safe.

Startup, authorization changes, and foreground recovery re-arms must reset the
runtime profile to `precise` before starting updates. An economical decision based
on an old position is no longer valid after a delivery gap. Both profiles retain
background updates, significant-change monitoring, and disabled automatic pausing.

### 3. Hysteresis and speed handling

Use separate entry and exit thresholds to prevent oscillation at an explored edge:

- Enter `economical` only when a **precise** location is deep inside a fully visited
  envelope.
- Leave `economical` as soon as a coarse update is no longer safely inside a
  smaller retained envelope, before any cell is added.
- Scale the entry envelope up for higher reported speeds and include speed accuracy.
  A last-observed speed does not bound later acceleration, so policy must include a
  conservative maximum-speed allowance or remain precise. If speed is unknown,
  negative, stale, or too high for the currently proven envelope, remain precise.
- Treat the proof that justified economical mode as expiring state. A long gap in
  delivery cannot be made safe by the distance filter, which is not a guaranteed
  upper bound on update latency; any expired proof forces precise mode.

The first implementation should be deliberately conservative. A reasonable trial
matrix is a walking-sized envelope of several hundred metres and a substantially
larger driving envelope (potentially around a kilometre), refined only after real
coverage testing. A user moving quickly through a small explored patch should stay
in `precise`; saving battery is never worth a likely frontier gap.

### 4. Location-update flow

The coordinator remains the owner of exploration persistence and rendering, but a
pure state machine owns validation and profile decisions. The coordinator only
executes the returned action. The decision happens before it records a cell:

```text
location update
  ├─ invalid, stale, out-of-order, or insufficiently accurate
  │    └─ do not record; request/remain precise
  ├─ Continuous preference + trusted precise sample
  │    └─ record the 50 m cell; remain precise
  └─ Adaptive preference
       ├─ precise profile + trusted precise sample
       │    ├─ record the 50 m cell
       │    └─ enter economical only if a conservative envelope is proven
       └─ economical profile
            ├─ safely inside a valid, unexpired proof → do not record
            └─ uncertain / near frontier / proof expired
                 └─ enter precise; wait for a fresh trusted precise sample
```

The existing day rollover, Core Data insertion, fog invalidation, and landmark
discovery behavior remains unchanged for precise updates. Economical updates do no
new-cell Core Data work, fog redraw, reverse-geocoding enqueue, or landmark lookup.

### 5. User control and observability

Add a persisted Settings selection in the initial implementation:

- **Continuous Precision (default):** preserves the current 10 m / 15 m requested
  profile at all times, while applying the new sample validator.
- **Adaptive (Experimental):** uses the profiles above and may lower requested
  accuracy only inside completely explored areas.

Persist the selection in `GridSettings`/`UserDefaults`, following existing setting
patterns. Existing installations with no stored value must migrate to Continuous.
The Settings UI should state plainly that Adaptive is experimental, only reduces
requested precision in completely explored areas, and automatically restores it
near new territory. Do not make a quantified battery-saving claim.

For early diagnostics, make the active profile observable and show it in debug logs
or an internal build indicator. Do not add a persistent user-facing alert or per-cell
notification.

## Implementation tasks

### Task 1: Add the pure sample and coverage models with tests

**Files:**

- Create: `FogOfWalk/FogOfWalk/Models/ExploredAreaClassifier.swift`
- Create: `FogOfWalk/FogOfWalk/Models/LocationSampleValidator.swift`
- Create or modify: a focused XCTest file under `FogOfWalk/FogOfWalkTests/`

- [ ] Define the precise recording threshold and timestamp freshness/order rules in
  one policy type, and apply them to both Continuous and Adaptive modes.
- [ ] Test invalid/non-finite coordinates, negative/non-finite/excessive horizontal
  accuracy, stale and out-of-order timestamps, and samples queued before a
  precise-profile transition.
- [ ] Implement the local coverage-envelope calculation using `GridMath.cellBox` and
  `Set<CellID>` membership.
- [ ] Define explicit inputs for accuracy, speed allowance, and entry/exit radius;
  keep policy constants in one place, not scattered through UI code.
- [ ] Test fully filled areas, a single missing cell, negative coordinates,
  latitude-sensitive longitude padding, polar/antimeridian fallback, enumeration
  caps, and envelopes that exceed the required safety radius.
- [ ] Test hysteresis: a location can enter only via the larger envelope and remains
  economical only via the smaller one.

### Task 2: Add profile state to `LocationService`

**Files:**

- Modify: `FogOfWalk/FogOfWalk/Services/LocationService.swift`
- Modify: `FogOfWalk/FogOfWalkTests/LocationServiceTests.swift`

- [ ] Add a `TrackingProfile` enum and an idempotent `apply(profile:)` method.
- [ ] Expose `accuracyAuthorization` through `LocationManagerProtocol` and
  `LocationService` for reduced-accuracy handling and tests.
- [ ] Configure the manager's `desiredAccuracy` and `distanceFilter` from the
  profile, leaving auto-pause disabled in both.
- [ ] Ensure initial startup, authorization changes, and `restartIfAuthorized()`
  force the runtime profile to precise while retaining
  `allowsBackgroundLocationUpdates` and significant-change monitoring.
- [ ] Extend the mock-based tests to assert both profile configurations and verify
  all existing authorization/restart guarantees still hold.

### Task 3: Connect profile selection to exploration updates

**Files:**

- Modify: `FogOfWalk/FogOfWalk/Views/MapContainerView.swift`
- Modify or add XCTest files for the decision logic

- [ ] Extract the profile decision into a pure state machine so the map coordinator
  only wires data together and performs returned actions.
- [ ] On precise updates, preserve the current cell-recording flow and then assess
  whether economical mode is eligible.
- [ ] On economical updates, validate coverage before any `addCell` call. If unsafe,
  switch to precise and discard the coarse update for exploration purposes.
- [ ] Retain current foreground re-arm and day-rollover behavior.
- [ ] Verify a potentially new coarse location never mutates `visitedCellsCache`,
  while the following precise update does.
- [ ] Test callback sequences for coarse significant-change updates during the
  precise profile, stale/out-of-order fixes, profile-proof expiry, invalid speed or
  speed accuracy, preference changes in both directions, and restart recovery.

### Task 4: Add the tracking preference and UI copy

**Files:**

- Modify: `FogOfWalk/FogOfWalk/Models/GridSettings.swift`
- Modify: `FogOfWalk/FogOfWalk/Views/SettingsView.swift`
- Modify/add tests as appropriate

- [ ] Add the persisted Adaptive/Continuous preference, defaulting existing and new
  installations to Continuous when no value has been stored.
- [ ] Apply preference changes immediately to the active location profile.
- [ ] Add concise explanatory Settings copy and an accessibility label/value for the
  control.
- [ ] Test persistence and both immediate transitions: Continuous forces precise;
  Adaptive remains precise until a fresh trusted sample proves economy is safe.

### Task 5: Lightweight physical-device validation

- [ ] Run the focused unit tests after each task and the full XCTest suite before
  release.
- [ ] Make the active runtime profile and transition reason visible in debug builds.
- [ ] On one physical device, run a normal 10–15 minute Continuous walk with the app
  backgrounded and screen locked; confirm new cells continue to appear.
- [ ] Prepare and import a backup containing a fully explored test area. Enable
  Adaptive and confirm the debug indicator remains economical for a sustained
  period inside it.
- [ ] Walk from that area into unexplored territory with the app backgrounded and
  screen locked. Confirm it returns to precise and leaves no obvious gap (defined
  for this limited test as more than two consecutive 50 m cells).
- [ ] Leave the device stationary in Adaptive for 30 minutes, then move without
  reopening the app; confirm tracking resumes. Repeat the boundary test once on a
  second tester/device if one is available.
- [ ] Do not require a reliable battery-savings estimate for this release. Sustained
  time in economical mode proves the mechanism is exercised; keep Adaptive opt-in
  until broader tester experience justifies reconsidering the default.

## Acceptance criteria

- Existing background location reliability behavior remains intact.
- Neither mode records invalid, stale, out-of-order, or insufficiently accurate
  samples.
- No coarse economical update can unlock a previously unvisited 50 m cell.
- Moving from known territory into fresh territory re-enters precise tracking early
  enough to avoid an obvious gap of more than two consecutive cells in the limited
  physical-device tests. This is an empirical target, not a platform guarantee.
- Adaptive demonstrably enters and sustains economical mode inside the prepared
  fully explored test area; no quantified energy saving is claimed.
- Continuous Precision remains the persisted default and explicit fallback.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| A coarse, cached, reduced-accuracy, or significant-change sample arrives while the configured profile is precise. | Validate every delivered sample independently of profile; after a transition, require a fresh precise sample newer than the transition. |
| Coarse position or GPS reacquisition delay crosses an unexplored edge. | Require full-coverage envelopes, safety margins, hysteresis, speed scaling, and fail to precise on doubt. |
| A dense-but-not-complete walked area is mistaken for safe. | Require every cell in the envelope, not a percentage/density threshold. |
| Driving exits a known area too quickly. | Increase required margin by speed; retain precise mode if the known area is not large enough. |
| Core Location delays an economical update beyond the requested distance filter. | Expire the safety proof and force precision when possible; acknowledge that background delivery offers no hard gap-free guarantee. |
| Existing `cellBox` longitude padding under-covers above the 85° cosine clamp. | Use safe adaptive geometry or refuse economical mode at unsupported latitudes; cap work and fail to precision. |
| Normal walked routes are too narrow to satisfy a large fully explored envelope. | Keep Adaptive experimental and expose debug profile state so testers can confirm whether it activates; reconsider the policy if it rarely does. |
| Lower accuracy gives little saving in some conditions. | Retain Continuous as the default and avoid claims of a fixed or measured saving for the initial release. |
| Profile changes reintroduce the old pause/restart bug. | Never re-enable automatic pause; keep significant-change monitoring and foreground re-arm; cover both in tests. |
