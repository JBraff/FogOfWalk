# Fog of Walk

An iOS app that overlays a "fog of war" on Apple Maps and lifts it as you physically walk through the world. Explore your neighborhood, uncover your city.

## What is this?

Fog of Walk covers your map in a grey haze and clears it as you walk. Go somewhere new and the fog lifts. Over time you build up a picture of everywhere you've actually been — the well-worn routes, the gaps you never noticed, the corners of your city still waiting to be explored.

## Documentation

For architecture, proposals, and preserved implementation history, see the
[documentation map](docs/README.md).

## Requirements

- Xcode 26.2 or later (last verified with Xcode 27); the project uses Swift 6.2-era build settings
  such as default `MainActor` isolation
- An iPhone running iOS 18.6 or later (the app's deployment target)
- An Apple Developer account (free tier works for personal device installation)

## Getting started

The Xcode project is checked in; cloning and building is enough. See [SETUP.md](SETUP.md) for how
the project is wired, building the separate Study app, and regenerating the landmark database.
Contributors and coding agents should start with [AGENTS.md](AGENTS.md).

**Quick build (after setup):**

```bash
xcodebuild \
  -project FogOfWalk/FogOfWalk.xcodeproj \
  -scheme FogOfWalk \
  -destination 'platform=iOS Simulator,id=<your-simulator-id>' \
  build
```

To find an available simulator ID:

```bash
xcrun simctl list devices available | grep iPhone
```

**Simulating movement:** In the running simulator, use **Features → Location → City Bicycle Ride** to watch the fog lift in real time.

## Running tests

```bash
xcodebuild \
  -project FogOfWalk/FogOfWalk.xcodeproj \
  -scheme FogOfWalk \
  -destination 'platform=iOS Simulator,id=<your-simulator-id>' \
  test
```

## License

MIT — see [LICENSE](LICENSE).
