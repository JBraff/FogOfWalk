# Location energy baseline preparation — verification

**Date:** 2026-10-10
**Scope:** Diagnostics-only legacy study build and post-run motion-history query. This is implementation and simulator evidence, not a physical-device baseline.

## Checks performed

- Xcode 27.0 generic iOS Simulator build passed for the normal app.
- Full `xcodebuild test` passed on an iOS 27.0 iPhone 18 Pro simulator: 235 test cases passed, none failed. New tests cover provisional shadow-validation boundaries, unknown speed, opt-in capture, original last-sample forwarding, and study-app gating.
- A separate Debug simulator build passed with `PRODUCT_BUNDLE_IDENTIFIER=com.jeremybraff.fogofwalk.study` and `FOG_APP_DISPLAY_NAME=Fog Walk Study`. The built `Info.plist` resolved that bundle ID and name and includes `NSMotionUsageDescription`.
- The separate app installed and launched in the simulator. Its initial location permission prompt displayed the study app name. Simulator launch does not verify the Settings controls, Core Motion history, locked-screen resume, or phone energy.
- `git diff --check` passed before this evidence record was added.

## Remaining gate evidence

No physical study build has been installed on the iPhone 15 Pro Max. The post-run historical-motion pilot, exact phone OS/build check, MapKit second-consumer audit, diagnostics export/relaunch check on the phone, protocol-qualified legacy baseline, and cause attribution remain pending. The two earlier short Power Profiler traces remain exploratory and are not counted here. No energy saving or candidate reliability is claimed.
