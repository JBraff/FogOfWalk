# Fog of Walk — Claude Code Instructions

@AGENTS.md

`AGENTS.md` above holds the full project context: architecture, data flow, the two app identities (normal and Study), key constraints, test conventions, build commands, and the feature checklist.

## Quick reference

- **Build:** `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build`. If that simulator doesn't exist, pick one from `xcrun simctl list devices available | grep iPhone`.
- **Test (all):** same command with `test` instead of `build`.
- **Test (unit only, faster):** add `-only-testing:FogOfWalkTests` to skip UI tests.
- **Simulator unavailable ("CoreSimulator is out of date")?** The owner must run `sudo xcodebuild -runFirstLaunch`. Report it, don't claim tests passed. A `generic/platform=iOS` build with `CODE_SIGNING_ALLOWED=NO` only checks that the code compiles.
- **Always build after changes.** A passing build is the minimum definition of done.
- **Always run tests after changes.** A passing test suite (not just a build) is the definition of done.
- **Always add or update tests** when adding features or fixing bugs. A change without corresponding tests is not complete.
- **Gate Study-only behavior on `LocationService.isStudyApp`.** The normal app's default tracking must not change.
- **Never commit Study diagnostic logs, motion files, or raw location traces.**
- Do not use `fatalError` for recoverable errors (Core Data load failures, etc.).
- Do not back-port away from `@Observable` / iOS 17 APIs.
