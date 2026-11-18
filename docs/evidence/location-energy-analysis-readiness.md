# Location energy analysis readiness

> Historical measurement work: current delivery follows [Automatic stationary pause and walking resume](../proposals/2026-10-15-automatic-stationary-pause-and-resume.md). The earlier energy-comparison and reference-qualification procedures are not prerequisites for that focused prototype. Manual tracking OFF does not establish automatic pause/resume.

## Verified analysis capabilities

Xcode 27 `xctrace` successfully imported private power archives into saved
`.trace` working copies and exported their table of contents and selected data.
Original source archives were preserved. Metadata duration and timezone-bearing
Start/End values were checked for internal consistency; capture-to-trace mapping
still has to be established independently for each recording.

| Table | Technical interpretation |
| --- | --- |
| `SystemPowerLevel` | Start, duration and `percent-per-hour` fields support interval analysis. |
| `ProcessSubsystemPowerImpact` | Process and subsystem-impact fields require verified app identity and metric availability. |
| `SystemThermalState` | Thermal intervals are available for control checks. |
| `DisplayBrightnessLevel` | Display intervals help identify interruptions; darkness alone does not establish sleep. |
| `DeviceChargingState` | An empty export does not establish an uncharged state. |
| `SystemSleepState` | An empty export does not establish sleep or continuous wakefulness. |

Schema names, row availability and units must be inspected for the actual
recording. Table presence in the contents is not evidence that it contains rows.

## Reproducible private export

Use private local paths in place of these placeholders; keep raw inputs and
exports outside Git. Import once into a saved `.trace`, then query that same
working copy. Positional table indices from separate implicit archive imports
can differ.

```sh
xcrun xctrace import --input PRIVATE_INPUT.atrc --output PRIVATE_WORKING.trace
xcrun xctrace export --input PRIVATE_WORKING.trace --toc --output PRIVATE_TOC.xml
xcrun xctrace export --input PRIVATE_WORKING.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="SystemPowerLevel"]' \
  --output PRIVATE_POWER.xml
```

Select the actual run number. Resolve XML references, units, interval semantics
and sentinel/missing values before calculating a rate. No reusable rate calculator
was implemented or validated by this preparation.

For the historical stationary protocol, use diagnostic Start +600 through +7200
seconds. Map the trace to that origin, clip valid intervals, check coverage and
controls, and calculate duration-weighted rates. Report gaps without imputation;
retain adverse and inconclusive data. An unweighted row average, callback count
or whole-device rate does not establish Fog's isolated energy cost.

## Transport, matching and instrumentation findings

The diagnostic Share/AirDrop flow passed an independent byte comparison. Motion
Share export was exercised separately. Saved motion reports and power archives
can belong to older captures; match recorded boundaries rather than relying on
filenames, transfer dates or the most recent export action.

Distinct Study packaging resolved foreground profiler target/data availability:
the verified `Fog-Walk-Study` process had foreground lifecycle and available app
work. Unknown lifecycle and sentinel metrics remain unavailable. Foreground
success does not qualify background consumer attribution or sleep instrumentation.
Background target/data availability was also observed, while consumer-specific
location energy remained unresolved.

The [technical verification](location-energy-diagnostics-verification.md)
retains these conclusions and the manual OFF sleep finding. No formal energy
baseline or automatic pause/resume result is established. The
[locked-screen method](location-energy-locked-screen-readiness.md) separates
connection isolation, sleep evidence and consumer attribution; the
[attribution method](location-energy-attribution-preparation.md) retains the
conditions for interpreting a comparison. Current location behavior is documented
in [system architecture](../SYSTEM.md); source audits in the historical study do
not override later implementation changes.
