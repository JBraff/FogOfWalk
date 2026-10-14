# Stationary location-energy attribution preparation

**Status:** Attribution comparison draft for review; Study build 3's foreground
target/data-availability preflight Passed. Locked-screen measurement readiness,
background consumer attribution and formal energy qualification remain pending.
**Authority:** [Replacement proposal](../proposals/2026-10-09-location-energy-and-reliability.md),
stage 1, and the [fixed baseline protocol](location-energy-baseline-protocol.md).
Preserve the legacy tracker and all existing numeric gates.

## Current evidence and disposition

The 2026-10-13 recording has a matching diagnostic log and power trace. Its fixed
minute-10–120 window gives a provisional whole-device rate of 1.542%/hour over
6599.999725 exported valid seconds. Sub-microsecond export gaps total 0.275 ms;
they were not imputed. The primary display is dark and thermal state nominal.
The owner confirms unplugged/Xcode-disconnected operation, normal Fog location
permission Never, study Always/Precise permission, Low Power Mode and Always-On
Display off, settling, stable network, and no movement or screen unlock.

Exact starting and ending battery percentages were not recorded. The owner has
subsequently confirmed that both were between 40% and 80%; retain that as
owner-confirmed battery-range evidence, with exact values unknown. Missing exact
values alone do not require repeating the run. Formal comparison qualification
still awaits the attribution and trace-evidence checks below. Do not reconstruct
exact battery levels by integrating the power rate: that supplies no initial
state of charge.

The supplied Motion report belongs to the preceding capture and is excluded.
Charging and sleep exports are empty. Owner confirmation establishes the reported
uncharged control; it does not supply missing trace sleep evidence. Additional
state/lifecycle exports do not recover battery levels, sleep state or study bundle
identity. Full findings are in the [verification record](location-energy-diagnostics-verification.md).

The exported process has the shared `Fog-Of-Walk` executable name. CPU, display,
GPU and networking impact values are all zero in the primary interval, and the
exported CPU-instruction values are zero throughout the recording. This does not
prove zero CPU or location energy: process identity, data availability and metric
resolution remain unresolved, and location work can have system costs. The trace
does not establish that stationary location tracking is the largest actionable
cost or justify a replacement location source.

## Resolve instrumentation before another long window

Native inspection after Mac unlock confirms zero app-impact values and a full-run
Suspended lifecycle. The native sleep lane is also empty. The app-impact process
identifier matches the normal TestFlight app in a current read-only phone lookup;
another Fog process appears in native graphics/Symbols data. That strongly
supports a wrong or stale target, while current identifier matching cannot
independently exclude historical identifier reuse. The normal app's zero impact
does not establish Study tracking cost. Resolve sleep/wake evidence and the tiny
exported interval gaps without silently waiving them or inferring continuous
wakefulness from an empty table.

For a future trace, select only Fog Walk Study under profiler Monitored apps and
record that selection privately. Profiling selection and location permission are
separate controls; main-app location must still be Never. Establish the study
target's identity by available metadata or verified selection before using its
process impact. Complete the setup and capture-state checks before the primary
interval, retaining their evidence outside that interval.

## Brief Study-only targeting check

This is an instrumentation preflight, not a stationary energy comparison or
reliability trial. It is needed because of the newly observed target mismatch;
prior installation, motion and timing rehearsals need not be repeated.

The owner subsequently found the old Fog and Study profiler switches changed
together, so the prior Study-only instruction could not be followed. Both copies
shared the same executable/bundle name despite different bundle IDs and display
names. Study 1.0/build 3 is now installed in place with `Fog-Walk-Study` as its
distinct product/executable name, preserving its bundle ID and data. This is a
candidate workaround for the coupling, not proof of the profiler's internal
selection mechanism. After being asked to check Study on with normal Fog off,
the owner reports that it now works better. Record this as owner-reported UI
selection success only. The subsequent short capture now verifies the distinct
Study foreground target, as recorded below. Locked-screen measurement readiness
and background attribution remain separate pending checks.

1. Keep normal-app location Never and study Always/Precise. In Developer >
   Performance Trace, use Power Profiler and select only Fog Walk Study under
   Monitored apps; turn off the normal Fog profiling switch. Preserve the study
   container and installed build. Reopen the settings page after the update and
   first verify the switches operate independently. If they still move together,
   stop this preflight and report that result instead of recording blindly.
2. Open Study so it is running. Start Performance Trace in Control Center, return
   to Study, and start Diagnostic Capture. Keep Study in the foreground for
   roughly one minute, with a brief map pan to provide visible app work. This
   setup check is not scored for energy; do not substitute it for the fixed
   two-hour baseline. No walk or Motion query is needed.
3. Stop Diagnostic Capture, then stop Performance Trace. Export the new diagnostic
   log and power trace privately. Check matching boundaries, monitored Study
   identity and a foreground lifecycle corresponding to Study interaction.
   Inspect CPU/graphics data availability without assuming every impact metric
   must be positive. A Suspended-only mismatched target is not a pass.

The owner has completed this preflight. The 52.960-second trace covers its
47.290-second diagnostic and exclusively names the distinct `Fog-Walk-Study`
process. Foreground lifecycle is recorded for 35.991 seconds; the initial
16.969 seconds are Unknown. CPU/display/GPU impact and CPU instructions contain
positive values; sentinel values are retained as unavailable. Target/data
availability Passed for this foreground check; it is not a background-energy
baseline. Details are in the verification record. Do not request another generic
short targeting run or a Motion query. Finish Xcode-disconnection/sleep evidence
preparation and the background MapKit consumer audit before a new long window;
the old empty sleep track and old normal-app targeting remain unresolved.

## Proposed attribution comparison for review

Stage 1 permits a stationary-only diagnostic control with location delivery
suspended if ordinary traces remain ambiguous. Compare unchanged legacy tracking
with such a control on the same study identity, build and phone under the existing
stationary protocol. The control estimates total tracking-dependent overhead,
including any MapKit location consumer; it does not isolate the legacy manager or
demonstrate a candidate's benefit.

The control mechanism has not been selected or physically verified. Confirm that
it covers standard updates, significant-change monitoring and MapKit's location
consumer. Do not equate diagnostic Stop, callback silence, or a source-mode label
with all consumers being stopped. Verify permission/session behavior and any
control-specific overhead before a measured comparison. Any required study-only
implementation must have regression tests and the full build/XCTest checks; keep
normal tracking unchanged and use equivalent builds for both comparison arms.

Keep the existing time origin, +600 through +7200-second analysis interval,
settling, app isolation, display/network/thermal controls and retention rules.
Record actual starting and ending battery percentages and verify the protocol's
range. Predeclare order, repetitions and comparison interpretation during review;
do not choose them from a favorable observed result or alter the existing gates.
Retain adverse and inconclusive results. No method or numeric gate is changed by
this draft.

Review these preparations before requesting another phone window. If the
instrumentation cannot support attribution or the comparison remains within
measurement uncertainty, record that limit instead of assuming tracking is the
cause. No candidate implementation, walk or battery-benefit claim follows from
the current exploratory recording.

## Reviewed locked-screen readiness procedure

The [next-test procedure](location-energy-locked-screen-readiness.md) now records
the source consumer audit and a concrete 15-minute stationary locked-screen check
on installed build 3. The independent Astra review required an executable wireless
disconnection method and conditional progression to a long baseline; both are
incorporated. The development Mac stays fully shut down until diagnostic and
power capture stop, preserving pairing and the phone's network configuration.
Native connection controls could not be inspected while the Mac was locked.

This check targets the missing sleep/wake/background instrumentation evidence;
the foreground targeting check remains Passed. It does not isolate MapKit cost
or select/implement the all-consumer control above. If consumer-specific evidence
is unavailable, that physical audit stays open and needs a reviewed instrumentation
or attribution-control method. Keep all existing measurement gates and do not
request another equivalent short trace to resolve absent consumer information.

The owner subsequently clarified that the development Mac must remain on and
cannot be operated remotely. This supersedes the shutdown instruction above.
Independent Astra review approved a readiness-only phone-side alternative,
conditional on setup verification: Settings Wi-Fi/Bluetooth off, hotspot off,
USB unplugged, cellular/permissions unchanged, and a bounded live CoreDevice
unreachable result before settling/capture. Lock, authorization and tool failures
are not disconnection evidence. Restore radios only after both recordings stop.
The revised procedure records changed radio conditions and prohibits energy
comparison with prior Wi-Fi-on recordings. No physical isolation or sleep result
is claimed; subsequent matched energy arms need identical declared radio settings.
