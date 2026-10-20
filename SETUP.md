# Fog of Walk — Project Setup

The Xcode project, its capabilities, and the Core Data model are all **checked into this repo**.
There is nothing to create — cloning and building is enough. This document explains how the
checked-in project is wired, how to build and run it (including the separate Study app), and how
to regenerate the bundled landmark database if you need to.

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
- **Core Data model:** one `FogOfWalk.xcdatamodeld` containing three model *versions*:
  `FogOfWalk.xcdatamodel`, `FogOfWalk 2.xcdatamodel`, and `FogOfWalk 3.xcdatamodel`, with
  `.xccurrentversion` selecting v3. They are not separate `.xcdatamodeld` directories. `VisitedCell`
  is in all three versions. v2 added `Landmark` and the `byCellSizeAndCoords` fetch index, and v3
  added the optional `VisitedCell.state` and `country` attributes. The store relies on automatic
  lightweight migration. Before resetting an unreadable store, recovery copies the database
  and all existing WAL/SHM sidecars to unique `.corrupt-<timestamp>` siblings. Any backup
  failure preserves the originals and stops recovery; a reset failure also stops recovery
  without fallback deletion. The user sees a storage error and writes are disabled for that
  launch. Successful recovery reports the history reset. Every new version must be inferable.
- **Deployment target:** app target `IPHONEOS_DEPLOYMENT_TARGET = 18.6`; test targets `26.2`;
  project-level default `26.2`. Building needs Xcode 26.2 or later (it was last verified with
  Xcode 27), because the project uses `SWIFT_DEFAULT_ACTOR_ISOLATION` and
  `SWIFT_APPROACHABLE_CONCURRENCY`.
- **Two app identities:** the same target also builds the separate Study app through
  command-line build-setting overrides. See section 3.

---

## 2. Build & run

```bash
# Build (replace the simulator name if needed)
xcodebuild \
  -project FogOfWalk/FogOfWalk.xcodeproj \
  -scheme FogOfWalk \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  build

# Run tests
xcodebuild \
  -project FogOfWalk/FogOfWalk.xcodeproj \
  -scheme FogOfWalk \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  test
```

To find an available simulator if that name doesn't exist:
```bash
xcrun simctl list devices available | grep iPhone
```

If `xcodebuild` reports **"CoreSimulator is out of date"** or "Unable to load simulator
devices", Xcode was updated without installing its first-launch components. Run
`sudo xcodebuild -runFirstLaunch` (or open Xcode once and accept the component install), then
retry. Until then, `-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` can
check that the code compiles, but it does not run the tests.

- **Simulator:** Works for UI. Use **Features → Location → City Bicycle Ride** to simulate
  movement and watch the fog lift.
- **Device:** Sign the app with your personal team, install via Xcode, grant "Always" location
  permission, then go for a walk.

**Info.plist keys** (already set, listed here for reference — do not need to be re-added):

| Key | Value |
|-----|-------|
| `NSLocationWhenInUseUsageDescription` | `Fog of Walk uncovers the map as you explore your neighborhood.` |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | `Background location lets Fog of Walk track your path even when your phone is in your pocket.` |
| `NSMotionUsageDescription` | Study wording: post-run motion/step history. Shipped by both identities, used only by the Study app. |
| `CFBundleDisplayName` | `$(FOG_APP_DISPLAY_NAME)`: `Fog-Of-Walk` by default, overridden for the Study app |
| `UIBackgroundModes` | Array → Item 0: `location` |
| `UIApplicationSupportsMultipleScenes` | `false` |

There is no legacy `NSLocationAlwaysUsageDescription` key — only the combined
`...AndWhenInUseUsageDescription` string above is needed on the deployment targets this app
supports.

---

## 3. Building the Study app

The Study app is an isolated install used for location-battery feasibility experiments. It is the
same target with these build-setting overrides (pass them to `xcodebuild` or set them for a
one-off Xcode build; do not commit them to the project):

```text
PRODUCT_BUNDLE_IDENTIFIER=com.jeremybraff.fogofwalk.study
FOG_APP_DISPLAY_NAME="Fog Walk Study"
PRODUCT_NAME=Fog-Walk-Study
CURRENT_PROJECT_VERSION=<next Study build number>
```

At runtime the app detects the Study bundle ID. Only then does it enable the Settings →
Location Study section, the alternative location source, and diagnostic capture. Always
install over the existing Study app: uninstalling deletes its diagnostic history. Follow
[the prototype record](docs/evidence/automatic-pause-resume-prototype.md) for install and
trial procedure. Diagnostic logs contain precise locations and must never be committed.

---

## 4. Regenerating `landmarks.sqlite`

Both `scripts/landmarks.sqlite` and `FogOfWalk/FogOfWalk/landmarks.sqlite` (~4 MB each) are
git-tracked binaries — the copy under `FogOfWalk/FogOfWalk/` is what actually ships, picked up
implicitly by the synchronized root group (it appears nowhere by name in `project.pbxproj`).

**If this file goes missing or fails to load, the app shows no error.**
`LandmarkSearchService.bundledSource()` prints one console line and falls back to an
`EmptyLandmarkSource()`, and the landmark feature quietly stops working. If pins and discovery
both go dead, check that this file is present and loadable before looking anywhere else.

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
