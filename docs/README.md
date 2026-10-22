# Fog of Walk documentation

This directory contains durable, product-local documentation for Fog of Walk.
Runtime code, tests, and configuration remain authoritative for current behavior.
The workspace initiative tracker records only current lifecycle, milestones,
blockers, and next actions; it does not replace these product documents.

## Start here

- [`AGENTS.md`](../AGENTS.md) at the repository root is the working guide for
  contributors and coding agents: layout, data flow, gotchas, test conventions,
  and build commands. [`SETUP.md`](../SETUP.md) covers project wiring, the Study
  app build, and regenerating the landmark database.
- [System architecture](SYSTEM.md) describes the enduring application structure,
  data ownership, and operational constraints.
- [Navigation and Explore Mode — revised proposal](proposals/2026-10-22-navigation-explore-revised.md)
  evaluates orientation, route comparison, foreground guidance and exploration
  suggestions against the existing code and platform limits. It includes proposed
  delivery slices and questions for engineering review; it is not accepted
  architecture or an authorized initiative. The
  [original product brief](proposals/2026-10-22-navigation-explore-original.md)
  is preserved as supplied for comparison.
- [Automatic stationary pause and walking resume](proposals/2026-10-15-automatic-stationary-pause-and-resume.md)
  is the owner-directed feasibility plan: build the smallest Study-only prototype
  and answer whether stationary tracking can pause and walking resumes automatically
  with the screen locked. Start with one focused idle-to-walk trial after software
  verification. Extensive battery-comparison trials are outside this delivery.
  The [Study prototype and focused trial](evidence/automatic-pause-resume-prototype.md)
  records its supported source design, software evidence and phone procedure.
- [Location Energy and Reliable Resume](proposals/2026-10-09-location-energy-and-reliability.md)
  retains the earlier measurement-first study. Its measurement prerequisites and
  repetition matrix are superseded for current work. The original
  [Adaptive Location Tracking plan](proposals/2026-09-04-adaptive-location-tracking.md)
  remains deprecated. Lifecycle and next actions live in the authorized
  `agent-workspace/work/initiatives/fog-adaptive-location-tracking.md` record.

## Documentation areas

- `proposals/` holds product designs that are under consideration and have not
  yet become accepted architecture.
- `history/plans/` and `history/designs/` preserve completed or superseded
  implementation planning artifacts without presenting them as current work.
- `decisions/` will contain accepted, durable architectural decisions when a
  decision needs its own rationale and alternatives.
- `evidence/` contains material implementation or physical-device evidence
  when it supports a product decision, verification claim, or release outcome.

Historical location-energy study records include the
[baseline protocol](evidence/location-energy-baseline-protocol.md) and
[diagnostics and physical-pilot verification](evidence/location-energy-diagnostics-verification.md).
The [departure reference qualification procedure](evidence/location-energy-reference-qualification.md)
defines the timing and measured-distance evidence needed after the build-2 pilot.
The [analysis readiness record](evidence/location-energy-analysis-readiness.md)
documents offline trace-export checks and remaining preflight work.
The [attribution preparation draft](evidence/location-energy-attribution-preparation.md)
records current measurement limits and the checks needed before another comparison.
The [locked-screen readiness procedure](evidence/location-energy-locked-screen-readiness.md)
prepares the next bounded stationary check, including concrete Xcode disconnection
and separate sleep/consumer-attribution decisions.
The [stationary tracking-control protocol](evidence/location-energy-tracking-control-protocol.md)
prepares Study build 4's all-consumer OFF control and the subsequent matched
comparison. Its first phone check qualifies the newly disabled consumers and
sleep instrumentation before any long pair.
These records preserve their original evidence and limits; they do not establish
automatic pause/resume or battery savings. Their old next-test instructions do not
override the current focused feasibility plan.
