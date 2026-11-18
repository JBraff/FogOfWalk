# Location energy study: technical verification

> Historical measurement work: current delivery follows [Automatic stationary pause and walking resume](../proposals/2026-10-15-automatic-stationary-pause-and-resume.md). The earlier energy-comparison and reference-qualification procedures are not prerequisites for that focused prototype. Manual tracking OFF does not establish automatic pause/resume.

This record retains software verification, instrumentation findings and their
limits. Personal trial narratives and measurements are excluded from the public
record. Raw diagnostics, motion reports and power traces remain private.

## Software verification

The original diagnostics preparation passed a normal-app build and the full
235-test XCTest scheme. Subsequent capture-origin motion reporting passed 244
tests; the Study-only all-consumer OFF control passed 252. These are historical
verification results, not new test runs or physical reliability claims.

The diagnostic implementation records complete callback batches, original sample
indices, the original last sample selected for forwarding, and downstream
exploration. Shadow validation records decisions without filtering legacy
exploration. Study-only capture and source controls are isolated from normal Fog.

Motion report schema version 2 measures cumulative steps and distance from
capture start, retaining movement before walking classification. Its bounded
historical query plan includes the final endpoint and whole-capture totals.
Tests cover delayed classification, unavailable distance, invalid intervals,
unordered history, query errors and long captures with bounded queries.

## Diagnostic and motion transport

Physical checks verified capture persistence across relaunch, boundary/lifecycle
logging, sample-to-downstream consistency and post-run motion-history queries.
Fresh-sample forwarding was observed; stationary callback silence alone cannot
establish delivery success, resource release or automatic background resume.

The stopped diagnostic Share/AirDrop flow transferred a file byte-for-byte
against an independently retrieved copy. Motion Share export was also exercised;
that transport check did not include an independent byte comparison. Motion
reports must be matched to diagnostic capture boundaries: a previously saved
report can belong to an older capture.

These results establish reporting and transport behavior. They do not qualify
independent walking-onset timing, travelled-distance uncertainty or early-route
coverage. Walking classification is not the physical departure instant, and
whole-route pedometer agreement cannot calibrate an early-distance gate.

## Trace import and calculation

Xcode 27 `xctrace` imported private power archives into saved `.trace` working
copies and exported their table of contents, power, process impact, display and
thermal data. Original inputs were preserved. Analysis resolved XML references,
actual field units and interval boundaries before computing duration-weighted
whole-device rates. Export gaps were reported without imputation.

Recorded trace Start/End metadata, rather than transfer dates or filenames,
establishes whether a power archive overlaps a diagnostic capture. Older archives
and mismatched motion reports were excluded. Table presence does not establish
that the table contains records. Missing or sentinel fields remain unavailable.

## Profiler identity and data availability

Normal Fog and early Study packages shared the `Fog-Of-Walk` executable name.
A shared name did not establish which app a process-impact track represented.
A Suspended track with zero impact values and separate Fog process evidence
supported a wrong or stale target; a current process-ID lookup could not exclude
historical ID reuse. Zero values did not establish zero Study tracking cost.

Study packaging therefore uses a distinct `Fog-Walk-Study` product/executable
name while preserving its bundle ID and Swift module. A subsequent foreground
preflight identified that process and observed foreground lifecycle plus nonzero
CPU, display, GPU and instruction data. Initial Unknown lifecycle and unavailable
metrics remained explicit limits. This verified foreground target/data
availability, not a stationary energy baseline.

Background target/data availability was also observed. Per-app desired-accuracy
fields and generic system location processes did not identify which app location
consumer was active or isolate its energy cost.

## Sleep, controls and attribution limits

Some recordings had empty exported and native sleep/charging lanes. Empty lanes
do not distinguish missing instrumentation from continuous wakefulness or prove
an uncharged state. Dark display, callback silence and generic CoreDevice errors
cannot establish processor sleep or development-connection isolation.

The manual OFF check recorded OFF state with no exploration forwarding and
populated sleep intervals. This establishes that sleep instrumentation can
produce data under that condition. It does not explain the earlier ON recordings'
empty lanes or establish a matched ON/OFF saving. Notification-related display
activity is a potential confound and needs consistent control in a comparison.

Whole-device power rates and CPU sample weights cannot be attributed entirely
to Fog or converted into a location-consumer energy cost. No protocol-qualified
baseline, bounded departure-distance result, automatic stationary/resume result,
or battery-saving percentage follows from this evidence.

## Related methods

- [Diagnostic contract and baseline protocol](location-energy-baseline-protocol.md)
- [Private trace export and analysis](location-energy-analysis-readiness.md)
- [Attribution preparation](location-energy-attribution-preparation.md)
- [Locked-screen instrumentation](location-energy-locked-screen-readiness.md)
- [Departure reference qualification](location-energy-reference-qualification.md)
- [Study-only tracking control](location-energy-tracking-control-protocol.md)
- [Automatic pause/resume prototype](automatic-pause-resume-prototype.md)
