# Stationary tracking attribution comparison

**Prepared:** 2026-10-14. Study-only implementation and independent review are
complete; build and full-suite verification passed. No physical on/off comparison
or battery saving has been established.
**Authority:** [Replacement proposal](../proposals/2026-10-09-location-energy-and-reliability.md),
stage 1's all-consumer stationary diagnostic control, and the
[baseline trial sheet](location-energy-baseline-protocol.md).

## Question and decision

Measure the incremental whole-device stationary energy associated with Fog's
location consumers and downstream work. This comparison informs whether tracking
optimization has meaningful upside. It is not a comparison with a candidate
tracker and does not isolate the legacy manager from MapKit or system services.

Use the same Study identity, build, phone, data, permission and radio configuration
in both arms. Normal Fog location permission remains Never. Keep existing history;
there is no deletion, fixture import or normal-app change.

| Arm | Study Settings selection | Configured behavior |
| --- | --- | --- |
| ON | Tracking off — stationary control unchecked | Original legacy manager policy, significant-change recovery and MapKit user location. |
| OFF | Tracking off — stationary control checked | Stop standard updates and significant-change monitoring, disable background-update requests, hide MapKit user location and stop map follow. Suppress late location callbacks and exploration forwarding. |

This estimates the total difference associated with those consumers and consequent
work. It is not the energy benefit a future functioning tracker can necessarily
achieve. OFF intentionally does not explore or capture walks; it must not become
a production tracking mode.

## Implemented controls and remaining physical qualification

The internal control is gated by the exact `.study` bundle ID, defaults to ON,
and persists OFF through process relaunch. App launch, foreground activation,
authorization callbacks and MapKit recreation respect OFF. Disabling/reenabling
invalidates queued location deliveries; an old cached fix cannot enter exploration
after control resume. Capture Start and capture relaunch record
`study_tracking_state` with `on` or `off`. Mode changes are rejected while logging
is active; Stop Diagnostic Capture stops logging only.

Before measured runs, install Study build 4 over the existing Study container.
The current remote phone cannot be installed from this Mac without a supported
connection/distribution path; build preparation does not constitute installation.
Do not reinstall normal Fog, clear app data, unpair, or reset permissions.

Verify on the installed build, outside timed runs: OFF disables the map user dot,
remains selected after closing/reopening Settings and normal relaunch, and its
stopped diagnostic log records OFF with no forwarded batches/downstream events.
Verify ON restores the original map location and permitted legacy delivery.
This is a specific new-control qualification, not another generic profiler
preflight. Stop any capture before switching arms. If callbacks arrive while OFF,
`study_callback_suppressed` records must replace forwarding; callback silence is
not proof that all OS resources have been released. Inspect available per-app
location/request metadata and native Instruments evidence before claiming the
physical off-control is qualified.

## Next phone test: qualify the new OFF control

After installation and implementation review, select OFF and use the matched
conditions below, including notification silencing. Settle for ten minutes, start
profiler and diagnostics, then lock stationary for about 15 minutes. Stop
diagnostics first, then profiler, and export both. Keep the selected OFF mode
through normal relaunch before capture to verify persistence. After both recordings
stop, restore ON and verify permitted delivery resumes outside measurement.

Inspect OFF mode markers, no forwarded batches/downstream events, Study target,
display, thermal, charging and native/exported sleep records. Unlike the previous
ON readiness check, this tests the newly implemented removal of all app location
requests. Populated OFF sleep records would establish that sleep instrumentation
can work under this condition; they do not by themselves establish battery savings
or prove the reason the previous ON lane was empty.

If sleep is still empty or OFF behavior is unqualified, stop here and resolve the
specific instrumentation/control problem. Do not repeat the same capture or
request a two-hour pair. No long comparison is requested until sleep measurement
readiness and the attribution control are qualified, or an alternative interpretation
method is independently reviewed.

## Subsequent matched pair and predeclared repetitions

After implementation review, physical control qualification and sleep measurement
readiness (or independently reviewed alternative interpretation), run one matched
pair: ON first, OFF second. Each recording lasts slightly longer than two hours,
so both diagnostic Start and Stop are inside the power recording. Start profiler,
return to Study and start diagnostics, lock promptly. After at least two hours,
stop diagnostics first and profiler second. Both arms use diagnostic Start +600 s
through +7200 s as their fixed primary interval. Do not substitute a selected
quiet segment, whole-recording mean, or battery-percentage change.

Treat the first pair as attribution feasibility only. If instrument/control
qualification fails, stop for instrumentation work rather than extend repetitions.
If it is usable, the predeclared initial series is three pairs, with orders
ON/OFF, OFF/ON, ON/OFF. Complete and retain all valid pairs before a directional
conclusion; do not stop after a favorable first pair. This series does not replace
the proposal's separate control-variability and candidate-adoption requirements.
A formal materiality threshold requires a reviewed variability estimate before
candidate results. No threshold is retrofitted to this attribution series.

## Matched conditions and trial notes

Use the existing trial sheet, adding arm and control-state verification. Start
40–80% battery, Low Power Mode off, Always-On Display off, unplugged, nominal
initial thermal state, at least ten minutes of settling after setup/charging/use,
and geocoding/backfill finished (or record unresolved status and defer scoring).
Hold duration, Study build/permissions, physical resting place, radio/network mode
and display settings constant within each pair. Use cellular-only conditions
with Settings Wi-Fi/Bluetooth/hotspot off in both arms, matching the latest
readiness setup. The Mac may stay on. For the geographically remote phone,
record separation, no cable and no active Tailscale/VPN/remote-device bridge;
the old generic CoreDevice error is not a Passed live probe. Make no live phone
queries during settling or recording.

For these controlled runs, apply the same owner-selected notification-silencing
configuration in both arms before settling and restore it afterward. Verify that
it prevents notification screen lighting; the latest readiness capture contained
eight notification lighting events. Do not change settings mid-run. Hold other
phone use and other location-active apps absent; normal Fog remains Never.
Record each arm's exact start/end battery readings, approximate physical lock/
unlock times, other use, network changes and notification exceptions separately.
Restore tracking ON after stationary controls before walking. When ending the
study entirely, set Study location Never before restoring normal Fog permission.

## Analysis and disposition

Retain source archives and hashes privately, import each once into a saved trace,
and map metadata to its diagnostic boundaries and recorded arm. Confirm correct
Study target, fixed-window coverage, no mode change, expected display/charging/
thermal states, and no OFF forwarding. Resolve schema references and units;
unavailable fields are not zero. Preserve invalid/inconclusive pairs and repeat
whole pairs according to the baseline's control rules; never trim adverse data.

Sleep exports and native sleep lanes were empty in the remote readiness run.
That remains unresolved and does not prove continuous wakefulness. Before formal
scoring, establish whether sleep events are captured correctly or specify and
independently review an alternative measurement/interpretation method. An empty
sleep lane in OFF must not be accepted merely because ON was also empty. If the
instrument cannot distinguish missing data from wakefulness, report exploratory
on/off differences with that limit and do not call them a qualified baseline.

Compute clipped, duration-weighted whole-device rates over the fixed window;
report export gaps without imputation, each paired ON-minus-OFF difference,
range and all adverse/inconclusive results. Keep app-impact and CPU/graphics
activity as explanatory evidence, not a converted battery percentage.

- A consistent reduction larger than independently established variability
  supports investigating stationary tracking optimization. Separating MapKit
  from the manager would require a further reviewed control, not an inference.
- A small difference within variability gives no demonstrated tracking benefit;
  investigate CPU/rendering/geocoding or other measured costs before a rewrite.
- Unqualified control or unusable measurement requires targeted instrumentation
  work, not another equivalent trace hoping for a different result.

No live-update source, automatic-pausing change, production default change or
battery-saving promise is authorized by the comparison result alone.

## Preparation evidence

Luna completed the bounded source audit and control regression tests. Independent
Astra review approved preparation after two findings were resolved: retain callback
test services and prove fresh delivery after rejection; qualify OFF and sleep in
a bounded check before requesting long pairs. Physical control qualification and
energy evidence remain separate.

The normal app and signed physical Study build compile. Study 1.0/build 4 uses
the same `.study` bundle ID, `Fog-Walk-Study` executable and display name, with
iOS 18.6 minimum. Local signature and provisioning checks passed, including the
existing development profile authorizing that signed identity. Build overrides
only are used; normal product identity/version defaults remain unchanged.
The app is prepared locally and has not been installed on the remote phone.

Initial tests exposed actor isolation in test-helper construction and a test
assuming MapKit would accept follow mode without an authorized simulator fix;
both were corrected. The MapKit test verifies the requested follow mode and real
OFF flags. A UI-runner launch stall required recovering the local simulator;
the recovered simulator passed the normal build and all 252 XCTest tests with
zero failures and zero skips on iPhone 18 Pro/iOS 27.0, Xcode 27.0. These are
preparation issues, not physical
tracking observations. Preserve previous incomplete/failed run evidence privately.
