# Fog of Walk — Xcode Setup

All Swift source files are ready. Follow these steps to create the Xcode project
and wire everything together.

---

## 1. Create the Xcode Project

1. Open Xcode → **File → New → Project**
2. Choose **iOS → App**
3. Fill in:
   - **Product Name:** `FogOfWalk`
   - **Bundle Identifier:** `com.yourname.fogofwalk`
   - **Interface:** SwiftUI
   - **Language:** Swift
   - **Include Tests:** ✓
   - **Use Core Data:** ✗ (we add it manually)
4. Save to the root of this repo — Xcode will create `FogOfWalk.xcodeproj` here.

---

## 2. Replace the Generated Sources

Delete Xcode's generated stubs and add the files from this repo:

| Xcode group            | Files to add                                     |
|------------------------|--------------------------------------------------|
| `FogOfWalk/`           | `FogOfWalkApp.swift`, `ContentView.swift`        |
| `FogOfWalk/Models/`    | `GridCell.swift`, `GridSettings.swift`, `ExplorationStore.swift`, `VisitedCell+CoreData.swift` |
| `FogOfWalk/Services/`  | `LocationService.swift`                          |
| `FogOfWalk/Views/`     | `MapContainerView.swift`, `FogView.swift`, `StatsView.swift`, `SettingsView.swift` |
| `FogOfWalkTests/`      | `GridCellTests.swift`                            |

To add files: **right-click group → Add Files to "FogOfWalk"** (or drag-and-drop).
Make sure **"Copy items if needed"** is unchecked if files are already in the right folder.

---

## 3. Add the Core Data Model

1. **File → New → File → Core Data → Data Model** — name it `FogOfWalk`
2. Xcode creates `FogOfWalk.xcdatamodeld` — **delete it** (move to trash)
3. **File → Add Files to "FogOfWalk"** → select the existing
   `FogOfWalk/FogOfWalk.xcdatamodeld` directory from this repo
4. Confirm it appears in the project navigator and is in the app target

---

## 4. Info.plist — Location Permissions

Open **FogOfWalk → Info** (target settings) and add these keys:

| Key | Value |
|-----|-------|
| `NSLocationWhenInUseUsageDescription` | `Fog of Walk uncovers the map as you explore your neighborhood.` |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | `Background location lets Fog of Walk track your path even when your phone is in your pocket.` |
| `UIBackgroundModes` | Array → Item 0: `location` |

---

## 5. Background Modes Capability

1. Select the **FogOfWalk** target → **Signing & Capabilities**
2. Click **+ Capability** → **Background Modes**
3. Check **Location updates**

---

## 6. Deployment Target

Set **Minimum Deployments → iOS 17.0** (required for `@Observable`).

---

## 7. Build & Run

- **Simulator:** Works for UI. Use **Features → Location → City Bicycle Ride**
  to simulate movement and watch the fog lift.
- **Device:** Sign the app with your personal team, install via Xcode,
  grant "Always" location permission, then go for a walk.

---

## Testing

Run **FogOfWalkTests** — the `GridCellTests` suite validates coordinate math
at NYC, London, Paris, Sydney, and the equator across all four cell sizes.
