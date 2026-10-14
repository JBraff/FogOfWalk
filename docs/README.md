# Fog of Walk documentation

This directory contains durable, product-local documentation for Fog of Walk.
Runtime code, tests, and configuration remain authoritative for current behavior.
The workspace initiative tracker records only current lifecycle, milestones,
blockers, and next actions; it does not replace these product documents.

## Start here

- [System architecture](SYSTEM.md) describes the enduring application structure,
  data ownership, and operational constraints.
- [Location Energy and Reliable Resume](proposals/2026-10-09-location-energy-and-reliability.md)
  is the current proposal for measuring and reducing battery use. The original
  [Adaptive Location Tracking plan](proposals/2026-09-04-adaptive-location-tracking.md)
  is deprecated. Its workspace initiative is tracked
  separately under `agent-workspace/work/initiatives/`.

## Documentation areas

- `proposals/` holds product designs that are under consideration and have not
  yet become accepted architecture.
- `history/plans/` and `history/designs/` preserve completed or superseded
  implementation planning artifacts without presenting them as current work.
- `decisions/` will contain accepted, durable architectural decisions when a
  decision needs its own rationale and alternatives.
- `evidence/` will contain material implementation or physical-device evidence
  when it supports a product decision, verification claim, or release outcome.

Location-energy study records include the
[baseline protocol](evidence/location-energy-baseline-protocol.md) and
[diagnostics and physical-pilot verification](evidence/location-energy-diagnostics-verification.md).
The [departure reference qualification procedure](evidence/location-energy-reference-qualification.md)
defines the timing and measured-distance evidence needed after the build-2 pilot.
The [analysis readiness record](evidence/location-energy-analysis-readiness.md)
documents offline trace-export checks and remaining preflight work.
The [attribution preparation draft](evidence/location-energy-attribution-preparation.md)
records current measurement limits and the checks needed before another comparison.
These records distinguish reporting checks from the unqualified physical
measurement gates; they do not establish battery savings.
