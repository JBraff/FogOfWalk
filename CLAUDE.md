# Fog of Walk — Claude Code Instructions

See [AGENTS.md](AGENTS.md) for full project context: architecture, data flow, key constraints, build commands, and feature-addition checklist.

## Quick reference

- **Build:** `xcodebuild -project FogOfWalk/FogOfWalk.xcodeproj -scheme FogOfWalk -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' build`
- **Test (all):** same command with `test` instead of `build`
- **Test (unit only, faster):** add `-only-testing:FogOfWalkTests` to skip UI tests
- **Always build after changes** — treat a passing build as the minimum definition of done.
- **Always run tests after changes** — treat a passing test suite (not just build) as the definition of done.
- **Always add or update tests** when adding features or fixing bugs. A change without corresponding tests is not complete.
- Do not use `fatalError` for recoverable errors (Core Data load failures, etc.).
- Do not back-port away from `@Observable` / iOS 17 APIs.
