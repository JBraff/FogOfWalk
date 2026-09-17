# Fog of Walk documentation

This directory contains durable, product-local documentation for Fog of Walk.
Runtime code, tests, and configuration remain authoritative for current behavior.
The workspace initiative tracker records only current lifecycle, milestones,
blockers, and next actions; it does not replace these product documents.

## Start here

- [System architecture](SYSTEM.md) describes the enduring application structure,
  data ownership, and operational constraints.
- [Adaptive Location Tracking](proposals/2026-09-04-adaptive-location-tracking.md)
  is the currently proposed product design. Its workspace initiative is tracked
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

There are currently no standalone decision or evidence records. Do not create
them merely to populate the directories.
