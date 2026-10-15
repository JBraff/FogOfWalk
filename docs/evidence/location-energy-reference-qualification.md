# Departure reference qualification after the build-2 pilot

> Scope update, 2026-10-15: this document preserves earlier measurement preparation and observations. Current delivery follows [Automatic stationary pause and walking resume](../proposals/2026-10-15-automatic-stationary-pause-and-resume.md): a minimal Study-only prototype and one focused locked-screen idle-to-walk check. Old next-test directions, formal energy qualification and repetition requirements below are historical, not prototype prerequisites. Manual OFF/sleep evidence does not establish automatic pause/resume.


**Date:** 2026-10-12
**Status:** Preparation procedure; timing and distance references are not yet qualified.
**Authority:** [Replacement proposal](../proposals/2026-10-09-location-energy-and-reliability.md)
and [baseline protocol](location-energy-baseline-protocol.md). This addendum does
not change the 100 m gate, select a candidate, or authorize a passing trial.

## What the existing pilot establishes

The [physical verification record](location-energy-diagnostics-verification.md)
establishes capture-origin reporting on build 2: 587 steps, 385.8 estimated
metres, 92 endpoints, and pre-classification counts retained. It establishes
correct legacy forwarding of 22 fresh, shadow-accepted samples. It does not
establish the distance walked from departure through first accepted receipt.

The reported stopwatch readings were 10:18 at departure and 15:35 at finish;
their difference, 5:17, is owner-reported. The capture lasted 928.6 seconds,
6.4 seconds less than the reported timer total. Neither the timer's capture-start
reading nor its return/Stop relation was recorded. This discrepancy does not
identify an offset or prove a clock defect. The earlier minute-level departure
estimate is superseded for scoring purposes. A guessed five-second alignment,
walking classification, or the location samples cannot recover the missing anchor.

The approximately 400 m map estimate and 385.8 m pedometer total differ by about
3.5%. That agreement does not bound either measurement, and the earlier loop's
12.5% disagreement does not calibrate this route. Whole-route agreement cannot
establish error in the first 100 m, exclude compensating errors, or assign phone
handling steps to the walk. Retain both pilots as reporting/feasibility evidence;
do not rescore either as a formal departure pass or failure.

## Recorded timing anchor

### Pre-idle starting-position check

During setup, identify a fixed physical starting spot and record a location fix
before the stationary interval begins. Review its sample/receipt timestamps and
horizontal accuracy from the diagnostic log; a visible map dot alone does not
prove that this tracker recorded a fresh fix. Retain the starting coordinate
privately with its accuracy uncertainty. It is a useful setup reference, not an
exact ground-truth position. Keep the phone at that spot during idle and locked
through departure. Opening Fog immediately before the walk calls its foreground
rearm path and changes the idle-departure condition being tested.

For exploratory observations, report the independently timed departure interval,
time to the first fresh, shadow-accepted post-departure receipt, and displacement
from the pre-idle fix with both fixes' reported horizontal-accuracy estimates,
without treating those estimates as validated error bounds. Displacement between
fixes does not establish cumulative distance walked during a delivery gap,
especially with turns or a return toward the start. This uses the tracker under
evaluation, so it does not replace the independent motion/route uncertainty needed
for the unchanged formal 100 m pedometer screen. Retain ambiguous samples and
label unqualified formal departure results inconclusive.

Route-distance qualification is not a prerequisite for stationary energy
collection. All energy preflight, connection, settling, display, trace, and
attribution requirements in the baseline protocol still apply. This simpler
position check makes preliminary observations useful without requiring a whole-
route tape measurement; it does not qualify a physical departure reference.

### Stopwatch observations

Use one continuously running, independent stopwatch for the whole capture. A
watch used only for timing is sufficient for recording observations; no GPS or
workout is needed. Keep the phone in its fixed carry position during the walk.
Record readings contemporaneously on paper or retained stopwatch laps, rather
than reconstructing them from memory afterward.

While stationary, record a stopwatch reading immediately **before** pressing
Start Diagnostic Capture and another immediately **after** the app visibly
confirms capture is running. These observations bracket the actual capture-start
event; starting two devices "together" is not an anchor. Keep the timer running
through return, reconnection if needed, and capture Stop. Similarly bracket the
Stop tap with before/after readings and confirm that capture ended without error.
Record return separately from Stop. Log any steps while unlocking, handling,
or reconnecting the phone; prefer remaining at the finish without extra walking.

Where practical, also bracket departure with retained readings taken before the
first physical step and after it. Bracket return and checkpoint passage in the
same way, taking readings before reaching and after crossing the physical marker.
Use the full observed interval, expanded for displayed precision. This avoids
assigning an invented reaction-time allowance to a single after-the-event lap.
If only a single reading is available, record its observation-delay uncertainty
and leave it unsupported until there is evidence for the allowance.

The private trial row must contain the displayed precision, each start/stop
bracket, departure and return readings with observation uncertainty, pauses,
checkpoint readings if used, and whether the timer reset/paused or phone clock
settings changed. Observation uncertainty includes reading resolution and the
delay between the physical event and noting or lapping it. Choose an achievable
observation procedure before a trial; a claimed reaction-time bound must be
supported, not selected afterward to make a gate pass.

For analysis, let capture start be C0 in the log and its stopwatch bracket be
[S0low, S0high]. With seconds as units, the constant clock-offset interval is
[C0 - S0high, C0 - S0low]. Independently compute the stop offset interval from
capture stop C1 and [S1low, S1high]. Check whether the two intervals are consistent.
Do not force them to overlap by shifting an observation. Keep the full start
bracket for scoring; the end check is a consistency check, not permission to
shrink the uncertainty to a favorable intersection.

These equations assume stable relative clock rate. Start/end agreement alone
does not bound interior clock drift or wall-clock adjustments. Record how clock
stability and drift allowance are supported for the actual capture duration,
including long-idle captures; expand converted time intervals by that allowance.
If this component or an observation interval is unsupported, timing remains
unqualified for formal scoring. A short pilot does not qualify an overnight clock bound. Do not
infer clock stability from location or walking-classification events.

## Bounded route distance

Select the reference before another pilot. Prefer an existing physically marked
route whose length and tolerance have documented provenance, or a sidewalk route
measured locally with a tape or measuring wheel. A public-map centerline or a
watch/phone GPS workout is not a physically measured sidewalk reference. No new
precise-location lookup is required. Keep addresses, maps, and measurement notes
private; commit only the method and aggregate uncertainty.

Measure the actual walking line from fixed start to fixed turnaround/finish,
including bends and the turnaround. Record instrument resolution, accuracy or
calibration evidence, endpoint placement, path-following deviation, and repeat
measurements in both directions. Repeated agreement estimates repeatability; it
does not remove systematic instrument error. If the available tool has no
supportable accuracy bound, do not describe the result as bounded.

For departure-reference qualification, include identifiable distance checkpoints
through at least the first 150 m, preferably no more than 25 m apart, and a route
of at least 200 m. Their cumulative distance intervals must include segment and
placement error. Record independent passage-time intervals with the stopwatch,
without unlocking the phone. Do not add markings without permission. This is a
reference pilot and may involve timing laps; it is not a controlled energy run.
If recording passage times changes walking substantially, document that limit.

At any analysis time, use the last checkpoint definitely passed before the
earliest possible time and the next checkpoint definitely passed after the
latest possible time to bracket travelled distance. Include endpoint tolerances,
timing uncertainty, and any permitted path deviation. With no suitable pair,
the bracket widens to departure or finish; do not insert a constant-speed estimate.
The route must progress monotonically through the checkpoint corridor with no
unrecorded stop, reversal, shortcut, or detour. Explicitly measured pauses can
widen timing intervals; an undocumented deviation makes the reference unusable.

Use cumulative **travelled** distance, not straight-line displacement. The early
qualification corridor is outbound; label its passage direction explicitly.
On an out-and-back, separately label return passages and add the outbound length
to distance travelled back from the turnaround. Never reuse an outbound marker
distance as the return cumulative distance. A tight receipt bracket requires an
observed checkpoint beyond the latest possible receipt time. If receipt is beyond
the instrumented corridor, retain the broad departure/finish interval and its
effect on disposition; do not extend the corridor with interpolation.

## Qualify the pedometer locally, then review the gates

The proposal's departure metric remains pedometer-estimated walking distance
through first accepted receipt, with uncertainty. Checkpoints corroborate and
test that estimate; they do not silently replace its metric. Compare cumulative
pedometer changes with measured progress at multiple early checkpoints and
receipt-time brackets, including pre-departure and post-return handling. Include
historical sampling cadence and any reporting latency in the uncertainty.
A whole-route scale factor or one pilot's largest residual is not a guaranteed
bound for a later departure after 30 minutes, two hours, or overnight idle.

Use adjacent historical endpoints to bracket cumulative readings at uncertain
departure and receipt times. For a monotone valid report, the widest subtraction
uses the upper receipt reading minus the lower departure reading; the narrowest
uses the lower receipt reading minus the upper departure reading, clamped at zero.
Do not linearly interpolate or subtract the walking-classification time. This
brackets the reported quantity only; an independently supported local pedometer
error allowance is still needed to bound actual walking distance. Missing distance,
nonmonotone readings, uncertain attribution of handling steps, or unsupported
history-timing error cannot be treated as zero uncertainty.

Inspect accepted samples against the independent departure interval. A sample
whose timestamp can precede departure cannot establish a fresh post-departure
fix merely because receipt is later. Preserve all ambiguous early samples; do
not discard them to present a later sample as the known first fix. Report both
sample and receipt times. If uncertainty prevents identifying the first accepted
post-departure sample or bounding its movement distance, disposition is inconclusive.

Predeclare how calibration observations support the error allowance and its
applicable conditions before candidate results. The next independent review
must assess the actual timing/measurement method, early-distance error, idle
duration limits, and the provisional departure gates after reference qualification.
If the one-phone method cannot support that allowance, record the gate inconclusive
and propose a separately reviewed protocol amendment rather than substitute a
different metric or relax the threshold.

Report three separate quantities: the historical pedometer departure-to-receipt
interval, the independently measured checkpoint progress interval, and the error
allowance plus resulting uncertainty interval used for the pedometer screen.
State whether calibration supports only this run's uncertainty or an explicitly
limited future-use envelope. Fitting an allowance to checkpoint observations and
then showing agreement with those same observations is not independent validation
for later trials. Additional applicability evidence is required before extending
an allowance to another route, carry position, pace, or idle duration.

The pedometer screen's qualified uncertainty interval wholly below 100 m can pass the distance screen.
An interval wholly at or above 100 m can fail it; a straddling interval remains
inconclusive. All other proposal gates still apply. No baseline, attribution,
coverage, candidate reliability, or battery benefit follows from this preparation.

## Preparation checkpoint

Before requesting another walk, establish which measured route or measurement
tool is actually available and settle the observation procedure. The immediate
no-walk preparation option is a stationary Start/Stop lap rehearsal with build 2:
retain both boundary brackets, displayed precision, and matching logged events.
This checks recording feasibility only. It does not demonstrate interior clock
stability, distance error, or formal eligibility.

A subsequent short exploratory reference pilot may report conditional timing
intervals under an explicitly stated stable-clock assumption, once the available
route/tool and that limited purpose are agreed. Unsupported clock or distance
allowances remain unqualified; such a pilot cannot pass the formal gate or qualify
long idle. Retain measured-route uncertainty evidence and obtain the post-pilot
gate review before formal scoring. A procedure review is not physical qualification. The study
build was version 1.0/build 2 when this reference procedure was prepared. The
current installed build is 1.0/build 3, with distinct Study packaging and the
same capture-origin motion behavior; use its current build metadata for future
trials. Legacy tracking remains unchanged, and this procedure needs no reinstall.
