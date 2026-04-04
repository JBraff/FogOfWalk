# Fog of Walk

An iOS app that overlays a "fog of war" on Apple Maps and lifts it as you physically walk through the world. Explore your neighborhood, uncover your city.

## What is this?

Fog of Walk covers your map in a grey haze and clears it as you walk. Go somewhere new and the fog lifts. Over time you build up a picture of everywhere you've actually been — the well-worn routes, the gaps you never noticed, the corners of your city still waiting to be explored.

## Requirements

- Xcode 15+
- iOS 17+ (required for `@Observable`)
- An Apple Developer account (free tier works for personal device installation)

## Getting started

See [SETUP.md](SETUP.md) for step-by-step instructions to create the Xcode project and wire everything together.

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
