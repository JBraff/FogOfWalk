# Locked-screen measurement readiness

**Prepared:** 2026-10-13.
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
3. Save Mac work and stop any Xcode/Instruments live recording or debug session.
   Unplug USB and remove MagSafe charging, then **fully shut down the development
   Mac** and leave it off until both recordings have stopped. Sleep or screen
   lock is not shutdown. This prevents that Mac's wireless Xcode reconnection
   without changing phone network settings or deleting its pairing. Verify no
   other development host is connected. Record the Mac-off control in the trial
   note. An installed-Xcode disconnect control may replace shutdown only after
   its operation is verified; no such UI control was verified in this preparation.
4. Confirm the Study diagnostics are inactive and there is no unresolved log
   write/full error. Leave Study ready to start capture. Keep permissions and
   installed build unchanged during the run.

## Next phone check: stationary, locked for about 15 minutes

The duration bounds the setup effort; it is not an energy analysis window or a
guarantee that the phone will sleep. No walk, stopwatch calibration, route fixture
or Motion query is needed. Use another clock to note approximate lock and unlock
times; the phone itself stays untouched while locked.

1. Start Performance Trace in Control Center and confirm recording is active.
2. Return to Study > Settings and start Diagnostic Capture; confirm it is running.
3. Lock the phone promptly. Leave it stationary and unused for about 15 minutes.
4. Unlock, note the ending battery percentage, stop Diagnostic Capture, then stop
   Performance Trace. Stop both before starting the Mac or reconnecting USB.
5. AirDrop the new stopped diagnostic log and the new saved power archive to the
   Mac. Preserve original files locally and identify them as one matched check.
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

Preparation validation passed on 2026-10-13: the unchanged app source built and
the full FogOfWalk XCTest scheme passed 244 tests, zero failures and zero skips,
on the iPhone 18 Pro simulator with iOS 27.0 and Xcode 27.0 (27A266a). Existing
Swift concurrency warnings remain; no source or build settings were edited.
Relative battery-document links and whitespace checks passed. Both workspace
checkouts regenerated their portfolios and passed schema, reference, lifecycle
and portfolio validation; unrelated main-checkout edits were preserved. These
checks verify preparation and repository consistency, not physical evidence.
