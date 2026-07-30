# Fog of Walk — Project Setup

The Xcode project, its capabilities, and the Core Data model are all **checked into this repo**.
There is nothing to create — cloning and building is enough. This document explains how the
checked-in project is wired, how to build and run it, and how to regenerate the bundled
landmark database if you need to.

---

## 1. How the project is wired

- **`FogOfWalk.xcodeproj/project.pbxproj`** uses `PBXFileSystemSynchronizedRootGroup` for the
  `FogOfWalk`, `FogOfWalkTests`, and `FogOfWalkUITests` groups. New files added under those
  directories are picked up automatically — there is no per-file membership list to maintain.
  `Info.plist` is the one explicit exception: it's referenced directly via `INFOPLIST_FILE`.
- **Product naming:** `PRODUCT_NAME = "Fog-Of-Walk"` while `PRODUCT_MODULE_NAME` is pinned to
  `FogOfWalk`, so the built bundle is `Fog-Of-Walk.app` but `@testable import FogOfWalk` still
  works. Test targets point `TEST_HOST` at `Fog-Of-Walk.app`.
- **No shared scheme.** `FogOfWalk.xcodeproj/xcshareddata/` doesn't exist, only `xcuserdata/` —
  builds rely on Xcode's autocreated user scheme. This is fine locally but means there is no CI
  in this repo and a fresh clone's first build depends on Xcode generating that scheme.
- **Core Data model:** one `FogOfWalk.xcdatamodeld` containing two model *versions* —
  `FogOfWalk.xcdatamodel` and `FogOfWalk 2.xcdatamodel` — with `.xccurrentversion` selecting v2.
  Not two separate `.xcdatamodeld` directories. `VisitedCell` is in both versions; `Landmark`
  and the `byCellSizeAndCoords` fetch index were added in v2.
- **Deployment target:** app target `IPHONEOS_DEPLOYMENT_TARGET = 18.6`; test targets `26.2`;
  project-level default `26.2`.

---

## 2. Build & run

```bash
# Build (replace simulator ID if needed)
xcodebuild \
  -project FogOfWalk/FogOfWalk.xcodeproj \
  -scheme FogOfWalk \
  -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' \
  build

# Run tests
xcodebuild \
  -project FogOfWalk/FogOfWalk.xcodeproj \
  -scheme FogOfWalk \
  -destination 'platform=iOS Simulator,id=F1E38D9B-23CC-41EB-A448-9CF91633190A' \
  test
```

To find an available simulator if the ID above is stale:
```bash
xcrun simctl list devices available | grep iPhone
```

- **Simulator:** Works for UI. Use **Features → Location → City Bicycle Ride** to simulate
  movement and watch the fog lift.
- **Device:** Sign the app with your personal team, install via Xcode, grant "Always" location
  permission, then go for a walk.

**Info.plist keys** (already set, listed here for reference — do not need to be re-added):

| Key | Value |
|-----|-------|
| `NSLocationWhenInUseUsageDescription` | `Fog of Walk uncovers the map as you explore your neighborhood.` |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | `Background location lets Fog of Walk track your path even when your phone is in your pocket.` |
| `UIBackgroundModes` | Array → Item 0: `location` |
| `UIApplicationSupportsMultipleScenes` | `false` |

There is no legacy `NSLocationAlwaysUsageDescription` key — only the combined
`...AndWhenInUseUsageDescription` string above is needed on the deployment targets this app
supports.

---

## 3. Regenerating `landmarks.sqlite`

Both `scripts/landmarks.sqlite` and `FogOfWalk/FogOfWalk/landmarks.sqlite` (~4 MB each) are
git-tracked binaries — the copy under `FogOfWalk/FogOfWalk/` is what actually ships, picked up
implicitly by the synchronized root group (it appears nowhere by name in `project.pbxproj`).

**If this file goes missing or fails to load, the failure is silent.**
`LandmarkSearchService.makeBundled()` falls back to an `EmptyLandmarkSource()` with no log line —
the landmark feature just quietly stops working. If pins and discovery both go dead with no
error, check that this file is actually present and loadable before looking anywhere else.

To regenerate it:

```bash
# 1. Fetch landmark candidates from Wikidata (items with coordinates, an enwiki article,
#    a curated set of instance-of types, and at least --min-sitelinks sitelinks; default 10).
#    There is no default --input/--output pair checked in as "landmarks.json" — use one of the
#    checked-in files (landmarks_10.json, landmarks_preview.json) or fetch fresh:
python3 scripts/fetch_landmarks.py --output scripts/landmarks_10.json --min-sitelinks 10

# 2. Build the SQLite file: a `landmarks` table plus a `landmarks_rtree` virtual R-tree index
#    (degenerate (lat, lat, lon, lon) boxes, since landmarks are points).
python3 scripts/make_landmarks_db.py --input scripts/landmarks_10.json --output scripts/landmarks.sqlite
```

After regenerating, copy the result to `FogOfWalk/FogOfWalk/landmarks.sqlite` so it ships in the
app bundle.
