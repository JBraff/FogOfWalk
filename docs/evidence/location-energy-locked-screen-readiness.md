# Locked-screen measurement readiness

> Historical measurement work: current delivery follows [Automatic stationary pause and walking resume](../proposals/2026-10-15-automatic-stationary-pause-and-resume.md). The earlier energy-comparison and reference-qualification procedures are not prerequisites for that focused prototype. Manual tracking OFF does not establish automatic pause/resume.

## Purpose and technical findings

This historical procedure separates background profiler target/data availability,
development-connection isolation, sleep instrumentation and consumer attribution.
A foreground profiler preflight passed, and background Study data was observed.
Those findings do not by themselves qualify sleep evidence or location-consumer
energy. Empty native/exported sleep lanes remained ambiguous. Manual OFF later
produced sleep intervals, establishing data availability under that condition
without explaining the earlier ON results.

The original source audit identified legacy standard/significant-change services
and MapKit user location as potential consumers. A shared manager delegate cannot
identify which legacy service caused a callback. Generic `locationd` activity,
per-app accuracy settings and CPU/GPU impact do not isolate MapKit from the app
manager. Consult [current architecture](../SYSTEM.md) for later changes to map
location and background rendering; the historical audit is not current runtime
truth.

Stop Diagnostic Capture stops logging only. Profiling selection, app permission,
source selection and resource release are distinct controls. Preserve pairing
and app containers; no unpairing or reset is required for this procedure.

## Private setup record

Record build/device/OS metadata, battery endpoints, display/network/thermal
conditions, settling, charging, connection paths and interruptions privately.
Keep participant observations and personal measurements out of public evidence.
The historical baseline uses 40–80% battery, Low Power Mode and Always-On Display
off, no serious initial thermal state, at least ten minutes of settling, and
geocoding/backfill idle or explicitly unresolved.

1. Verify normal Fog location Never, Study Always/Precise, Power Profiler selected
   and only Study monitored. Preserve any existing saved recording.
2. Establish development-connection isolation before settling. One option is
   shutting down the development Mac; another is phone-side radio isolation:
   USB/MagSafe unplugged, Wi-Fi/Bluetooth off in Settings, hotspot off and no active
   remote-device bridge. Leave cellular, permissions and Developer Mode unchanged.
   Record changed radio conditions and hold them through both recordings.
3. If checking CoreDevice, use a bounded live command before settling; cached
   paired-device listings do not establish connection state. Successful live
   communication fails isolation. Lock, authorization, syntax and generic tool
   errors do not prove disconnection. Explicitly confirmed connection-path
   isolation may support a bounded readiness check, but is not a passed live
   probe or proof of sleep. Keep ambiguous setup unresolved.
4. End all device queries/live sessions before settling and capture. Verify
   diagnostics are inactive and no unresolved write/full error exists.

Apple documents [Power Profiler connection requirements](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler),
[Settings versus Control Center radio controls](https://support.apple.com/en-us/102412)
and [device pairing](https://developer.apple.com/documentation/xcode/pairing-your-devices-with-your-mac).
A paired device is not necessarily connected, and a dark display is not evidence
of processor sleep. Radio isolation can affect positioning and power; it is not
interchangeable with a different network condition in a matched energy comparison.

## Bounded readiness method

This is an instrumentation check of about 15 minutes, not an energy analysis
window, walking-reference qualification or automatic-resume test.

1. Start Performance Trace, then Diagnostic Capture, and confirm both are active.
2. Lock the phone and leave it stationary and unused for the bounded interval.
   Keep independently noted lock/unlock times and interruptions private.
3. Stop diagnostics, then the profiler before reconnecting or restoring radios.
4. Export the stopped log and matching saved power archive privately. Preserve
   original files. Respect the Study app's seven-day diagnostic cleanup limit.

## Inspection and decision

Import once into a private saved `.trace`. Inspect native tracks and export that
same working copy. Resolve actual schemas, XML references, units, interval
coverage and unavailable fields before interpreting data.

| Question | Required evidence and limit |
| --- | --- |
| Do log and trace match? | Map trace metadata to diagnostic boundaries and independently noted lock/unlock; report gaps. App scene phases are not exact physical lock timestamps. |
| Is Study monitored? | Verify `Fog-Walk-Study` identity and lifecycle. Suspended/Unknown lifecycle and unavailable metrics cannot establish zero tracking cost. |
| Is sleep measurable? | Check populated native and exported intervals. Empty lanes do not distinguish missing instrumentation from wakefulness. |
| Were controls preserved? | Check charging, display, thermal and private setup notes. Participant confirmation does not replace missing telemetry. |
| Are location consumers identifiable? | Require consumer-specific client/resource evidence. Generic system processes and impact fields cannot isolate a consumer. |

Proceed to a formal energy comparison only with usable instrumentation and a
qualified attribution control, or an independently reviewed alternative method.
Use the unchanged primary interval and controls in the
[baseline protocol](location-energy-baseline-protocol.md). Retain adverse and
inconclusive observations; missing evidence calls for specific instrumentation
work rather than repeating an equivalent capture for a favorable result.

The original preparation passed the normal build and 244-test full XCTest scheme
on the iPhone 18 Pro simulator with iOS 27.0 and Xcode 27.0. Those historical
software checks did not qualify physical sleep, background consumer attribution,
a departure-distance gate or battery benefit. The
[technical verification](location-energy-diagnostics-verification.md) records
the supported physical instrumentation conclusions.
