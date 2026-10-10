# Location Energy and Reliable Resume

**Status:** Proposed. This document authorizes no implementation or default change.
**Date:** 2026-10-09
**Supersedes:** [Adaptive Location Tracking](2026-09-04-adaptive-location-tracking.md), deprecated on 2026-10-09.

## Intended outcome

Reduce Fog of Walk's measured battery cost while preserving automatic exploration,
including the first cells walked after the phone has been idle with its screen locked.
The user should not have to open the app or start a walking session to resume tracking.

The first question is where the energy goes. The leading hypothesis is that precise
tracking during long stationary periods is an avoidable cost. This must be measured;
it is not an established diagnosis. If measurement points to rendering, geocoding,
or other app work instead, address that measured cost before replacing location delivery.

This proposal replaces the explored-area strategy entirely. It does not use visited
coverage envelopes, synthetic explored neighborhoods, speed-based frontier margins,
or economical/precise geographic switching.

## Current behavior and constraints

The existing CLLocationManager requests nearest-ten-metre accuracy with a 15 m
filter, disables automatic pausing, enables background updates, and keeps
significant-change monitoring as a recovery mechanism. Foreground activation re-arms
tracking. Automatic pausing previously caused background resume failures.

Keep this implementation as the production default and experimental control.
Do not simply re-enable its automatic-pausing setting. Retain the 50 m grid,
actual-sample-only exploration, local persistence, permission UX, and no-haptics
behavior. Neither interpolation nor user-managed walking sessions is in scope.
The app deployment floor remains iOS 18.6.

## Candidate worth evaluating

Prototype Apple's CLLocationUpdate live-update API as an alternative location
source. Apple's energy guidance describes stationary detection and resumed delivery
when movement returns. That is a reason to experiment, not proof of lower energy
use, prompt GPS reacquisition, or equivalent background reliability in this app.

Before coding, verify API availability against the installed SDK and iOS 18.6,
including stationary diagnostics and background/session lifecycle requirements.
Choose and record the supported live-update configuration; do not assume it maps
to the legacy manager's accuracy and distance-filter knobs. Document permission,
background indicator, cancellation, restart, and OS-termination behavior.

No app timer, motion callback, geofence, or significant-change event is assumed to
wake the app promptly enough to capture the beginning of a walk. Do not deliberately
cancel the candidate stream when stationary and then rely on one of those mechanisms
to restart it. Test the framework's stationary/resume behavior directly.

## Evidence stages and decision gates

### 1. Establish a physical-device baseline

Add minimal internal diagnostics to the current implementation, then measure:

- screen-locked stationary operation for two hours;
- screen-locked walking on a fixed 20–30 minute route;
- foreground map use on that route, measured separately;
- stationary-to-walking departure after 30 minutes, two hours, and overnight.

Record device and OS version, build, authorization/accuracy authorization, charging,
Low Power Mode, thermal state, battery range, network conditions, screen state,
workload duration, and measurement method. Inspect location-related energy and CPU,
rendering, geocoding, and persistence activity. Use physical-device energy profiling
supported by the installed Xcode. Battery percentage alone is insufficient for a
short trial. A diagnostic trace identifies likely causes; it is not a calibrated
battery-saving percentage.

**Gate:** Produce an attributable baseline and identify the largest actionable cost.
If stationary location work is not material, record that finding and propose a
measured alternative before implementing a new tracker. Inconclusive measurement
means repeat or improve the measurement, not assume the hypothesis is true.

### 2. Build a comparable experimental location source

Introduce the smallest location-source seam needed to feed the existing exploration
pipeline from either the legacy manager or the candidate live-update stream. One
source runs at a time. Switching cancels the old source, invalidates its outstanding
callbacks, and starts the selected source without duplicating exploration actions.

Keep source/session ownership outside the lifetime of a map coordinator. The map
continues to receive updates without owning background session survival. Implement
explicit start, stop, authorization-change, foreground recovery, and error handling.
A persisted internal build setting selects the candidate; absent/unknown settings
select the legacy source. Do not add a public experimental setting at this stage.
Keep recovery-only monitoring only if compatible and justified; distinguish its
samples in diagnostics where possible and never let coarse recovery data bypass
recording validation. Document any difference from the legacy recovery behavior.

Define one common recording validator before comparing sources. Initial trial
policy: valid finite coordinates, finite horizontal accuracy from 0 through 25 m,
sample age from 0 through 15 seconds, strictly increasing timestamps, and timestamps
at or after the current source-session start. Treat these as explicit experimental
values, not an established optimum. Unknown speed does not invalidate an otherwise
acceptable exploration sample. Do not reject a good sample merely because a
stationary diagnostic was also reported.

First compare this validator with the original app on real traces. If it materially
reduces legitimate coverage, revise it and rerun the baseline. Then use the same
fixed validator for both sources. This separates validation changes from source
changes. Handle delivered sample batches in timestamp order; test duplicates and
late callbacks. No coordinate enters GridMath before validation.

**Gate:** Full build and XCTest suite pass; source lifecycle and validation behavior
are deterministic. No claims about energy or OS wake-up reliability yet.

### 3. Establish background reliability on physical devices

Use a fixed route crossing grid interiors rather than merely touching corners.
Use an independently recorded reference route and departure time, such as a second
trusted logger carried alongside the test phone. Do not run an additional precise
location consumer on the test phone: it could alter the behavior being measured.
Record reference uncertainty and exclude ambiguous boundary cells from scoring.

For each source, start each paired trial from the same isolated exploration fixture.
Keep the departure corridor unvisited. Never import fabricated exploration into the
user's normal history. Do not reopen the app until the route is complete.

Measure departure-to-first-accepted-fix time, distance traveled before that fix,
reference-route cells captured/missed, consecutive missed cells, rejected samples,
callback gaps, and any manual intervention. Measure path distance in metres from
the reference; grid columns are not uniformly 50 m wide at every latitude.

Minimum initial matrix on the primary physical device:

- three matched pairs of departures after 30-minute idle;
- three matched pairs after two-hour idle;
- three matched pairs after overnight idle;
- three matched pairs of uninterrupted 20–30 minute walking routes;
- controlled permission loss/regrant, foreground recovery, and source restart;
- at least one poor-reception departure scenario, clearly identified in results.

Alternate source order across pairs. Test system termination/relaunch separately
where reproducible; report untested cases explicitly. User force-quit is a separate
condition and must not be described as guaranteed automatic recovery. Add cycling
and driving departure trials before claiming support equivalence for those uses.

Proposed trial gates, fixed before inspecting candidate results:

- zero departures requiring the user to reopen the app;
- first accepted location before 25 m of reference-route travel after departure;
- at least 95% of unambiguous reference-route cells captured on each normal walk;
- no run of two or more consecutive missed reference-route cells;
- candidate aggregate coverage no more than one percentage point below the control.

Report both absolute results and paired differences. If the legacy source fails an
absolute gate, investigate the baseline rather than relaxing the gate after seeing
candidate results. Report adverse-reception results separately; candidate-specific
stalls block promotion. These are trial acceptance thresholds, not OS guarantees.

**Gate:** Evidence demonstrates usable departure and walking behavior. A simulator
pass cannot satisfy this gate. Small samples support a limited experiment, not a
claim of universal reliability.

### 4. Test energy benefit without compromising the comparison

Use at least five paired two-hour stationary runs and five paired walking runs per
source on the same phone with matched conditions and alternating order. Obtain an
initial measurement-noise estimate from repeated control runs. Keep diagnostics
equivalent and lightweight; verify behavior without an attached debugger as well.

Select one repeatable energy metric before candidate trials and record its units,
limitations, and capture procedure. Define the minimum useful change as the larger
of 15% of the control metric or twice the observed control-run variability. Candidate
stationary use must improve by that amount in the median paired comparison and
improve in at least four of five pairs. Walking energy must show no regression
larger than the measured variability. If tooling cannot produce a meaningful
quantitative comparison, extend the trials or change the measurement method;
profile-state duration and callback count alone do not establish energy savings.

Finally run at least three paired representative day-length trials, including idle
and walking, to check whether stationary gains translate to useful daily benefit.
Record confounding phone use and repeat invalid comparisons. Do not claim a universal
battery percentage from one device or from an uncalibrated energy metric.

**Gate:** Reliability still passes and energy improvement exceeds noise. Otherwise
retain the legacy implementation and record the experiment as unsuccessful or
inconclusive. A negative finding is useful evidence; it is not a delivered fix.

### 5. Limited rollout and promotion decision

Only after the prior gates pass, offer the candidate as an explicitly experimental
opt-in with the legacy source as immediate fallback. Require a second physical
device, preferably a different supported OS/hardware combination, to repeat the
stationary-departure and energy checks before broad promotion. If unavailable,
keep the experiment limited and record the missing evidence.

Collect ordinary-use observations for at least one week from the small tester group.
Any confirmed candidate-specific tracking stall or repeatable coverage regression
blocks default promotion. Choose adopt, extend experiment, or reject in a durable
decision with evidence links. A default change is a separate product decision;
completion of a prototype does not imply approval to switch all users.

## Required independent reviews

An independent reviewer must assess each checkpoint below. Record findings,
resolutions, evidence links, and the decision in the initiative before advancing.
A passing test suite does not replace these reviews.

1. **Before implementation:** review the baseline measurement protocol, available
   instruments/devices, reference-route method, and feasibility of trial workloads.
   Challenge the proposed numeric thresholds (including validation cutoffs, coverage,
   departure distance, trial counts, and energy criteria). Define the variability
   statistic and paired comparison method explicitly. Finalize the protocol before
   examining candidate results; document any later revision and rerun affected trials.
2. **Before physical candidate trials:** inspect source/session ownership,
   cancellation and stale callbacks, authorization changes, foreground recovery,
   background indicator behavior, and OS-version availability. Review tests for
   failure paths and confirm the experimental source cannot silently replace the default.
3. **Before adoption:** review all physical results, failed/inconclusive trials,
   measurement uncertainty, coverage regressions, and second-device evidence.
   Recommend adopt, extend, or reject; implementation success alone is insufficient.

Execution roles and delegation instructions are in the workspace
[execution handover](https://github.com/JBraff/agent-workspace/blob/codex/fog-location-energy-plan/work/handoffs/fog-location-energy-and-reliability.md).
The handover's model assignments do not change these evidence requirements.

## What each testing layer proves

| Layer | Tests | What it cannot prove |
|---|---|---|
| Pure XCTest | Validator boundaries; virtual-clock silence; source/session state; errors; cancellation; late batches; unknown speed | Real OS scheduling, positioning accuracy, energy |
| Integration XCTest | Both sources use identical validation; rejected data cannot alter cells/landmarks; accepted samples preserve day rollover and persistence; one active source; preference fallback and recovery | Background resume on hardware |
| iPhone simulator | UI selection, injected route replay, source switching, permission paths that can be simulated | Real stationary detection, radio cost, locked-screen wake-up timing |
| Physical iPhone | Idle departures, route coverage, recovery, energy and representative daily use | Universal reliability across all devices and environments |

Virtual-clock silence tests must show that the app cannot manufacture a fix or
claim successful resume without a delivered location. They must not simulate a
background timer as guaranteed execution. Add regression tests for every discovered
logic bug using XCTest and the repository's MainActor conventions. Run the full
build and test suite for each implementation stage, not only focused tests.

## Diagnostics and evidence

Internal diagnostics record source/session, receipt and sample times, accuracy,
accept/reject reason, stationary indication, lifecycle events, and downstream work
counts. No persistent user alerts. Keep raw coordinates and reference traces local
and opt-in; never commit personal routes or raw location logs. Commit only redacted
aggregate results and reproducible procedures under docs/evidence/ when available.

Each evidence record includes build, device/OS, protocol, trial count, results,
failures, uncertainty, and the gate decision. The workspace initiative owns current
milestones, progress, blockers, and next actions. This document owns the proposed
method and acceptance policy. No measurements have been performed for this plan.

## Sources and interpretation

- [Apple: Accessing the device's location efficiently](https://developer.apple.com/documentation/xcode/accessing-the-device-s-location-efficiently)
  supports investigating stationary-aware delivery and minimizing location work.
- [Apple: Adopting live updates in Core Location](https://developer.apple.com/documentation/corelocation/adopting-live-updates-in-core-location)
  is the implementation reference for the candidate source.
- [Apple: Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
  is the lifecycle/session reference; check availability for the supported OS.

The choice to investigate this API and all numeric trial gates above are engineering
proposals for Fog of Walk, not Apple performance promises.
