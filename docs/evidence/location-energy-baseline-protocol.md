# Location energy study: legacy baseline protocol and trial sheet

**Status:** Ready for a one-phone motion-reference pilot and diagnostics-only legacy rehearsal. No formal baseline result is recorded here.
**Study phone:** iPhone 15 Pro Max; record the exact iOS build on each trial.
**Authority:** [Location Energy and Reliable Resume](../proposals/2026-10-09-location-energy-and-reliability.md). If this sheet changes after candidate results are seen, record the revision and repeat affected pairs.

## Diagnostic contract

The separate `com.jeremybraff.fogofwalk.study` app has an explicit Start/Stop control in Settings. The normal bundle ID cannot start capture. It uses the same legacy `CLLocationManager` policy and still forwards only the last sample in each callback batch. Diagnostic logging never filters exploration. Every JSONL event has a millisecond Unix-time `recordedAt` and a `kind`; other date fields use the same encoding:

| Kind | Fields and interpretation |
|---|---|
| `capture_start`, `capture_stop`, `process_relaunch` | Capture boundary and process restart. The active capture reopens after a relaunch. |
| `tracking_start_or_rearm`, `foreground_rearm`, `authorization_change`, `permission_request`, `permission_upgrade_request`, `permission_unavailable`, `location_paused`, `location_resumed`, `location_error`, `scene_phase` | Legacy lifecycle, with authorization raw value or error domain/code where relevant. A rearm does not imply a new fix. |
| `batch` | Callback receipt time, batch ID, count, and `legacy` source. |
| `sample` | Original index, sample time, finite latitude/longitude, horizontal accuracy, speed, age at batch receipt, shadow decision, and `forwarded`. Assessment order is by sample timestamp, while `forwarded` identifies only the original last element. No sample is rejected by this logging path. |
| `downstream` | Cell ID, whether Core Data inserted a new cell, discoveries, and day rollover after actual forwarding. This cell ID is location sensitive. |

Shadow decisions use the proposal's provisional values: valid finite coordinate, 0–25 m finite horizontal accuracy, 0–15 s age, timestamp at or after source-session start, and strictly increasing accepted timestamps. Unknown speed is allowed. The contract records all batch samples, including rejected and non-forwarded samples. A capture started during an already-running location session uses the service's original session start. No diagnostic event is a claim that iOS delivered a fresh fix after movement.

Standard and significant-change monitoring currently share one `CLLocationManager` delegate callback. The legacy batch event therefore names the tracker but cannot prove which of those two mechanisms caused a particular callback. Do not infer the callback's origin from its accuracy alone.

Logs and motion references are protected local files in the study app's Application Support directory, excluded from backup. Capture is opt-in, persists across process relaunch, and stops at 16 MiB; files older than seven days are removed when the study app next initializes. Export is a deliberate Share action after capture stops. Treat exported logs as private location data; do not commit them. A failed write or full capture is visible in Settings and invalidates a trial if it leaves essential evidence missing.

The post-run Motion History button queries historical Core Motion activities and pedometer data only after capture stops. Its JSON includes activity transitions, a first reported walking time, whole-interval steps/distance, and cumulative pedometer distance every 15 seconds for the first ten minutes after reported walking. It is a reference with uncertainty, not independent GPS or a live wake-up signal. It never starts motion updates during tracking.

## Build and preflight

Build the study app with Xcode using the normal project and scheme, the phone as destination, and these build-setting overrides:

```text
PRODUCT_BUNDLE_IDENTIFIER=com.jeremybraff.fogofwalk.study
FOG_APP_DISPLAY_NAME=Fog Walk Study
```

The bundle ID gives it an independent exploration container and makes the study controls visible. Do not import the normal app's history or a fabricated route fixture into it. The same study app identity and build must be used for legacy and candidate arms later. Record the commit, configuration, app build number, phone model, iOS build, and Xcode version. Give the study app Always location permission before timed trials. Disable location permission for the normal TestFlight app while the study app tracks; verify that it is no longer tracking. Stop the study tracker before restoring normal-app permission. No attached debugger, wired Xcode connection, or wireless Xcode connection during measured locked-screen runs.

Before the first formal run, verify the diagnostic export contains a batch, every sample from it, exactly one forwarded index matching the original last sample, and downstream cells. Confirm capture remains active after a normal app relaunch. Check that MapKit's `showsUserLocation` does not create another continuous background location consumer; if changing map behavior becomes necessary, apply it to both arms and rerun affected legacy measurements. Compare a few shadow decisions to ordinary recorded cells so the provisional validator does not silently remove legitimate coverage.

## Motion-reference pilot

1. On the same phone, grant Motion & Fitness permission via a short practice capture and post-run query before any formal timed trial. If motion or pedometer history is unavailable, record that result.
2. Choose a private physically marked walking route with known approximate distance, preferably at least 200 m. Do not use another GPS app on the phone. Keep the phone still for five minutes, note the wall-clock departure time independently of location callbacks, then walk the marked route with the screen locked. Note the finish time and any stop or detour.
3. Stop capture and run **Query Motion History for Last Capture**. Compare the activity transition with the noted start time and compare pedometer distance with the marked route. Quantify onset resolution and distance error; report an interval or bound, not just a point estimate.
4. Repeat if the first query is unavailable or ambiguous. If the uncertainty could straddle the 100 m departure threshold, formal departure trials are inconclusive until the reference method improves. Never use the location stream under evaluation to infer walking onset.

The pilot's manually noted start and marked distance are approximate. Keep route maps, logs, and motion JSON private. Record only redacted uncertainty and feasibility conclusions in the repository.

## Fixed formal trial sheet

Make one local row per run, grouped by pair ID, and preserve the original rows when repeating an invalid pair. Record these fields before analyzing a candidate:

| Group | Fields |
|---|---|
| Identity | Pair/run ID; `legacy` or `candidate`; order; app commit/build; exact phone/iOS; date; route or stationary condition. |
| Preconditions | Always authorization and accuracy authorization; normal TestFlight permission disabled; Low Power Mode off; charging false; battery start/end 40–80%; starting thermal state; Xcode connection absent; ten-minute settling period; geocode/backfill idle. |
| Environment | Screen locked/foreground; Always-On Display off for controlled pairs; brightness and ordinary display settings; network mode; weather/reception; other phone use; actual start/stop timestamps. |
| Files | Private diagnostic JSONL and `.aar` names; Motion JSON when applicable; transfer and trace interval; no raw path or coordinate in committed results. |
| Location outcome | Batch/sample counts; shadow rejection reasons; first accepted post-departure sample and receipt times; motion-onset interval; pedometer distance interval through receipt; preselected interior cells captured/missed; consecutive gaps; callback gaps; manual intervention. |
| Energy outcome | Time-weighted valid whole-device system-power rate over minute 10–120 for stationary or the full predefined walk; metric resolution; app impact, CPU, location, rendering, geocoding, persistence, thermal, and display tracks. |
| Disposition | Valid, invalid pair, or inconclusive; exact reason; repeat ID; reviewer note. |

For controlled stationary and walking runs, start unplugged with 40–80% battery, Low Power Mode off, no serious starting thermal state, and Always-On Display off. Hold network and display settings constant within a pair. Discard and repeat a whole pair for charging, pre-existing serious thermal state, or unrelated phone use during capture. A thermal rise that develops during an otherwise valid run is data to investigate. Alternate source order. Retain full traces locally and inspect sleep/wake behavior. Do not estimate Fog's battery cost from whole-device rate alone.

The legacy baseline must include two-hour screen-locked stationary operation, a locked 20–30 minute fixed walk, a separate foreground map walk, and 30-minute, two-hour, and overnight idle departures. First establish motion-reference feasibility and an attributable energy baseline. If stationary location work is not material, document the measured alternative before any source prototype. The paired candidate matrix and numeric gates remain in the proposal.
