# Location energy baseline preparation — verification

**Date:** 2026-10-10; updated 2026-10-13.
**Scope:** Diagnostics-only legacy study builds, simulator verification, physical installation, motion-history checks, exploratory stationary recordings, and the completed build-3 foreground profiler-targeting check. No protocol-qualified physical energy baseline is recorded.

## Checks performed

- Xcode 27.0 generic iOS Simulator build passed for the normal app.
- Full `xcodebuild test` passed on an iOS 27.0 iPhone 18 Pro simulator: 235 test cases passed, none failed. New tests cover provisional shadow-validation boundaries, unknown speed, opt-in capture, original last-sample forwarding, and study-app gating.
- A separate Debug simulator build passed with `PRODUCT_BUNDLE_IDENTIFIER=com.jeremybraff.fogofwalk.study` and `FOG_APP_DISPLAY_NAME=Fog Walk Study`. The built `Info.plist` resolved that bundle ID and name and includes `NSMotionUsageDescription`.
- The separate app installed and launched in the simulator. Its initial location permission prompt displayed the study app name. Simulator launch does not verify the Settings controls, Core Motion history, locked-screen resume, or phone energy.
- `git diff --check` passed before this evidence record was added.

## Physical installation preflight, 2026-10-12

The inspected product revision was `99cc2923c0187c99149987663bcf63287de471ae`,
with Xcode 27.0 (27A266a). No tracking policy or application code changed.

- Full `xcodebuild test` passed on the iOS 27.0 (24A434) iPhone 18 Pro
  simulator: 236 tests passed, zero failed or skipped, as reported by
  `xcresulttool get test-results summary`.
- The Debug study build passed for `generic/platform=iOS`, first unsigned and
  then with automatic development signing. Its built `Info.plist` resolves
  `com.jeremybraff.fogofwalk.study`, display name `Fog Walk Study`, version
  1.0/build 1, minimum iOS 18.6, the Motion permission description, and the
  location background mode. `codesign --verify --deep --strict` passed; the
  embedded development profile covers the study identity and allows debugging.
- Signing initially failed for a missing Xcode account, then for Apple's updated
  Program License Agreement. The owner completed sign-in and agreement acceptance.
- USB development discovery initially exposed only a restorable representation
  with unsupported pairing. Reconnection and restarting the Mac's CoreDevice
  service did not fix it. After the owner restarted the phone and reconnected it,
  CoreDevice reported a paired, connected, wired physical device with Developer
  Mode enabled. The owner explicitly authorized development pairing for the study.
- The device is an iPhone 15 Pro Max running iOS 26.6.1 (23G83). Device identifiers
  are omitted from this record.
- `devicectl device install app` successfully installed the separate study app.
  `devicectl device process launch` launched it without a debugger or console
  attachment, and the installed-app query confirmed version 1.0/build 1. This
  does not establish location permission, capture correctness, or motion history.

## Audit findings and remaining physical checks

`MapContainerView` enables `showsUserLocation` and follow mode, adding a foreground
location consumer. Apple's
[showsUserLocation reference](https://developer.apple.com/documentation/mapkit/mkmapview/showsuserlocation)
and [user-location delegate reference](https://developer.apple.com/documentation/mapkit/mkmapviewdelegate/mapview(_:didupdate:))
do not establish measured background resource use on the study phone. Physical
trace inspection remains necessary before declaring the background-consumer
check passed. Any map behavior change must apply to both arms and invalidate
affected legacy measurements under the fixed protocol.

The motion query records the first activity marked walking and raw confidence;
it does not calculate an onset uncertainty bound. The pilot must compare that
history with independently noted departure time and marked route distance before
formal departure scoring. Stopping diagnostic capture stops logging, not the
legacy location tracker; study location permission must be disabled before
restoring normal-app permission if no other tracker-stop mechanism is used.

## Stationary diagnostics and motion preflight, 2026-10-12

The owner confirmed normal/TestFlight app location permission was set to Never,
with Always and Precise Location enabled for Fog Walk Study. Diagnostic capture
was started explicitly in the app, the study app was relaunched through
`devicectl` without a debugger, and the owner stopped capture and successfully
queried Motion history. The stopped files were copied through the development
connection to a private local temporary directory; only aggregates are recorded
here. The app's Share sheet export flow has not yet been exercised.

The 89.8-second stationary capture contained 18 well-formed JSONL records:
one capture start, one process relaunch, one capture stop, three batches, three
samples, and three downstream events, plus lifecycle records. Each one-sample
batch recorded its complete sample set and forwarded its original last sample;
there were no batch-contract mismatches or recorded errors. All three samples
had finite valid coordinates and accuracy within 25 m. Two samples were older
than 15 seconds; the remaining sample predated the newly relaunched source
session. Shadow decisions were two staleOrFuture and one beforeSession, with
zero accepted samples. All three were still forwarded by the legacy pipeline,
as required for diagnostics-only measurement, and no new cells were inserted.
This verifies cached-sample logging, not fresh-fix delivery or route coverage.

An authorization-change event reported Always status. Precise Location and
normal-app permission isolation are owner-confirmed, not independently queried
from the OS. Capture resumed in the same log after process relaunch.

The motion reference's interval matched the capture boundaries. Activity and
pedometer history were available. It contained five activity records with high
confidence, no walking records, zero steps, and no walking-onset distance
points. This stationary run verifies permission and historical-query workflow;
it does not bound walking-onset or nonzero-distance error.

## Walking diagnostics and motion rehearsal, 2026-10-12

The owner reported roughly six minutes stationary followed by a roughly
seven-minute walk, then stopped diagnostics and successfully queried Motion
history. The stopped files were copied into a private local temporary directory.
The route name, coordinates, cell addresses, exact wall-clock times, and file
identifiers are omitted. The owner subsequently confirmed one full closed loop
with no extra walking. At the owner's request, public OpenStreetMap road
geometry was retrieved and its segment lengths calculated independently of the
app's location stream: 323.6 m along the loop street plus 51.0 m along its
connecting street, or 374.6 m total (about 0.233 miles). This is a mapped road
centerline estimate, not a physically marked sidewalk measurement. Map geometry
and exact paths remain private. Timing precision and any pauses have not yet
been established.

The 828.8-second capture contains 88 well-formed records, with matching capture
and Motion interval boundaries, 25 one-sample batches, 25 forwarded samples, and
25 downstream events. Original-last-sample forwarding and required sample fields
have no contract mismatches. Nine new cells were inserted. There are no recorded
location errors. All coordinates are finite and valid. The shadow validator
accepted 24 samples, with receipt ages of 0.037–0.097 seconds and horizontal
accuracy of 2.1–14.0 m. The first sample was rejected only for accuracy (29.8 m)
and was still forwarded by the unchanged legacy policy. Its downstream cell was
already visited and was also recorded by later accepted samples; excluding that
one sample would not remove a newly visited cell in this trace. This verifies fresh
sample logging and actual downstream processing; it does not establish complete
route coverage or justify the provisional accuracy threshold.

Motion history contains nine high-confidence activity records, including three
walking records. The whole capture reports 620 steps and an estimated 421.2 m.
The whole-capture estimate is 46.6 m (12.5%) greater than the mapped centerline
loop. That single comparison has unbounded map/sidewalk uncertainty and is not
a calibrated pedometer error bound. The first reported walking transition occurs
about 63 seconds after the owner's
approximate departure time. That comparison has unbounded manual timing error;
it is not a measured 63-second detection delay. The cumulative distance timeline
starts at that reported transition and ends at 559 steps and 384.1 m, excluding
61 steps and 37.1 estimated metres counted elsewhere in the capture. Those
earlier steps cannot be attributed solely to the route or to phone handling
from these files.

The first shadow-accepted sample was received 42.3 seconds after the reported
walking transition, about 106 seconds after the approximate manual departure.
The timeline reports zero steps through 45 seconds after the transition, yet
the whole capture includes earlier steps. A zero timeline value therefore
cannot establish zero departure distance. Without bounded independent onset
and route-distance error, this rehearsal does not qualify the motion reference
or score the 100 m departure gate. No energy trace was collected for this run.

Share sheet export, bounded walking-reference uncertainty, mapped-route coverage,
background MapKit resource inspection, protocol-qualified legacy baseline, and
cause attribution remain unverified. The earlier short Power Profiler traces
remain exploratory. No energy saving or candidate reliability is claimed.


## Capture-origin motion report and reinstall, 2026-10-12

The study-only historical report now exports schema version 2. Every pedometer
query starts at capture start, preserving steps before walking classification
and movement with no walking classification. Full-capture sampling uses at most
80 coarse endpoints; a clamped 15-second detail window spans two minutes before
reported walking through ten minutes afterward. The union requires at most 129
queries even after overnight idle. Exact endpoints and cadences are exported;
the last query supplies both the final timeline point and whole-capture totals.
The capture origin, lookback window, and sampling resolution are not bounds on
manual departure time, classification delay, or pedometer error. See the updated
[diagnostic contract](location-energy-baseline-protocol.md).

Eight new XCTest regressions cover delayed classification with 61 preceding
steps, movement without walking classification or distance availability,
overnight idle with bounded queries and full interval coverage, short/fractional
capture endpoints, unordered activity history, invalid intervals, query errors,
and versioned JSON labels. The existing legacy tracking and last-sample-forwarding
tests remain unchanged. The full `xcodebuild test` suite passed on the iOS 27.0
(24A434) iPhone 18 Pro simulator: 244 passed, zero failed or skipped, confirmed
with `xcresulttool get test-results summary`. No warnings were reported in the
new motion source or tests; unrelated existing Swift 5 concurrency warnings
remain in the project.

A Debug build for `generic/platform=iOS` passed with automatic development
signing, the same separate study identity and display name, and a build-number
override of 2 (version 1.0). Signature verification passed. The phone remained
an iPhone 15 Pro Max on iOS 26.6.1 (23G83), with Developer Mode enabled.
`devicectl device install app` replaced the study app in place without an
uninstall or container reset; the installed-app query confirmed build 2.
All four previously listed study capture/reference files were still present
with unchanged sizes and modification dates after installation. This metadata
comparison does not independently verify every byte or the exploration store.
The first launch attempt was denied because the phone was locked. After the
owner unlocked it, launch succeeded without a debugger or console attachment.

Existing documentation from the physical rehearsals is preserved above. No
location-service, map-consumer, exploration, retention, or tracking-policy code
changed. At this reinstall checkpoint, version 2's physical historical-query
behavior had not yet been exercised; the following section records the subsequent
report-check pilot. Share
export, motion-reference qualification, formal baseline, cause attribution,
and battery improvement remain unverified. No departure gate was rescored.


## Build-2 physical motion-report pilot, 2026-10-12

The owner completed a fixed sidewalk out-and-back using an actual turnaround
that differed from the initially proposed one. The owner reports a Google Maps
estimate of approximately 200 m each way, or 400 m total. This estimate was not
independently retrieved or physically measured. Route addresses, coordinates,
cell identifiers, exact wall-clock times, and raw file names remain private.
The owner has an Apple Watch Series 7 (GPS), and was instructed to use timing
only rather than start a workout that could use the paired phone's GPS.
Bluetooth audiobook playback was permitted as a report-check pilot condition;
actual playback and absence of a watch workout were not independently verified.
This was not a controlled energy trial.

The installed-app query confirmed study version 1.0/build 2. Capture was stopped
and a matching schema-version-2 motion report had already been generated on the
phone. The files and capture-state preferences were copied through the connected
development service into a private local temporary directory for analysis.
The 928.6-second capture contains 80 well-formed JSONL records: one capture
start, one capture stop, 22 one-sample batches, 22 samples, 22 downstream events,
and lifecycle records. All batch/sample counts, required sample fields, and
original-last-index forwarding match the diagnostic contract. Coordinates are
finite and valid. All 22 samples are shadow-accepted, with receipt ages of
0.085–0.107 seconds and horizontal accuracy of 2.0–4.7 m. Three new cells were
inserted. No location-error event was recorded. These counts verify logging and
unchanged legacy delivery; they do not independently prove full route coverage.

The matching post-run report declares capture start as its timeline origin and
matches the capture's end. It contains four activity records (raw confidence 2),
including one walking record, and 92 unique, increasing query endpoints, all
inside the capture interval and matching the exported plan. Both coarse and
detail cadence are 15 seconds. Cumulative steps and metres are nondecreasing,
and the last point matches whole-capture totals of 587 steps and 385.8 estimated
metres. At the first reported walking classification, the timeline already
retains 20 steps and 14.0 estimated metres. This physically verifies that the
new report preserves pre-classification counts; it does not establish that all
those earlier steps belong to the intentional walk.

The first shadow-accepted fix was received 3.1 seconds after reported walking
classification. Adjacent cumulative points through that receipt contain 20–22
steps and 14.0–15.5 estimated metres **from capture start**, not independently
validated distance from actual departure. The whole-capture estimate is 14.2 m
(3.5%) below the owner's approximate 400 m map estimate. That difference is not
a calibrated pedometer error bound: map rounding, sidewalk path, capture-window
movement, and exact departure/return alignment remain uncertain.

The owner initially supplied minute-level wall-clock times, then clarified that
an elapsed timer showed departure at 10 minutes 18 seconds and a total time of
15 minutes 35 seconds, implying a reported walking interval of 5 minutes
17 seconds. The owner is unsure of timer/capture alignment and estimates that
they started within about five seconds. Their alignment was not recorded.
The diagnostic capture is 6.4 seconds shorter than the timer's reported total,
so the five-second guess cannot be adopted as a demonstrated timing-error bound
or an exact shared origin. The timer finish's relation to capture Stop also
was not established. Do not infer the missing anchor from the location stream
or walking classification under evaluation.

The build-2 physical reporting check passed. Walking-reference qualification,
exact departure scoring, bounded route/pedometer error, Share-sheet export,
background MapKit resource inspection, formal energy baseline, and cause
attribution remain unverified. No energy trace was supplied or analyzed for
this pilot. No source policy, numeric gate, or battery-benefit claim changed.

## Reference preparation review, 2026-10-12

The build-2 pilot was reviewed against its recorded timing and distance limits
before requesting further walking. No raw capture was reanalyzed, no timing
anchor was reconstructed, and neither pilot was rescored. Both initiative
branches were fetched; each HEAD matched its remote initiative branch, while
task-owned working-tree changes remain local and uncommitted.

The [reference qualification addendum](location-energy-reference-qualification.md)
defines stopwatch brackets around capture Start and Stop, independent departure
and return observations, actual-path measurement with stated instrument and
endpoint uncertainty, and early-distance checkpoints. Return is separate from
Stop. Boundary offset agreement does not establish interior clock stability.
Checkpoint progress, reported pedometer distance, and the uncertainty interval
used for scoring must be reported separately. Whole-route agreement does not
calibrate early distance.

An independent GPT-6 Astra reviewer approved this as a preparation procedure
after three findings were resolved: distinguish stationary/conditional short-
pilot feasibility from formal qualification; keep the pedometer metric and its
future-use uncertainty envelope explicit; and define outbound versus return
checkpoint passages and the broad fallback outside the instrumented corridor.
The reviewer found no remaining document blocker. This review does not qualify
any physical reference or change the strict 100 m threshold.

The owner was asked which physically measured route or tape/wheel reference is
available. That answer, observation practicality, clock stability, local
pedometer/history timing error, and applicability after long idle remain pending.
The immediate no-walk preparation option is a stationary Start/Stop bracket
rehearsal; it has not been performed or requested in this continuation. No
additional walk, installation, source change, or energy measurement occurred.

Whitespace and relative-link checks passed, and synthetic stopwatch-offset
arithmetic was checked separately from physical evidence. The motion source
and new, untracked regression-test file remain byte-identical to their takeover
state. This continuation changes documentation only; the recorded 244-test
result above was not rerun. Reference qualification, MapKit background resource
use, formal baseline attribution, reliability, and battery benefit remain unverified.

The owner subsequently proposed recording a starting fix before stationary idle.
The reference addendum now treats that as a setup check, taken before idle to
avoid foreground rearm immediately before departure. First-fix latency and
displacement from start can be reported as exploratory observations; the latter
does not establish cumulative walking distance during missing updates. A focused
independent Astra review found no gate weakening and requested one clarification,
now resolved: both fixes' reported horizontal-accuracy estimates are not validated
error bounds. The formal pedometer screen and stationary-energy controls remain
unchanged. No physical check or further walk was requested in this discussion.

## Stationary timing rehearsal, 2026-10-12

The owner completed a stationary rehearsal and then connected the phone. A local
CoreDevice query confirmed the paired wired iPhone 15 Pro Max on iOS 26.6.1
(23G83), with Fog Walk Study version 1.0/build 2 installed. The latest stopped
capture and study capture-state preferences were copied to a private local
temporary directory. Log Start/Stop match the preferences within one millisecond;
capture is inactive. Identifiers, exact wall-clock times, and raw files stay private.

The capture lasts 369.507 seconds (6:09.5) and contains 11 well-formed records:
one Start, one Stop, five scene-phase events, two foreground rearms, and two
tracking start/rearm events. Background appears at +7.845 s, with inactive and
active return events at +367.441 s and +368.154 s. A transient active/rearm at
+7.815 s precedes background. These are app lifecycle observations, not exact
physical lock/unlock timestamps. No batch, sample, downstream, relaunch, or
location-error event was recorded. This run verifies persisted boundary/lifecycle
logging; it does not verify a fresh pre-idle fix or demonstrate tracking success
or failure from callback silence.

The owner reports starting capture and stopwatch at the same time, locking at
7.02 seconds, unlocking 5:59 later, and stopping capture 4.67 seconds later, with
a 6:12 stopwatch total. No before/after Start/Stop brackets were supplied. The
reported component intervals sum to 370.69 seconds, 1.31 seconds below the
reported total. The total exceeds the logged capture by 2.493 seconds. These
discrepancies do not identify a clock offset, assign error to an endpoint, or
provide a validated uncertainty bound. No independent departure or motion
reference, energy trace, or battery result was supplied.

An independent Astra reviewer checked the redacted summary and agreed that no
further short stopwatch rehearsal is needed before stationary energy collection.
It required an explicit minute-10–120 origin and verified trace alignment/coverage,
while preserving all controls, background-consumer inspection, and attribution.
The baseline protocol now fixes that origin at diagnostic capture Start; trace
metadata must establish the mapping, otherwise the run remains inconclusive.
The owner was asked for current battery percentage to prepare the two-hour
stationary run. That run has not started. No walking gate, clock calibration,
MapKit background audit, formal baseline attribution, or battery benefit is passed.
No app code, tracking policy, installed identity, or container changed.

The reviewer also approved the stationary origin/capture-order clarification
for preparation only, recommending a modest end buffer without changing the
analysis interval. The protocol now includes that buffer and requires recorded
coverage and display/wake evidence. Trace time-base mapping remains unverified.
The owner subsequently reported uncertainty about finding a two-hour test window;
no battery percentage was supplied and no energy run was scheduled or started.
Retain the prepared method for a convenient unused-phone window; do not request
another short rehearsal or infer any energy outcome from the stopped timing run.

## Stopped diagnostic Share/AirDrop export, 2026-10-12

The owner exported the existing stopped stationary diagnostic log through the
study app's Settings Share flow and AirDropped it to the Mac. The received file
matches the privately retrieved phone copy byte-for-byte: 821 bytes, 11 records,
one Start/Stop pair, and 369.507-second duration. The physical diagnostic-log
Share/AirDrop preflight passed. Raw files, file names, and exact times remain
private. No additional Motion query or export is needed for this transport check;
Motion Share export remains separately unverified.

No new capture, energy measurement, app change, or walk occurred. This result
does not calibrate stopwatch alignment, qualify walking-reference distance, or
establish energy attribution. The next collection step remains the prepared
stationary baseline when the owner has a convenient unused-phone window.

## Long stationary capture received, 2026-10-12

The owner reports completing a test longer than two hours without unlocking until
the end, then AirDropping its diagnostic log and Motion Reference. The received
diagnostic file has 516 bytes and seven well-formed records, with one Start/Stop
pair spanning 8407.367 seconds (2:20:07.4). Record timestamps are nondecreasing and
within the capture. Background is recorded at +2.222 s; inactive/active return is
recorded at +8406.080/+8406.571 s, followed by foreground rearm, tracking rearm,
and Stop. No lifecycle event falls in the fixed primary interval, +600 through
+7200 s. App lifecycle observations are consistent with the owner's report; they
are not independent screen-lock or display-state evidence.

No batch, sample, downstream, relaunch, or location-error event was recorded.
Callback silence does not demonstrate tracking success or failure, a stopped
tracker, sleep, or low energy consumption.

The received schema-2 motion report matches the diagnostic boundaries exactly.
Both history services report availability. All 71 cumulative endpoints are
strictly increasing, lie within the capture, and match the declared plan; the
last endpoint equals Stop. The coarse cadence is 120 seconds, with no walking
classification or detail window. Whole totals and every endpoint report zero
steps and zero estimated metres. Five activity records contain no walking,
running, cycling, or automotive flags; some records have no activity flags at all.
This supports the stationary observation without treating classification or zero
pedometer values as exact proof that the phone never moved. Motion Share/AirDrop
was exercised for this matched report; no comparison with an independently
retrieved phone copy was made in this run.

Only the earlier exploratory power recordings were found in Downloads at this
inspection. The owner was asked whether Power Profiler ran and to export its trace
if recorded, answered that they are unsure, and was asked to check the saved-trace
list before another recording. A new-run energy result is pending that trace, capture/trace mapping,
valid full primary coverage, display/sleep and thermal evidence, trial-control
confirmation, MapKit background-consumer inspection, and cost attribution. Start/
end battery, charging, Low Power Mode, Always-On Display, network, settling,
normal/study tracker isolation, and Xcode-disconnection controls have not yet been
confirmed for this run. Do not substitute old power data or classify this as a
qualified baseline, reliability gate, or battery benefit.

Raw files, names, and wall-clock timestamps remain private. Source and the
untracked motion regression tests are preserved; no app change, new test run, or
request for another physical recording is part of this receipt check.

### Subsequently received power archives

The owner found two saved traces that appeared older and AirDropped both. The
received archives match the earlier files already on the Mac byte-for-byte.
Private extraction, import into separate saved `.trace` copies, and table-of-
contents export succeeded. Both recorded intervals are from 2026-10-10 in the
owner's timezone: 1688.056 seconds and 894.047 seconds. Their timezone-bearing
Start/End metadata agrees with each declared duration within one millisecond.
Neither interval overlaps the new 8407.367-second diagnostic capture. This
conclusion uses recorded metadata, not AirDrop file dates or names.

These archives cannot provide energy data for the new stationary test and must
not be substituted for it. The owner was asked whether Performance Trace is still
recording; if so, stop it and export the newly saved trace. The owner cannot tell
its state. A screenshot of the Control Center trace control is the next inspection
step; do not toggle it blindly. No matching power trace is currently available
for analysis, but the
received files alone do not establish whether profiling never started, remains
active, or produced another unlocated trace. Do not request a repeat until the
existing recording's availability is resolved. Diagnostic/Motion receipt checks
remain valid; formal energy qualification, attribution and battery benefit remain
unverified. Raw archives, working copies and timestamps stay private.

The next owner-supplied screenshot shows the Performance Trace settings page:
Enable Performance Trace is on, Power Profiler is selected, and both the study
and normal Fog apps are selected under Monitored apps. Those switches select
profiling targets, not location permissions. The visible saved trace is an older
recording. This establishes current configuration only; it does not establish
recording state, configuration during the completed test, or tracker isolation.
Inspect the actual Control Center Performance Trace control next, leaving these
settings unchanged while resolving the existing recording.

The owner subsequently reports forgetting the setup/control step and asks whether
the test needs repeating. The exact omitted step has not been named. If Performance
Trace was never started in Control Center, this run has no recoverable power
measurement and cannot qualify the energy baseline; repeat the energy recording
at a convenient future window with both Power Profiler and diagnostics running.
The existing diagnostic and Motion receipt checks remain valid. No earlier
installation, motion-report pilot, or export preflight needs repeating for this
reason. Changing profiling targets alone would not establish that no recording
occurred. Confirm the missed start step or recover a matching trace before a final
disposition; do not infer an energy rate from the available exports. No repeat
window has been agreed and no new recording has started.

## Matching stationary power recording received, 2026-10-13

The owner supplied three new Downloads exports after a multiple-hour test,
reporting that the screen stayed locked and the phone did not move. Raw files were
copied for private inspection; file names, coordinates, device identifiers and
wall-clock times remain outside Git. No source, installed build or tracking-policy
change was made.

The diagnostic capture spans 13057.462 seconds (3:37:37.5), with 29 well-formed
records and one Start/Stop pair. Background is recorded at +3.242 seconds and the
first return at +13051.990 seconds. There is no lifecycle return in the fixed
+600 through +7200-second primary interval. Six single-sample legacy batches have
six corresponding downstream records. All samples are shadow-accepted and
forwarded, with recorded ages 0.008–0.023 seconds; two occur in the primary
interval. No new cell was inserted. These counts do not measure energy or prove
physical resume reliability.

The new power archive was extracted, imported once into a saved private `.trace`,
and exported from that same copy with Xcode 27. Its device metadata reports
iOS 26.6.1 (23G83). The recording spans 13056.729 seconds, starts 2.682 seconds
before diagnostic Start, and ends at diagnostic +13054.046 seconds. Its declared
duration and timezone-bearing Start/End difference agree within one millisecond.
The recorded interval covers the entire predeclared primary interval without
moving its origin. Power ended about 3.416 seconds before diagnostic Stop, a
deviation from the intended stop order outside the primary interval; retain it
in review rather than shifting the analysis window.

| Export check | Finding |
| --- | --- |
| System power | 13056 rows overall; 6601 finite, nonnegative rate intervals intersect the primary window; none has a zero rate. |
| Primary power coverage | 6599.999725 seconds of exported valid duration out of 6600 seconds; no overlap. Sub-microsecond gaps total 0.275 ms, with a largest gap about 42 ns. No gap is imputed. |
| Provisional whole-device rate | Duration-weighted mean over the exported valid primary intervals: 1.542% battery/hour. Retained range: 1.022–27.590%/hour; no unfavorable samples were removed. |
| Display | Zero reported brightness throughout the primary interval, with full interval coverage in the display table. Two brief brighter intervals later in the recording occur after +7200 seconds; retain them without assuming user unlock or moving the primary window. |
| Thermal | Nominal throughout the primary interval and recording. |
| Charging and sleep | Both exported tables contain zero rows. Absence does not prove uncharged state or expected sleep/wake behavior. |
| Process impact | 28393 rows overall and 14358 intersecting the primary interval, all named `Fog-Of-Walk`, for one process. CPU, display, GPU and networking fields are available. |

Resolve XML references before using fields. Exported start/duration values are
nanoseconds; rate fields are already percent per hour. The small exported interval
gaps remain explicit rather than asserting mathematically complete power coverage.
A separate Decimal-arithmetic calculation reproduced the valid duration,
0.274951 ms total gap, 42 ns maximum gap and mean to nine decimal places.
The provisional mean is a whole-phone observation, not Fog's isolated cost, a
validated battery-saving percentage, or a qualified baseline result.

The executable name is shared by normal and study builds. Trace process metadata
contains that name but no usable bundle path; the study bundle identifier was not
found in the private working trace. The corresponding app identity therefore
remains unverified by this export. Do not attribute all process rows to the study
app on name alone. Background MapKit consumption and the largest actionable cost
remain unresolved.

The supplied Motion file is byte-identical to the previous 8407.367-second report.
It does not match this new capture and is excluded. The study's saved Motion export
can refer to an older query; future motion references must be matched to capture
boundaries. No new Motion query is required to inspect this stationary power
recording, and no new walking-reference qualification is claimed.

The owner was asked to confirm unplugged/Xcode-disconnected operation, normal-app
permission Never, study Always/Precise permission, Low Power Mode and Always-On
Display off, settling, stable network, and starting/ending battery percentages.
Those controls, pending work/backfill, trace sleep/charging evidence, app identity,
export-gap interpretation and cost attribution still require review before formal
baseline qualification. The file receipt and timing checks support continued
analysis; no repeat is requested solely because of the stale Motion export or
the trace's start/end placement. Retain Active at m1 and legacy behavior.

### Owner-confirmed controls and bounded attribution follow-up

The owner confirms all requested non-battery conditions: unplugged operation,
Xcode disconnection, main Fog location Never, study Always/Precise permission,
Low Power Mode and Always-On Display off, at least ten minutes settling and stable
network. The earlier stationary/locked observation remains owner-confirmed.
Starting and ending battery percentages were not recorded; the battery-range
condition is unverified. These are owner observations, not independent telemetry.
Pending backfill was not part of that confirmation and remains unverified.

The power-rate calculation does not require manually subtracting battery levels,
but missing levels prevent verification of the fixed battery-range condition.
Classify this run as exploratory/inconclusive for formal qualification; preserve
its files and provisional whole-device mean. Do not infer the starting state of
charge from the mean or silently relax the protocol.

Further private exports succeeded: `StateReportingIntervals` has zero rows and
`ProcessLifecycleChange` has one row. Neither supplies battery levels, sleep state
or the study bundle identifier. The primary process export has 6601 finite CPU,
display and GPU impact rows, and 1156 networking impact rows; all numeric impact
values are zero. All 28393 exported CPU-instruction fields are zero, including
14358 primary rows. This does not demonstrate zero app/CPU/GPS cost or establish
that stationary tracking is immaterial. Attribution, app identity, metric
availability/resolution and native-versus-export interpretation remain unresolved.

The [attribution preparation draft](location-energy-attribution-preparation.md)
records instrumentation checks and the proposal's conditional stationary-only
control. It is prepared for review, not a new approved measurement policy or
request for another phone test. No source or tracking change was made; the existing
244-test result was not rerun for documentation and read-only analysis.

Native Instruments inspection was attempted but the Mac was locked and the UI
tool could not unlock it. No trace was visibly inspected in Instruments. The
native-versus-export comparison remains pending until the owner unlocks the Mac;
command-line findings and the preparation draft remain available. This is a
local inspection limitation, not a request to repeat the phone recording or a
lifecycle change.

The owner subsequently clarified that both starting and ending battery levels
were between 40% and 80%, despite not retaining exact percentages. Record both
endpoints as owner-confirmed within the protocol band and their exact values as
unknown. This resolves the previously unverified battery-range condition without
inventing measurements or changing the range. Missing exact percentages alone
are not grounds to repeat this run. Formal baseline qualification still awaits
app attribution, sleep/wake and other outstanding trace evidence; no battery
benefit or tracker-replacement decision is established by this clarification.

### Native Instruments check after Mac unlock

The owner confirmed the Mac was unlocked. The saved private `.trace` was opened
in Instruments and inspected across the complete 3:37:36 recording. The native
system summary reports 1.9%/hour for the whole recording. The whole-recording
duration-weighted export calculation gives 1.931250%/hour, consistent at the
native summary's displayed precision. This is a different interval from the fixed
primary mean of 1.542%/hour; neither replaces the other.

The expanded native Fog app-impact track reports zero CPU, GPU, display and
networking averages and a Suspended lifecycle across the full recording. The
exported lifecycle row likewise spans 13056.729 seconds with label Suspended.
Thus the all-zero app fields are not merely absent from the XML export. The
native sleep and charger lanes contain no intervals, matching their empty
exports; native inspection did not recover missing sleep/wake evidence.

Native graphics/Symbols views contain another Fog process with a different
process identifier. The whole-run CPU sample tree also includes locationd,
GNSSLocationService and gpsd, as well as the profiling process. CPU sample weights
are not battery percentages, elapsed CPU utilization, or attributable Study
energy. No primary-window app-cost conclusion is drawn from that whole-run view.
Binary metadata did not establish the other Fog process's study identity.

A bounded, read-only CoreDevice lookup succeeded on the already paired phone.
The current Fog executable corresponding to the native app-impact process
identifier maps to the normal app, version 1.0/build 11. The separate study app
remains installed at version 1.0/build 2. Matching a current process identifier
does not independently exclude historical identifier reuse, but together with
the full-run Suspended track and separate Fog process it strongly supports a
wrong or stale profiler target. Do not interpret the zero normal-app impact as
zero study-tracking cost. Raw process identifiers, app container paths and device
metadata remain private.

The earlier profiler-settings screenshot had both Fog apps selected. That was
configuration evidence at its own observation time, not proof of selection during
this run. The guidance should have made Study-only profiler monitoring explicit.
The next useful check is a brief foreground recording with only Fog Walk Study
selected under Monitored apps, before spending another long stationary window.
Keep normal-app location Never and study Always/Precise; profiler switches are
separate from tracking permissions. Inspect the saved result for the active
Study target/lifecycle before a formal energy comparison. This targeted setup
check is justified by the new attribution finding; do not repeat generic pairing,
motion-history or stopwatch rehearsals.

The [preparation document](location-energy-attribution-preparation.md) now gives
the concrete short procedure. The existing whole-phone measurement and confirmed
controls are retained, but formal attribution and sleep/wake qualification remain
open. No candidate, production tracking change, new walk, long test or battery
benefit is claimed. The original power archive remains byte-identical to its
receipt hash; inspection changed only the private working copy's UI state.

### Coupled profiler switches and distinct Study build 3

The owner reports that disabling profiler monitoring for normal Fog also disables
Study, with the switches changing together. This blocks the proposed Study-only
target selection; no successful selection or short targeting capture is claimed.
The project gives both copies `Fog-Of-Walk` as product, bundle and executable name,
despite separate bundle IDs and display names. Shared naming is a plausible
explanation for the observed coupling, not a verified statement about iOS's
internal profiler key.

A Study-only packaging workaround was built with invocation overrides:
`PRODUCT_NAME=Fog-Walk-Study`, `CURRENT_PROJECT_VERSION=3`, the existing study
bundle ID, and the existing Fog Walk Study display name. Checked-in project,
Info.plist, motion implementation and untracked motion tests were unchanged.
The built bundle name and executable are both `Fog-Walk-Study`; the Swift module
remains `FogOfWalk`. Legacy manager behavior, forwarding, model/store identity,
permissions and source defaults are unchanged.

The normal full simulator XCTest suite passed all 244 tests, zero failures and
zero skips. The signed physical Study build succeeded; strict signature,
study entitlement and provisioning-for-the-known-phone checks passed. Before
installation, capture was confirmed inactive and app preferences/Application
Support were privately copied. The update used the same study bundle ID without
uninstalling or resetting its container. All 14 original Application Support
files were byte-identical immediately after installation and before launch;
saved capture preferences were preserved and capture remained inactive.

CoreDevice confirms Study 1.0/build 3 installed as `Fog-Walk-Study.app`, with normal
TestFlight 1.0/build 11 unchanged. Debugger-free launch succeeded, and the running
study process has the distinct `Fog-Walk-Study` executable basename. Raw signing,
device and app-data evidence remains private. This verifies packaging, tests,
installation and data retention; it does not verify profiler-switch independence
or a corrected power target.

The owner was asked to reopen Performance Trace settings and verify Study on with
normal Fog off independently, leaving tracing stopped. That answer is pending.
If coupling persists, resolve it before the roughly one-minute foreground targeting
capture. No new walk, long recording, candidate tracker or battery benefit is
claimed. Use the same build/identity for all future comparison arms, and retain
the existing build-2 measurements with their original metadata and limits.

### Owner selector response and next targeting capture, 2026-10-13

After being asked to reopen Performance Trace and check Study on with normal Fog
off, the owner reports that it works better and requests the next-test procedure.
This is recorded as owner-reported selector success on installed Study build 3,
not independent inspection of the phone UI or proof of the saved trace's target.
The next capture is roughly one minute in the foreground, with a brief map pan:
Power Profiler monitoring Study only, normal location Never, Study Always/Precise;
start Performance Trace before Diagnostic Capture, then stop Diagnostic Capture
before Performance Trace and export both files. No exact stopwatch timing, walk,
screen lock or Motion query is needed for this instrumentation check. Inspect
matching boundaries, distinct Study identity and foreground lifecycle before any
long window. No new recording, energy result or tracker change is confirmed.

### Build-3 foreground targeting preflight, 2026-10-13

The owner completed the requested short check and AirDropped a new diagnostic
log and power archive. Private extraction, one saved xctrace import and
schema/reference-aware exports succeeded. Both original source hashes remain
unchanged. Raw files, process IDs, exact timestamps and location data stay private.

The diagnostic lasts 47.290 seconds and has nine valid records with one Start/Stop
pair. Its one single-sample legacy batch is shadow-accepted and forwarded once;
sample age is 0.081 seconds and horizontal accuracy 4.852 metres. No new cell is
inserted. A short inactive/active transition occurs near the end, with foreground
rearming; this is not a locked-screen or stationary-energy trial.

The power recording lasts 52.960 seconds. Its timezone-bearing metadata maps
Start to 4.016 seconds before diagnostic Start and End to 1.654 seconds after
diagnostic Stop, covering the complete diagnostic capture. Metadata duration
rounding differs by 0.123 ms. The monitored process is exclusively
`Fog-Walk-Study`, matching the unique executable of the verified installed build
3. It has 114 app-impact rows and 53 system-power rows. There are 53 positive CPU
impact rows, 53 positive display rows, 45 positive GPU rows and 53 positive CPU
instruction rows. Sentinel fields remain unavailable, not zero; networking has
nine numeric zero rows and 105 unavailable rows, which do not prove no networking.

The app lifecycle is Unknown for the first 16.969 trace seconds, then Foreground
for 35.991 seconds (beginning at diagnostic +12.953 seconds). Foreground activity
and nonzero app work establish this preflight's target/data-availability check;
the whole run is not asserted to have a known foreground classification. This
resolves the short-targeting gate that the earlier Suspended normal-app trace
could not pass. It establishes neither background attribution nor a battery rate
or saving. No generic one-minute repeat, Motion query or walk is needed.

Next finish locked-screen measurement readiness before requesting another long
window: verify Xcode disconnection, a way to inspect sleep/wake evidence, and the
background MapKit location-consumer audit. The current source still enables
`MKMapView.showsUserLocation` and does not disable it on background entry; this
identifies a potential additional consumer, not measured background cost. Legacy
source/settings are unchanged. Apple documents that Xcode connections prevent
silicon sleep and that sleep/wake events require disconnected on-device capture
([Power Profiler guidance](https://developer.apple.com/documentation/Xcode/measuring-your-app-s-power-use-with-power-profiler?changes=_8)).
The existing long-run empty sleep export remains unresolved; foreground success
does not fill that gap or qualify the old recording as Study-attributable energy.
