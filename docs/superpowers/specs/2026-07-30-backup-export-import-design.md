# Backup Export/Import — Design

## Problem

There is no way to back up exploration history (visited grid cells) or landmark discovery state. If a user loses or resets their device, that history is gone permanently. `AGENTS.md` already notes there is no data-management UI of any kind today.

## Goal

Let a user manually export their exploration data to a file they control (Files, iCloud Drive, AirDrop, email, etc.), and import that file back in — either to restore onto a new device or to merge two devices' histories together. This is a manual, on-demand action, not automatic/continuous sync (no CloudKit).

## Scope

Included:
- Export visited cells + discovered-landmark state to a single JSON file.
- Import a previously exported file, merging it into the current device's data.
- A new Settings screen to host these actions.

Explicitly out of scope:
- Automatic/continuous backup (e.g. `NSPersistentCloudKitContainer`).
- Exporting undiscovered landmarks or bundled landmark reference metadata (name/category/coordinates) — those are re-derived from the bundled `landmarks.sqlite` on the importing device.
- Any settings other than backup (existing `GridSettings` toggles are not being moved into this screen as part of this work, though the screen should not preclude that later).

## Architecture

A new `SettingsView.swift` sheet, opened from `ContentView` via a new toolbar button and `@State private var showSettings = false` / `.sheet(isPresented:)`, following the existing boolean-sheet pattern used for `showStats` (`ContentView.swift:49`).

A new `BackupService` (plain struct/class, not `@Observable` — stateless) encapsulates encode/decode and merge logic, taking `ExplorationStore` and `LandmarkStore` as dependencies. This keeps Core Data fetch/merge details out of the view.

## Backup file format

Plain JSON, versioned for forward compatibility:

```json
{
  "schemaVersion": 1,
  "exportedAt": "2026-07-30T12:00:00Z",
  "visitedCells": [
    {"cellX": 12, "cellY": 34, "cellSizeMeters": 50.0, "firstVisited": "2026-01-05T08:00:00Z", "locality": "Downtown"}
  ],
  "landmarks": [
    {"identifier": "Q12345", "firstDiscovered": "2026-01-10T09:30:00Z"}
  ]
}
```

- `visitedCells`: every `VisitedCell` row (`cellX`, `cellY`, `cellSizeMeters`, `firstVisited`, `locality`).
- `landmarks`: only landmarks where `isDiscovered == true`, with `identifier` (stable Wikidata QID) and `firstDiscovered`. Name/category/coordinates are intentionally omitted — they come from bundled reference data, not user data.

## Export flow

1. `BackupService.export(explorationStore:landmarkStore:) throws -> Data`:
   - Fetches all `VisitedCell` rows via `ExplorationStore.viewContext` (a plain `NSFetchRequest<VisitedCell>`, no new store method required for read-only export).
   - Reads `LandmarkStore.allLandmarks`, filters to `isDiscovered == true`.
   - Encodes to JSON via `JSONEncoder` (ISO8601 date strategy).
2. Data is written to a temp file named `FogOfWalk-Backup-<yyyy-MM-dd>.json`.
3. Presented via `ShareLink` from `SettingsView` so the user can save/share it through the system share sheet. No custom file-picker/export UI needed.

## Import / merge flow

1. `.fileImporter(contentTypes: [.json])` in `SettingsView` lets the user pick a backup file.
2. `BackupService.import(data:) throws -> BackupPayload` decodes the file and validates `schemaVersion` (reject unknown/future versions with a clear error — do not attempt best-effort partial decoding).
3. `BackupService.merge(payload:into:landmarkStore:) throws -> MergeSummary`:
   - **Visited cells**: new `ExplorationStore.addCells(_:)` method. For each imported cell, if no row exists for `(cellX, cellY, cellSizeMeters)`, insert it with the imported `firstVisited`/`locality`. If a row already exists, keep the **earlier** of the two `firstVisited` values (do not touch `locality` if already set). This differs from the existing `addCell(_:)`, which stamps `firstVisited = Date()` — that behavior is correct for live visits but wrong for merging historical data.
   - **Landmarks**: new `LandmarkStore.restoreDiscovered(_:)` method taking `[(identifier: String, firstDiscovered: Date)]`. For each entry, find the matching `Landmark` by `identifier` (skip silently if not found — the bundled reference data may not include it, e.g. bundled dataset changed between export and import devices); set `isDiscovered = true`, and `firstDiscovered` to the earlier of existing/imported value if already discovered, or the imported value if not.
   - Both merges run as a single background-context save — decode fully and validate before mutating either store, so a malformed file never leaves partial writes.
4. `SettingsView` shows a result summary, e.g. "Imported 340 new cells, 12 new landmarks" (counts of rows actually added/updated, from `MergeSummary`).

## Error handling

- Invalid JSON, unreadable file, or unsupported `schemaVersion` → alert with a clear message; no store mutation occurs (decode/validate happens entirely before any Core Data write).
- File picker cancellation → no-op, no error alert.

## Testing

Unit tests for `BackupService` against an in-memory `NSPersistentContainer` (matching existing `FogOfWalkTests` conventions):
- Round-trip: export then import into a fresh store reproduces identical `VisitedCell`/discovered-`Landmark` state.
- Merge keeps the earlier `firstVisited`/`firstDiscovered` when a row already exists on the importing device.
- Malformed JSON and unsupported `schemaVersion` are rejected without mutating either store.
- Importing a landmark `identifier` not present in the local bundled dataset is skipped without error.
