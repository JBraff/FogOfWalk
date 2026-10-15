# Study automatic stationary pause and walking resume

Date: 2026-10-15. Software prototype and verification record. Physical feasibility
is **Pending** until the focused phone trial below supplies usable evidence.
This implements the [owner-directed proposal](../proposals/2026-10-15-automatic-stationary-pause-and-resume.md).

## Supported approach

Use `CLLocationUpdate.liveUpdates(.fitness)`, keeping its asynchronous sequence
open while Core Location reports `stationary`. Apple documents automatic update
resumption and background execution when movement makes locations available.
The app retains `CLBackgroundActivitySession` and `CLServiceSession(authorization:
.always)`; the latter supports using Always authorization outside in-use periods.
Neither a timer nor a significant-change event is the walking restart mechanism.

Verified against Xcode 27.0's installed iPhoneOS SDK: live updates/background
activity sessions are available from iOS 17; `stationary` and service sessions
from iOS 18. All fit the app's iOS 18.6 deployment floor. Use `stationary`, rather
than its deprecated `isStationary` spelling.

Sources: Apple's [streamlined location updates session](https://developer.apple.com/videos/play/wwdc2023/10180/),
[stationary property](https://developer.apple.com/documentation/corelocation/cllocationupdate/stationary),
[service session](https://developer.apple.com/documentation/corelocation/clservicesession),
and installed SDK declarations in `CoreLocation.swiftinterface`,
`CLLocationUpdater.h`, `CLBackgroundActivitySession.h`, and `CLServiceSession.h`.
These contracts justify a prototype; they do not establish reliable early-route
capture on the study phone.

## Implementation and focused review

- Only the exact Study app identity can select the persisted `liveUpdates` source.
  Normal Fog, missing selections, and unknown values use legacy tracking.
- `LocationService` owns the source. Repeated startup/foreground/authorization
  callbacks do not replace a running live sequence, including while stationary.
  The Study app wires `ExplorationRecorder` and rejoins a persisted live session
  during app initialization before a map or SwiftUI task is needed. The normal
  app retains its existing map callback wiring; both use the same recording logic.
- Switching sources, manual OFF, or losing Always authorization cancels the live
  task, invalidates its two sessions, and invalidates its generation. Late live
  events and queued legacy update/pause/resume callbacks cannot cross generations.
  Legacy fallback is selectable immediately outside capture. An ended/erroring
  sequence stops and records failure; foreground recovery can create a new source.
  It does not silently substitute legacy tracking during a feasibility capture.
- Live selection stops both legacy manager location services and disables MapKit
  user location. Map recreation respects this selection. Study's dot and native
  follow are unavailable in this arm; manual map navigation remains available.
  Selecting Legacy restores its map consumer. The manager remains the permission
  delegate, without requesting locations in the live arm.
- Framework state and location delivery are separate: nil locations do not add
  exploration, and a final stationary location does not clear stationary state.
  Live forwarding rejects invalid, pre-session, older-than-15-second, future and
  duplicate/out-of-order samples. The legacy sample policy is unchanged. Existing
  shadow diagnostic accuracy decisions remain advisory. Only actual samples add
  50 m cells, with the same day rollover and landmark discovery behavior.
- Capture records source selection, framework stationary transitions and update
  diagnostics, sample/fix receipt times, and downstream cells. Start also records
  the currently known stationary state. Source/OFF controls lock during capture;
  Stop Capture leaves tracking running. Existing local retention and size limits
  apply. Logs and raw locations stay outside Git.

The focused source/lifecycle review covered startup, replacement, cancellation,
permission downgrade/regrant, error recovery, map recreation, data ownership and
fresh exploration. No unresolved software blocker was found. This was a local
implementation review, not an independent review or physical validation.
Force-quit, termination recovery, other phones and quantified energy benefit
are not established by this work.

## Software evidence

The normal app build passed. The full FogOfWalk scheme passed **268 XCTest tests,
zero failures and zero skips**, on iPhone 18 Pro / iOS 27.0, Xcode 27.0. Sixteen new
`StationaryLocationSourceTests` cover defaults/identity isolation, persisted
startup, map exclusion, idempotent rearm, stationary handling, fresh exploration
without a map, cancelled/stale callbacks, fallback, permission recovery, manual
OFF, source errors, freshness and diagnostic capture. Simulator events are
injected; this does not prove physical background wake-up.

The signed physical Study package is version 1.0/build 5, bundle ID
`com.jeremybraff.fogofwalk.study`, executable `Fog-Walk-Study`, display name
`Fog Walk Study`, minimum iOS 18.6. Strict signature verification and existing
wildcard provisioning/team/known-phone authorization checks passed. The normal
app's packaging defaults were not changed. Existing actor-isolation warnings in
unrelated files remain. Private build logs and `.xcresult` evidence are retained
outside Git.

## Installation and one focused trial

Install over the existing Study identity; do not uninstall or reset its data.
Before updating, verify capture is inactive and privately copy Application Support
and preferences. Verify preserved files/preferences before first launch, installed
build metadata and debugger-free launch. The first probe found the phone unavailable. After the owner readied the phone,
CoreDevice installed build 5 over build 4 successfully. Before first launch all
17 original Application Support files were byte-identical and every original
preference was preserved; capture was inactive, tracking OFF was false and the
source default remained Legacy. Installed metadata confirms Study 1.0/build 5;
normal Fog remains 1.0/build 11. The remote debugger-free launch attempt was
refused because the phone had locked. Manual opening/setup and the physical trial
remain pending; no automatic pause/resume or battery result is claimed.

1. In Study Settings, select **Automatic pause/resume** and leave **Tracking off**
   unchecked. Verify Always permission and receipt of a fresh setup location.
   Keep normal Fog's competing tracker disabled. Finish setup before capture.
2. Predeclare a **20-minute stationary bound**, followed by a **5–10 minute walk**.
   Pick a nearby early checkpoint on a simple route. Note approximate departure
   and checkpoint times using another clock or post-run recollection, with its
   uncertainty. No route calibration or energy baseline is required.
3. Start Diagnostic Capture, lock the phone and leave it stationary for 20 minutes.
   Use no debugger, charging or active development connection. End all Mac phone
   queries before the trial. Record material interruptions and actual setup.
4. At the bound, walk with the screen locked, without opening or restarting Study.
   Do not extend the idle period to chase a stationary result. If no actual
   stationary state is found afterward, classify this trial as inconclusive and
   investigate the specific reason.
5. After walking, stop and export diagnostics. Check a framework stationary event
   or known-state snapshot before departure, then nonstationary events, first
   fresh fix receipt, continued samples and actual exploration through the early
   checkpoint. Distinguish events delivered before the post-walk unlock/foreground
   from those caused by reopening. Callback silence and the returning map dot
   cannot establish resume. Report any ambiguous early gap as inconclusive.
6. Return a proceed/reject/inconclusive answer before requesting another trial.
   Restore Legacy after the experiment if automatic tracking fails or is abandoned.
   Expand testing only for a specific unresolved question.

This is a functional feasibility trial. A successful run is one-phone evidence;
no battery-saving percentage or normal-app rollout follows automatically.
