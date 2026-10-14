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

## Available test setup and evidence limit

The study uses one physical iPhone and an iPhone simulator. There is no second
device or independent GPS logger. The simulator supplies known coordinates for
repeatable pipeline and route-replay tests; it cannot measure phone energy or
prove that iOS resumes location delivery after a real locked-screen departure.
The iPhone supplies the physical resume and energy evidence. A planned walking
route and the phone's historical motion/pedometer data can give a separate
movement reference, but cannot provide an independently measured GPS trace.
Report these limits with every gate decision. Do not claim cross-device or
cross-OS reliability from this study.

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

After the independent protocol review, add minimal internal diagnostics to the
current location implementation without changing its delivery policy, including
its current practice of forwarding only the last sample in each delivered batch.
Record batch receipt, sample metadata, the forwarded sample, downstream
processing, and proposed-validator decisions in shadow mode. Keep raw
coordinates local, opt-in, and bounded. Measure that diagnostics-only legacy
build before testing a candidate source:

- screen-locked stationary operation for two hours;
- screen-locked walking on a fixed 20–30 minute route;
- foreground map use on that route, measured separately;
- stationary-to-walking departure after 30 minutes, two hours, and overnight.

Before scoring a formal baseline departure, pilot the post-run motion reference
described in stage 3 on the same phone. Its availability and uncertainty determine
whether the one-phone departure gate can be evaluated at all. A failed pilot does
not become a passing baseline by substituting location callbacks for movement
ground truth.

Before the first formal run, fix the trial sheet and use it unchanged for both
sources. Use one study build with an isolated app container for both legacy and
candidate runs, so test fixtures never enter the owner's normal exploration
history. If the normal TestFlight app remains installed, disable its location
permission while the study app is the active tracker and verify it is not
tracking. Stop study tracking before restoring normal-app permission. Apply the
same exclusivity to representative-use windows and the ordinary-use week.
Complete all study-app permission prompts before timing. Start each pair with
Low Power Mode off, the phone unplugged and disconnected from Xcode, battery
between 40% and 80%, and no serious thermal state. Allow at least ten minutes
after charging, installation, or active phone
use before starting a locked-screen run. Turn Always-On Display off for the
controlled stationary and walking comparison, hold network mode and ordinary
display settings constant within each pair, and let any geocoding/backfill work
finish before the measurement. Record normal-use trials separately if they use
different display settings. Discard and repeat a whole pair for pre-existing
thermal state, charging, or unrelated phone use during capture. A thermal rise
that develops during an otherwise valid run is a result to investigate, not a
reason to discard an unfavorable candidate run. For stationary energy, analyze
the predeclared interval from minute 10 through minute 120; retain the full
trace to inspect startup and sleep behavior. For walking energy, analyze the
entire predeclared route interval. Alternate source order across pairs.

Record device and OS version, build, authorization/accuracy authorization, charging,
Low Power Mode, thermal state, battery range, network conditions, screen state,
workload duration, and measurement method. Inspect location-related energy and CPU,
rendering, geocoding, and persistence activity. Use physical-device energy profiling
supported by the installed Xcode. Battery percentage alone is insufficient for a
short trial. A diagnostic trace identifies likely causes; it is not a calibrated
battery-saving percentage.

On an iPhone running iOS 26 or later, use on-device Power Profiler for locked-screen
and walking runs so the phone can be unplugged and away from Xcode. Enable tracing
for the TestFlight or development build, start and stop each run from Control Center,
then transfer the `.aar` trace to the Mac for Instruments analysis. Record the actual
trace interval, app build, Always-On Display setting, display-brightness and thermal
tracks, and any other phone use. Hold ordinary display settings constant across
matched runs. The profiler's system power rate is whole-device consumption, not
Fog of Walk's isolated cost; its per-process impact tracks also do not by themselves
identify Core Location as the cause. Correlate them with the app diagnostics and
other profiling before attributing cost. For measured locked-screen runs,
disconnect Xcode's device connection, including wireless debugging, and confirm
the trace contains expected sleep/wake activity. An attached debugger or charging
phone can change the measurement; charging makes the reported system power rate zero.
On-device traces are limited to ten hours, so representative-use windows must
fit within that limit. Keep full traces local and private.

**Gate:** Produce an attributable baseline and identify the largest actionable cost.
If stationary location work is not material, record that finding and propose a
measured alternative before implementing a new tracker. Inconclusive measurement
means repeat or improve the measurement, not assume the hypothesis is true.
If attribution from Power Profiler and app diagnostics remains ambiguous, a
separate stationary-only diagnostic control may suspend location delivery on the
same phone to estimate the whole tracking-dependent overhead. Keep that control
out of normal exploration history and never treat it as a candidate tracking mode.
Audit MapKit's user-location display and other in-app location consumers during
this baseline; an additional active location consumer could mask a source change.

### 2. Build a comparable experimental location source

Introduce the smallest location-source seam needed to feed the existing exploration
pipeline from either the legacy manager or the candidate live-update stream. One
source runs at a time. Switching cancels the old source, invalidates its outstanding
callbacks, and starts the selected source without duplicating exploration actions.
Keep the study app identity, permissions, map behavior, and data fixture equivalent
between arms. Verify that MapKit's user-location feature does not maintain a
second continuous background tracker that defeats the comparison. If map behavior
must change, apply that change to both sources and rerun the affected legacy
baseline before attributing any energy difference to the candidate.

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

### 3. Establish one-phone background reliability

Prepare one repeatable walking route on a local map, with a fixed physical start,
turns, and finish. Walk the same sidewalk and direction for both sources. Before
candidate trials, identify expected grid cells whose route segment passes well
inside the cell; exclude cells near a boundary or a route choice and record how
many were excluded. The mapped route is an approximate reference, not an
independent GPS recording. Keep the route private. Do not run another location
consumer on the test phone during a trial.

Use a study-only, post-run query of the phone's historical Core Motion activity
and pedometer data to estimate when walking began and distance walked before the
first accepted fix. It requires Motion & Fitness permission; obtain it before
timed trials. Query after the walk, not as a live motion callback or a way to wake
the tracker. First pilot the method on a physically marked route to establish
activity-onset resolution and pedometer distance error. If the data is unavailable
or too uncertain to distinguish the departure gate, mark that trial inconclusive;
do not infer movement onset from the location stream being evaluated. Do not add
motion collection to the production tracker.

For each source, start each paired trial from the same isolated exploration fixture.
Keep the departure corridor unvisited. Never import fabricated exploration into the
user's normal history. Leave the phone locked and do not reopen the app until the
route is complete. Analyze the first accepted post-departure sample by both sample
time and receipt time; a cached earlier fix cannot satisfy the departure gate.

Use injected, known-coordinate XCTest routes to prove exact validator and cell
behavior, and simulator GPX/UI replay to exercise source selection and app wiring.
Those tests have precise input truth but cannot establish physical resume timing.
On the iPhone, record motion-onset uncertainty, estimated distance to first fix,
mapped interior cells captured/missed, consecutive gaps, rejected samples,
callback gaps, and any manual intervention. The mapped route cannot score every
actual footstep or establish sub-cell coverage accuracy.

Minimum initial matrix on the same physical iPhone:

- three matched pairs of departures after 30-minute idle;
- three matched pairs after two-hour idle;
- three matched pairs after overnight idle;
- three matched pairs of uninterrupted 20–30 minute walking routes;
- controlled permission loss/regrant, foreground recovery, and source restart;
- at least one poor-reception departure scenario, clearly identified in results.

Alternate source order across pairs. Test system termination/relaunch separately
where reproducible; report untested cases explicitly. User force-quit is a separate
condition and must not be described as guaranteed automatic recovery. Add cycling
and driving departure trials before claiming support for those uses; the phone's
pedometer reference only evaluates walking.

Proposed one-phone trial gates, fixed before inspecting candidate results and
reviewed again after the motion-reference pilot:

- zero departures requiring the user to reopen the app;
- first accepted post-departure location delivered before 100 m of
  pedometer-estimated walking distance through its receipt time, with uncertainty
  wholly inside the limit; report the sample time separately;
- at least 90% of preselected interior route cells captured on each normal walk;
- no run of two or more consecutive missed interior route cells;
- candidate aggregate interior-cell coverage no more than five percentage points
  below the control.

The 100 m and coverage gates are weaker than the former independent-GPS gates;
they are screening thresholds for this one-phone study, not equivalent evidence.
Report absolute results, paired differences, exclusions, and uncertainty. If the
legacy source fails an absolute gate, investigate the baseline rather than relax
the gate after seeing candidate results. Report adverse-reception results
separately; candidate-specific stalls block promotion. Trials with an uncertain
departure or route deviation cannot be scored as passes.

**Gate:** Physical evidence supports or rejects a limited one-phone experiment.
Simulator success alone cannot satisfy this gate. Passing does not prove exact
route coverage, prompt wake-up on other devices, or universal reliability.

### 4. Test energy benefit without compromising the comparison

Use at least five stationary pairs of two-hour runs and five walking pairs on the
same phone. Each pair contains one legacy and one candidate run under matched
conditions; alternate their order. Obtain an initial measurement-noise estimate
from repeated control runs. Keep diagnostics equivalent and lightweight; verify
behavior without an attached debugger as well.

The primary metric is the time-weighted mean of unplugged, valid whole-device
Power Profiler system-power-rate samples over the predeclared analysis interval,
in percentage points of battery capacity per hour. It is a same-phone comparison,
not Fog of Walk's isolated consumption. Before candidate data, collect three
control/control pairs for each workload. Let variability be the median absolute
difference between those paired control rates, separately for stationary and
walking trials. If display state, other phone use, charging, or serious thermal
state at the start invalidates a run under the predeclared protocol, repeat the
whole pair; do not trim only an unfavorable interval. Record the metric
resolution and extend controls if variability cannot be estimated meaningfully.

For each candidate pair, define improvement as legacy rate minus candidate rate.
Stationary median paired improvement must exceed the larger of 15% of the median
legacy rate or twice stationary control variability, and at least four of five
pairs must improve. Walking median candidate excess must not exceed walking
control variability; investigate any individual pair with an excess greater than
twice that variability. Report all pairs, not only the median. If the rate cannot
support a meaningful comparison, extend trials or choose and predeclare another
metric before inspecting more candidate results. Callback count and profile-state
duration alone do not establish energy savings.

Finally run at least three matched pairs of representative-use windows, each no
longer than the Power Profiler ten-hour limit and each including both idle and
walking. Compare matched durations and report them as sampled daily-use windows,
not full-day battery use. Record confounding phone use and repeat invalid pairs.
Do not claim a universal battery percentage from one device or from an
uncalibrated energy metric.

**Gate:** Reliability still passes and energy improvement exceeds noise. Otherwise
retain the legacy implementation and record the experiment as unsuccessful or
inconclusive. A negative finding is useful evidence; it is not a delivered fix.

### 5. One-phone adoption decision

Only after the prior gates pass, offer the candidate as an explicitly experimental
opt-in on the tested phone, with the legacy source as immediate fallback. The
one-phone study can conclude that the candidate is useful for this device and OS;
it cannot establish reliability or energy benefit across the supported hardware
and OS range. Record that limitation instead of treating a simulator run as a
second physical device.

Collect at least one week of ordinary use on the same phone. Any confirmed
candidate-specific tracking stall or repeatable coverage regression blocks even
the limited opt-in. Choose keep opt-in, extend experiment, or reject in a durable
decision with evidence links. A production-wide default change is outside this
one-phone plan and requires a separate product decision with evidence appropriate
to the devices it would affect. Completion of the prototype does not imply such
a default change.

## Required independent reviews

An independent reviewer must assess each checkpoint below. Record findings,
resolutions, evidence links, and the decision in the initiative before advancing.
A passing test suite does not replace these reviews.

1. **Before implementation:** review the baseline measurement protocol, the
   one-phone route and motion-reference pilot, available instruments, and trial
   feasibility. Challenge numeric thresholds, including validation cutoffs, the
   100 m estimated departure limit, interior-cell coverage, counts, and energy
   criteria. Finalize inclusion rules, variability, and paired comparison before
   examining candidate results; document any later revision and rerun affected
   trials.
2. **Before physical candidate trials:** inspect source/session ownership,
   cancellation and stale callbacks, authorization changes, foreground recovery,
   background indicator behavior, and OS-version availability. Review tests for
   failure paths and confirm the experimental source cannot silently replace the default.
3. **Before limited adoption:** review all physical results, failed/inconclusive
   trials, motion and route-reference uncertainty, energy uncertainty, and coverage
   regressions. Recommend limited opt-in, extend, or reject; implementation success
   alone is insufficient.

Execution roles and delegation instructions are in the workspace
[execution handover](https://github.com/JBraff/agent-workspace/blob/codex/fog-location-energy-plan/work/handoffs/fog-location-energy-and-reliability.md).
The handover's model assignments do not change these evidence requirements.

## What each testing layer proves

| Layer | Tests | What it cannot prove |
|---|---|---|
| Pure XCTest | Validator boundaries; virtual-clock silence; source/session state; errors; cancellation; late batches; unknown speed | Real OS scheduling, positioning accuracy, energy |
| Integration XCTest | Both sources use identical validation; rejected data cannot alter cells/landmarks; accepted samples preserve day rollover and persistence; one active source; preference fallback and recovery | Background resume on hardware |
| iPhone simulator | UI selection, known-coordinate route replay, source switching, permission paths that can be simulated | Real stationary detection, radio cost, locked-screen wake-up timing |
| One physical iPhone | Idle departures, approximate mapped-route coverage, recovery, paired energy and representative-use windows | Independent GPS ground truth or reliability across other devices and OS versions |

Virtual-clock silence tests must show that the app cannot manufacture a fix or
claim successful resume without a delivered location. They must not simulate a
background timer as guaranteed execution. Add regression tests for every discovered
logic bug using XCTest and the repository's MainActor conventions. Run the full
build and test suite for each implementation stage, not only focused tests.

## Diagnostics and evidence

Internal diagnostics record source/session, batch receipt and sample times,
accuracy, forwarded sample, shadow or active accept/reject reason, stationary
indication, lifecycle events, and downstream work counts. No persistent user
alerts. Keep raw coordinates, mapped routes, and motion reference data local and
opt-in; never commit personal routes or raw location logs. Commit only redacted
aggregate results and reproducible procedures under docs/evidence/ when available.

Each evidence record includes build, device/OS, protocol, trial count, results,
failures, uncertainty, and the gate decision. The workspace initiative owns current
milestones, progress, blockers, and next actions. This document owns the proposed
method and acceptance policy. No protocol-qualified baseline or candidate
measurements have been performed for this plan.

## Sources and interpretation

- [Apple: Accessing the device's location efficiently](https://developer.apple.com/documentation/xcode/accessing-the-device-s-location-efficiently)
  supports investigating stationary-aware delivery and minimizing location work.
- [Apple: Adopting live updates in Core Location](https://developer.apple.com/documentation/corelocation/adopting-live-updates-in-core-location)
  is the implementation reference for the candidate source.
- [Apple: Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
  is the lifecycle/session reference; check availability for the supported OS.
- [Apple: Measuring your app's power use with Power Profiler](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler)
  documents on-device traces, sharing, the whole-device power rate, charging and
  pairing limitations, and the ten-hour capture limit.
- [Apple: Simulating location in tests](https://developer.apple.com/documentation/xcode/simulating-location-in-tests)
  describes known-coordinate and GPX replay for test logic, not physical wake-up.
- [Apple: Core Motion activity history](https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager)
  and [pedometer history](https://developer.apple.com/documentation/coremotion/cmpedometer)
  support post-run movement estimates on the same phone, subject to permission,
  availability, and measured uncertainty.

The choice to investigate this API and all numeric trial gates above are engineering
proposals for Fog of Walk, not Apple performance promises.
