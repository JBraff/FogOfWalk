# States & Countries Visited — Design

## Problem

Discovery Stats shows a "By Location" breakdown grouped by city (`VisitedCell.locality`), but there's no way to see which states/provinces or countries the user has visited. `LocalityGeocoder` already reverse-geocodes every newly-visited cell via `CLGeocoder`, but only keeps `p.locality` (or its fallbacks) — it discards `administrativeArea` and `country` from the same placemark.

## Goal

Show all-time lists of states/provinces and countries visited in the Discovery Stats sheet, using full display names (e.g. "California", "United States"). Lay the groundwork so a later "when did I last visit X" feature needs no further schema changes.

## Scope

Included:
- Two new `VisitedCell` attributes: `state`, `country` (optional strings, full names from `CLPlacemark.administrativeArea` / `.country`).
- Capturing these for newly-geocoded cells, and backfilling them for cells geocoded before this change.
- All-time-only "States" and "Countries" sections in `DiscoveryStatsView`.
- Extending the backup export/import payload to carry `state`/`country`.

Explicitly out of scope:
- Per-period (Today/Week/Month) state/country breakdowns — all-time only, per user decision.
- The "last visited a state/country" feature itself — not built now, but the data model changes here (retaining `firstVisited` per cell) mean it needs no new schema when it's built later; it would just compute `max(firstVisited)` over the cells in a `LocalityStats` group.

> **Update (2026-08-03):** The "States" list is restricted to the 50 US states and normalized to
> full names via a static abbreviation/full-name table (`Models/USState.swift`), reversing the
> original "no US-specific lookup table" decision above. See "Stats computation" and "UI" for the
> corrected behavior. `countryStats` is unaffected — countries are still shown unfiltered as
> stored (raw `CLPlacemark.country`).

## Data model

New Core Data model version (v3, following the existing `.xcdatamodeld` versioning pattern) adds two optional String attributes to `VisitedCell`:
- `state` — `CLPlacemark.administrativeArea`
- `country` — `CLPlacemark.country`

Both optional with no default needed beyond `nil` — a lightweight/automatic Core Data migration, since existing installs simply get `nil` for both attributes on existing rows until backfilled.

## Geocoding capture

`LocalityGeocoder.geocodeCluster(_:)` (`Models/LocalityGeocoder.swift`) already fetches a `CLPlacemark` per cluster and sets `cell.locality`. It will additionally set:
```swift
cell.state = p.administrativeArea
cell.country = p.country
```
No new network calls — same placemark, same request.

## Backfill

`LocalityGeocoder.geocodeUntaggedCells(context:)` currently fetches cells matching `locality == nil` for its one-time-per-launch backfill pass. Its predicate broadens to:
```
cellSizeMeters == %f AND (locality == nil OR state == nil OR country == nil)
```
This picks up both never-geocoded cells and cells geocoded before this change (which have `locality` set but `state`/`country` nil), reusing the existing bucketed-clustering and rate-limited-request machinery unchanged. The `hasBackfilled` once-per-launch guard stays as is.

## Stats computation

`LocalityStats` (`Models/DiscoveryStatsModel.swift`) is renamed generically: its `locality: String` field becomes `name: String`, since it will now represent a city, state, or country interchangeably. `LocalityRow` (`Views/DiscoveryStatsView.swift`) and the existing `localitySection` update to use `.name` instead of `.locality` — no behavior change for the existing city breakdown.

`DiscoveryStatsModel` gains two new all-time-only properties:
```swift
var stateStats: [LocalityStats] = []
var countryStats: [LocalityStats] = []
```
Computed in `refresh(context:)` alongside the existing all-time locality bucket, in a single pass over all cells. `countryStats` buckets by `cell.country ?? "Unknown"` unchanged. `stateStats` is restricted to recognized US states: `cell.state` is resolved via `USState.canonicalFullName(for:)` (`Models/USState.swift`, a static 50-entry abbreviation → full-name table), and cells with a nil/unrecognized/non-US value are excluded from the bucket entirely (no "Unknown" entry). This both filters out non-US administrative areas (e.g. Canadian provinces) and normalizes mixed abbreviation/full-name values (e.g. "CA" and "California") into one entry. Both bucket dictionaries reuse the existing `buildStats(_:)` helper (centroid/span/sort-by-count-descending) to produce `[LocalityStats]`.

## UI

Two new `GroupBox` sections in `DiscoveryStatsView`, placed after the existing "By Location" section:
- **"States"** — `LocalityRow` per state, sorted by count descending, tap-to-navigate via `onNavigate` (same pattern as city rows). Includes a "`x` of `USState.count` (50) states visited" summary line above the list.
- **"Countries"** — same treatment, per country, no summary line (unbounded — not restricted to a fixed set).

No period picker (all-time only). Empty state text follows the existing pattern (e.g. "No states explored yet") when there are zero geocoded cells.

## Backup payload

`BackupVisitedCell` (`Models/BackupService.swift`) gains `state: String?` and `country: String?`. `BackupPayload.currentSchemaVersion` bumps to the next version; `BackupService.decode(_:)`'s version gate is updated accordingly (still rejecting unknown/future versions outright — no best-effort partial decode, matching existing behavior).

`BackupService.export` includes the new fields when building each `BackupVisitedCell`. `BackupService.merge`'s cell-insert path (`ExplorationStore.addCells(_:)`) carries `state`/`country` through the same way it already carries `locality` — set on insert for new cells; existing cells keep their current values (matching how `locality` is already handled, so a merge never overwrites already-geocoded data).

## Testing

- `LocalityGeocoderTests.swift`: geocode result sets `state`/`country`; backfill predicate picks up cells with `locality` set but `state`/`country` nil.
- `DiscoveryStatsModelTests.swift`: `stateStats`/`countryStats` grouping, sort-by-count-descending; existing locality tests updated for the `name` rename. `stateStats` additionally covers: nil/unrecognized/non-US values excluded; abbreviation and full-name values for the same state merge into one entry. `countryStats` still bucketing nil values as "Unknown".
- `USStateTests.swift`: table has exactly 50 entries; abbreviation and case-insensitive full-name lookups resolve correctly; unrecognized values return `nil`.
- `BackupServiceTests.swift`: round-trip encode/decode/merge carries `state`/`country`; schema version bump; merge does not overwrite existing cells' `state`/`country`.
