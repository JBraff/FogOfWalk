# Stationary location-energy attribution preparation

> Historical measurement work: current delivery follows [Automatic stationary pause and walking resume](../proposals/2026-10-15-automatic-stationary-pause-and-resume.md). The earlier energy-comparison and reference-qualification procedures are not prerequisites for that focused prototype. Manual tracking OFF does not establish automatic pause/resume.

## Technical findings

The historical study exposed a profiler-targeting ambiguity: normal Fog and early
Study packages shared an executable name. A Suspended normal-app track with zero
impact values did not establish Study cost. Current process-ID lookup could not
exclude historical ID reuse. Whole-device rates did not isolate location energy.

Giving Study the distinct `Fog-Walk-Study` product/executable name preserved its
bundle identity and Swift module while enabling verified foreground target/data
availability. A foreground preflight observed app work with that identity;
background target/data availability was also observed. Neither result identifies
the individual location consumer or qualifies a stationary baseline. Empty sleep
and charging tracks remain missing evidence, not zero states.

The [technical verification](location-energy-diagnostics-verification.md)
records the supported conclusions without personal trial measurements.

## Targeting preflight method

Use this method to resolve an actual target/data-availability problem, not as a
routine repeat of a passed preflight.

1. Keep normal Fog location permission Never and Study Always/Precise. Select
   only Study in Power Profiler. Profiling selection and location permission
   are separate controls. Verify independent selection before recording.
2. Start Performance Trace, then Diagnostic Capture. Keep Study in the foreground
   for roughly one minute and pan the map to provide visible app work. No walk,
   motion query or stationary energy score is needed.
3. Stop diagnostics, then the profiler. Export privately and verify matching
   boundaries, the distinct Study process, foreground lifecycle and available
   impact fields. A mismatched Suspended-only target is not a pass. Not every
   metric must be positive; sentinel fields remain unavailable.

## Historical attribution comparison

The [all-consumer control](location-energy-tracking-control-protocol.md) covers
standard updates, significant-change monitoring and MapKit user location in the
Study app. Diagnostic Stop only stops logging; it is not that control. Callback
silence and an OFF label do not prove physical resource release.

A matched legacy-ON versus manual-OFF comparison estimates total tracking-related
whole-device overhead, including downstream work. It does not isolate the legacy
manager from MapKit/system services or establish the benefit of a functioning
replacement tracker. Use the same Study identity, build, device, data, permissions
and radio/display conditions in both arms. Verify physical control behavior and
sleep measurement before formal scoring, or independently review an alternative
interpretation method.

Retain the historical diagnostic Start +600 through +7200-second interval,
settling, app isolation, battery-range, display/network/thermal and retention
controls in the [baseline protocol](location-energy-baseline-protocol.md).
Predeclare order, repetitions, variability and interpretation before candidate
results. Keep private trial notes and raw evidence outside Git; publish technical
conclusions and explicit limits rather than participant measurements.

## Interpretation limits

Missing sleep data cannot be repaired by dark-display evidence, generic connection
errors or a foreground preflight. Populated OFF sleep intervals establish data
availability under OFF only; they do not explain an empty ON lane or quantify a
saving. If location-client records cannot distinguish consumers, retain the
attribution limit rather than infer the source from generic system activity.

Radio isolation changes connectivity and potentially positioning/power. Matched
arms need the same declared settings; recordings with different radio conditions
are not a controlled comparison. The
[locked-screen procedure](location-energy-locked-screen-readiness.md) documents
setup and evidence requirements. If measurements remain within variability or
control/instrument qualification fails, report an inconclusive result and address
the specific missing evidence before another comparison.
