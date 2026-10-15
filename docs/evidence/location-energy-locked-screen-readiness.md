# Locked-screen measurement readiness

> Scope update, 2026-10-15: this document retains the earlier measurement procedure and its original evidence limits. Follow [Automatic stationary pause and walking resume](../proposals/2026-10-15-automatic-stationary-pause-and-resume.md) for current delivery. The long comparison/qualification gates and old next-test instructions below are historical, not prerequisites for the focused prototype and idle-to-walk check. Manual tracking OFF is not an automatic-resume candidate.


**Prepared:** 2026-10-13.
**Current isolation method:** Phone-side radio isolation; the development Mac
stays on and online. The owner's lack of Mac access supersedes the earlier
shutdown procedure. For the owner's geographically remote setup, isolation may
be accepted from the explicit connection-path checklist below; the live probe
remains inconclusive. Sleep/wake instrumentation still needs physical verification.
**Purpose:** Resolve the remaining instrumentation questions before another
two-hour stationary baseline. This is a specific background-readiness check,
not a repeat of the passed foreground targeting check, a battery comparison,
or a departure trial. Keep installed Study 1.0/build 3 and its data container.
The [baseline protocol](location-energy-baseline-protocol.md) and
[replacement proposal](../proposals/2026-10-09-location-energy-and-reliability.md)
retain their existing measurement windows and numeric gates.

## Preparation findings

The current source requests location through two consumers:

| Consumer | Source evidence | Remaining physical question |
| --- | --- | --- |
| Legacy tracker | `Services/LocationService.swift`: standard updates and significant-change monitoring start together; nearest-ten-metre accuracy, 15 m filter, automatic pausing disabled and background updates enabled. | Background delivery and tracking-dependent energy; a shared delegate does not identify which service produced each callback. |
| MapKit user location | `Views/MapContainerView.swift`: `showsUserLocation = true`, tracking mode `.follow`; no background-entry toggle in `FogOfWalkApp.swift`. | Whether it adds active background location work or changes the cost of a later source comparison. |

[Apple's MapKit documentation](https://developer.apple.com/documentation/mapkit/mkmapview/showsuserlocation)
says enabling user location uses Core Location and periodically updates the
location. Source inspection establishes a possible additional background consumer,
not its actual background activity or power cost. Geocoder requests and bundled
landmark searches are downstream work, not additional continuous location trackers.
Record their activity/backfill state separately when attributing a baseline.

Stop Diagnostic Capture stops logging only. It does not stop standard updates,
significant-change monitoring or MapKit user location. Permission isolation and
profiler target selection are separate controls. Keep normal Fog location Never
while Study has Always/Precise; after all Study testing, set Study location Never
before restoring normal Fog permission.

Apple's [Power Profiler guidance](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler)
states that an Xcode connection keeps Apple silicon awake and that sleep/wake
events require disconnected on-device capture. Preserve the development pairing;
do not unpair, reset, reinstall or erase either app for this check. A paired-device
listing is not evidence that a timed run is disconnected. Do not query the phone
or use Mac-side live profiling during the recording.

## Before starting

Use one private trial note for this check. Record the installed Study build,
phone/iOS build, battery percentage, Low Power Mode, Always-On Display, network
mode, charging state, settling time and any other phone use. Use the baseline's
40–80% battery range, Low Power Mode off, Always-On Display off, no serious initial
thermal state and at least ten minutes of settling after charging or active use.
Let pending geocoding/backfill finish. If its idle state cannot be established,
record that uncertainty rather than assume it.

1. In Settings > Privacy & Security > Location Services, verify normal Fog is
   Never and Fog Walk Study is Always with Precise Location on.
2. In Settings > Developer > Performance Trace, verify Power Profiler, Study
   monitoring on and normal Fog monitoring off. Finish any existing recording
   deliberately before starting a new one; preserve its saved file.
3. Leave the development Mac on and online. On the **phone**, turn Wi-Fi off in
   Settings > Wi-Fi and Bluetooth off in Settings > Bluetooth; turn Personal
   Hotspot off if enabled. Unplug USB and remove MagSafe charging. Leave cellular,
   Location Services, Developer Mode and profiler settings unchanged. Do not use
   Airplane Mode. Keep these radio settings through both recordings. This also
   disconnects Bluetooth accessories, including the paired watch/earphones.
4. Before settling or starting either recording, have the agent perform one
   bounded live CoreDevice connection check, such as `device info processes`,
   with private output. `list devices` alone can reflect known/cached pairing.
   Successful live communication means isolation failed. Require an actual
   unreachable/disconnected result consistent with the phone's recorded settings;
   a lock, authorization, syntax or local-tool error is not proof of disconnection.
   If a custom remote-device/VPN path is configured, resolve it separately.
   For a phone geographically remote from the Mac, an alternative for this
   bounded readiness check is explicit owner confirmation of physical separation,
   no USB, Settings Wi-Fi/Bluetooth off, hotspot off, and no active VPN or
   remote-device bridge. Record this as connection-path evidence, not a Passed
   live probe. An inconclusive probe alone never qualifies. This alternative
   does not establish sleep or qualify a formal energy baseline.
   End the probe before settling; no device queries or live sessions during
   capture. If either connection-path evidence or the live result is ambiguous,
   keep setup unresolved. Mac UI access is not required for the command-line check.
5. Let the phone settle for at least ten minutes with its final radio settings.
   Record this as a cellular-only readiness condition, separate from earlier
   Wi-Fi-on traces. Keep the Mac's network unchanged.
6. Confirm the Study diagnostics are inactive and there is no unresolved log
   write/full error. Leave Study ready to start capture. Keep permissions and
   installed build unchanged during the run.

Apple's [radio-control instructions](https://support.apple.com/en-us/102412)
distinguish fully disabling radios in Settings from the temporary Control Center
disconnection, which leaves connectivity features available. Apple's
[device-pairing documentation](https://developer.apple.com/documentation/xcode/pairing-your-devices-with-your-mac)
describes cable and wireless connections. Removing USB and fully disabling the
phone's Wi-Fi/Bluetooth/hotspot is the reviewed isolation design; physical setup
must be recorded at its actual evidence scope; sleep/wake evidence remains
unverified until the recording is inspected. Preserve pairing and
both app containers; no reinstall or Developer Mode change is required.

## Next phone check: stationary, locked for about 15 minutes

The duration bounds the setup effort; it is not an energy analysis window or a
guarantee that the phone will sleep. No walk, stopwatch calibration, route fixture
or Motion query is needed. Use another clock to note approximate lock and unlock
times; the phone itself stays untouched while locked.

1. Start Performance Trace in Control Center and confirm recording is active.
2. Return to Study > Settings and start Diagnostic Capture; confirm it is running.
3. Lock the phone promptly. Leave it stationary and unused for about 15 minutes.
4. Unlock, note the ending battery percentage, stop Diagnostic Capture, then stop
   Performance Trace. Stop both before restoring radios or reconnecting USB.
5. Restore the phone's original radio settings, then AirDrop the new stopped
   diagnostic log and saved power archive to the Mac. Preserve original files
   locally and identify them as one matched check. If transfer requires unavailable
   Mac interaction, retain the files on the phone until transfer is possible;
   the study app's seven-day cleanup still applies.
   Do not export an older saved trace or an unrelated Motion report.

## Inspection and decision

Import the archive once into a private saved `.trace`, export that copy's table
of contents and inspect native Instruments tracks. Resolve actual schema names,
units and XML references before interpreting data. Export available system
sleep, charging, display, thermal, process lifecycle and app-impact tracks;
an empty table is missing evidence, not a zero state. Keep raw traces, identifiers,
coordinates, filenames and absolute timestamps outside Git.

| Question | Evidence and disposition |
| --- | --- |
| Do log and trace match? | Map recorded trace metadata to diagnostic Start/Stop and independently noted lock/unlock. Report setup/end coverage and any gap; scene phases alone do not prove physical lock. |
| Is Study the monitored app? | Verify the distinct `Fog-Walk-Study` process. Background/suspended lifecycle or unavailable impact values must not be described as zero tracking cost. |
| Is sleep/wake evidence usable? | Inspect populated native sleep/wake intervals and the corresponding export. If empty, report unresolved: actual wakefulness and missing instrumentation remain different possible explanations. Do not infer sleep from a dark display. |
| Were controls preserved? | Check charging, dark display, thermal tracks, owner connection notes and other use. Missing telemetry remains an explicit limit even where the owner confirms a control. |
| Can background location consumers be attributed? | Inspect any available location-client/resource records, correlate with Study lifecycle and diagnostics, and distinguish MapKit work from app-manager work only where evidence identifies it. Generic `locationd` activity or Power Profiler CPU/GPU impact cannot identify the consumer. If this recording lacks the needed records, leave the MapKit physical audit open and specify the missing instrumentation. |

This check can establish locked-screen instrumentation readiness; it cannot prove
MapKit's absence, quantify energy savings or qualify the 100 m departure screen.
The source audit is complete, while physical consumer attribution remains pending.
Phone-radio isolation changes connectivity and may affect location behavior and
system power. Do not compare this readiness check's energy with the prior Wi-Fi-on
run or assert equivalent positioning. Any later matched energy arms must share
the same predeclared radio configuration and its settling conditions; separately
evaluate representative-use conditions. The numeric gates are unchanged.
If attribution remains ambiguous, review a study-only stationary diagnostic
control covering **all** location consumers under the existing proposal before
implementing or measuring it. Diagnostic Stop and callback silence are not that
control. Any map behavior change must be equivalent in both study arms, have
regression/full-suite verification and repeat affected legacy baseline measurements.

After reviewing this check, prepare the fixed two-hour stationary baseline with
its existing +600 through +7200-second window only when locked-screen
instrumentation is ready **and** attribution preparation is resolved or covered
by a reviewed attribution method. Correct targeting and populated sleep data
alone do not close the MapKit audit. If evidence is missing, specify the remaining
instrumentation or control work instead of repeating an equivalent trace. Empty
sleep data remains inconclusive; do not keep capturing until a favorable sleep
result appears. Preserve all adverse/inconclusive observations and the legacy
production default.

## Preparation review

The owner subsequently completed the remote readiness capture on 2026-10-14.
The matched approximately 34-minute exports establish Study background target
and data availability. Eight brief intermediate display-lighting events are
owner-reported notifications, with no phone use. Both exported and native
Instruments sleep lanes remain empty. Full findings and the unresolved
sleep/consumer-attribution gates are in the
[verification record](location-energy-diagnostics-verification.md#remote-locked-screen-readiness-capture-2026-10-14).
Do not request another equivalent capture or advance to a long baseline solely
from the successful background target check.

On 2026-10-14, the owner confirmed the phone is many miles from the development
Mac, unlocked and disconnected, with Wi-Fi/Bluetooth/hotspot off and cellular on.
Tailscale is occasionally used but is currently disconnected; no current remote
connection was reported. A sandboxed device listing timed out; an unsandboxed
listing succeeded. Live process probes, including an unlocked retry, returned
CoreDevice error 4016 with no assertable states. No probe succeeded, but the
generic error does not independently prove disconnection. Raw output stays in
private temporary files.

The agent accepts the explicit remote connection-path checklist as practical
setup evidence for one readiness-only capture, replacing the earlier requirement
for a specific CLI failure in this situation. This is an agent procedural revision,
not an independently reviewed amendment or a Passed live connection check.
The prior same-network positive-control suggestion does not fit the owner's
remote setup. Preserve the inconclusive probes and require actual sleep/wake
inspection afterward. No recording, sleep interval, consumer attribution or
energy benefit is established by this setup evidence; the formal-baseline gates
below remain unchanged.

On 2026-10-13, the independent Astra reviewer approved this specific 15-minute
check in principle, subject to two fixes: an executable wireless-disconnection
method and explicit conditional progression before another long baseline. The
procedure now uses development-Mac shutdown and retains the MapKit attribution
gate. On re-review the reviewer approved one 15-minute locked-screen readiness
check with no remaining preparation blocker. The reviewer found no need for
another foreground preflight, walk, Motion
query or stopwatch calibration. Review is procedural evidence only; no new phone
capture, connection isolation, sleep or background attribution has been verified.
The Mac was locked during attempted native Xcode inspection; no connection UI
setting was inspected or changed. A read-only device listing found the physical
phone paired/available, which does not establish future timed-run disconnection.

The owner subsequently clarified that shutdown is unavailable and they cannot
operate the Mac remotely. The current phone-side procedure supersedes the
Mac-off instruction. Independent Astra review approved it as readiness-only,
subject to a live unreachable/disconnected setup result before settling/capture.
Successful communication fails isolation; lock, authorization and local-tool
errors remain ambiguous. No additional capture is required to check setup.
The Mac remains on and online; no Mac settings, pairing, Developer Mode or app
data are changed. Phone radio conditions differ and must be recorded. No physical
isolation result is claimed before the owner performs setup and the probe runs.

The initial procedure's preparation validation passed on 2026-10-13: the unchanged app source built and
the full FogOfWalk XCTest scheme passed 244 tests, zero failures and zero skips,
on the iPhone 18 Pro simulator with iOS 27.0 and Xcode 27.0 (27A266a). Existing
Swift concurrency warnings remain; no source or build settings were edited.
Relative battery-document links and whitespace checks passed. Both workspace
checkouts regenerated their portfolios and passed schema, reference, lifecycle
and portfolio validation; unrelated main-checkout edits were preserved. These
checks verify preparation and repository consistency, not physical evidence.

The phone-side revision also passed the normal build and all 244 XCTest tests,
zero failures/skips, on the same simulator/Xcode setup. Record/portfolio validation
passed with unrelated workspace changes preserved. Setup isolation remains pending.
