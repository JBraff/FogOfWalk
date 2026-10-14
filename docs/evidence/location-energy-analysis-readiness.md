# Location energy analysis readiness

**Date:** 2026-10-12; updated 2026-10-13.
**Scope:** Offline preparation, export verification, and subsequent trace-analysis
readiness checks. The build-3 foreground profiler-targeting check Passed; formal
locked-screen energy qualification and background attribution remain pending.
The earlier preparation and subsequent results are distinguished below.

## Checks completed without another phone test

A read-only Luna source audit, checked by the primary agent, confirms that the
legacy manager retains nearest-ten-metre accuracy, a 15 m filter, disabled
automatic pausing, background updates, and significant-change recovery. Callback
forwarding still uses only the original last sample. The capture-origin motion
implementation and its untracked regression tests were preserved.

`MapContainerView.makeUIView` still enables `showsUserLocation` and follow mode.
This identifies a possible additional location consumer; source inspection
cannot establish its background resource use or power cost. Physical inspection
remains required. Apply any justified map change equally to both study arms and
repeat affected baseline measurements under the proposal.

The installed Xcode 27 `xctrace` CLI successfully imported the existing private
exploratory stationary `.atrc` into a private `.trace` working copy and exported
its table of contents and selected tables. The source trace was unchanged.
Its 1688.056-second duration remains an exploratory, roughly 28-minute recording,
not a protocol-qualified baseline or a recording of the current build-2 study app.

The trace has timezone-bearing Start/End metadata. Their difference agrees with
the declared duration within one millisecond. This establishes internal metadata
consistency only; mapping a future study capture into the trace still needs
verification against that run's actual metadata.

| Exported table | Rows in this exploratory trace | Preparation finding |
| --- | ---: | --- |
| `SystemPowerLevel` | 1688 | Start, duration, and `percent-per-hour` fields are exportable. |
| `ProcessSubsystemPowerImpact` | 3668 | Process and subsystem-impact fields are exportable. |
| `SystemThermalState` | 1 | A thermal interval is exportable. |
| `DisplayBrightnessLevel` | 17 | Display intervals are exportable. |
| `DeviceChargingState` | 0 | No exported rows; do not infer complete uncharged-state evidence. |
| `SystemSleepState` | 0 | No exported rows; do not infer either sleep or continuous wakefulness. |

Table presence in the contents is not evidence that a table contains records.
Inspect full Instruments tracks and available metadata when a state export is
empty; unresolved primary-interval controls remain unqualified. No new power
rate, attribution, or MapKit background-consumer conclusion was computed here.

## Reproducible private export preparation

Use private local paths in place of these placeholders; keep raw inputs and
exports outside Git. Import once into a saved `.trace`, then query that same
working copy. Do not correlate positional table indices from separate implicit
imports of an `.atrc`; their table ordering can differ.

```sh
xcrun xctrace import --input PRIVATE_INPUT.atrc --output PRIVATE_WORKING.trace
xcrun xctrace export --input PRIVATE_WORKING.trace --toc --output PRIVATE_TOC.xml
xcrun xctrace export --input PRIVATE_WORKING.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="SystemPowerLevel"]' \
  --output PRIVATE_POWER.xml
```

Select the actual run number and inspect that export's schema rather than assume
all OS/tool versions or recordings have identical tables. Resolve XML references,
field units, interval semantics, and missing values before calculating a rate.
No reusable rate calculator has been implemented or validated by this check.

For a future stationary run, use the
[fixed baseline origin and interval](location-energy-baseline-protocol.md):
diagnostic Start +600 through +7200 seconds. Establish the trace time-base mapping,
clip valid intervals to that window, verify full coverage and controls, and use
duration-weighted rates. Do not substitute an unweighted row average, count
callbacks as energy, or treat a whole-device rate as Fog's isolated cost. Retain
all tracks and records for attribution and adverse-result review.

## Stopped diagnostic Share/AirDrop check completed

The owner exercised Fog Walk Study > Settings > Export Location Diagnostic Log >
AirDrop to the owner's Mac. The received file is byte-identical to the private
copy retrieved from the phone: 821 bytes, 11 records, one Start/Stop pair, and
369.507-second duration. This verifies complete transfer of the stopped
stationary log through the physical Share/AirDrop flow. The raw file and name
remain private. No new capture or walking was needed.

Motion export is a separate preflight check and must match its report's own
capture interval. Do not assume an older motion report belongs to the latest
stationary log. No new Motion query is needed for the diagnostic-log Share check.
Motion Share export remains a separate, unverified flow; it is not required for
this diagnostic-log transport check. Log transport does not qualify stopwatch
alignment, motion-reference uncertainty, or any energy measurement.

The owner subsequently completed a 8407.367-second stationary capture and
AirDropped its matched schema-2 Motion Reference, exercising Motion Share/AirDrop
for that report. Its receipt checks and remaining energy-evidence requirements
are recorded in the
[diagnostics verification record](location-energy-diagnostics-verification.md).
The two-hour baseline is not qualified merely by diagnostic duration or zero
pedometer totals; the corresponding power trace and trial controls remain pending.

The two subsequently AirDropped power archives were confirmed from recorded
metadata to be the older 2026-10-10 exploratory traces, with durations 1688.056
and 894.047 seconds and zero overlap with the new capture. They cannot supply its
power data. Check whether a current Performance Trace is still active or another
saved trace exists before deciding a new energy recording is needed.

When an unused-phone window becomes available, confirm the existing battery,
permission/isolation, settling, display/network, thermal, backfill, and Xcode-
disconnection controls before recording. Preserve the legacy tracker until an
attributable baseline justifies a candidate. Walking reference and formal
departure scoring remain separate and unqualified.

## Subsequent matched recording

The 2026-10-13 stationary submission now includes a new power archive overlapping
its 13057.462-second diagnostic capture and covering the fixed minute-10–120
window. Private import, schema/reference resolution, table export and clipped
duration-weighted inspection succeeded. The provisional whole-device mean is
1.542%/hour over 6599.999725 valid exported seconds; sub-microsecond export gaps
total 0.275 ms and are not imputed. Primary display brightness is zero and thermal
state nominal. The new submission's Motion file belongs to the previous capture
and is excluded. Full receipt findings and remaining control, app-identity,
sleep/charging, export-gap and attribution limits are in the
[verification record](location-energy-diagnostics-verification.md). This is not
yet a qualified baseline or an adoption decision.

## Build-3 foreground targeting readiness

The completed short diagnostic and power exports establish a matching
47.290-second capture within a 52.960-second power recording, monitored exclusively
as the distinct `Fog-Walk-Study` executable. Foreground lifecycle and positive
CPU/display/GPU impact and CPU instructions verify target/data availability.
The initial lifecycle period is Unknown and sentinel metric fields remain
unavailable. This passes foreground instrumentation only. Full aggregates and
limits are in the [verification record](location-energy-diagnostics-verification.md).

No repeat of the short check is needed. The next preparation is explicit Xcode
disconnection, sleep/wake evidence and the background MapKit consumer audit before
another long window. Foreground success does not repair the old long recording's
normal-app attribution or empty sleep data. Legacy tracking is preserved.

## Next locked-screen preparation

The [reviewed readiness procedure](location-energy-locked-screen-readiness.md)
provides a specific 15-minute stationary locked-screen check on installed build 3,
with the development Mac fully shut down during capture to prevent wireless
Xcode reconnection. It retains phone network settings and app pairing/container.
The source audit confirms MapKit requests user location, but actual background
consumer activity and energy remain unverified. Use the new check for sleep/wake
instrumentation readiness; if it lacks location-client evidence, specify the
remaining attribution method rather than repeating the same check. No new
physical result or long-window readiness is claimed by this preparation.
