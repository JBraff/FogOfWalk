# Automatic stationary pause and walking resume

**Status:** Owner-directed feasibility scope, 2026-10-15. Implement and evaluate in the isolated Study app first; the production default remains unchanged.
**Replaces for current delivery:** The measurement-first gates in [Location Energy and Reliable Resume](2026-10-09-location-energy-and-reliability.md), the long stationary attribution series, and the interim general battery-cost audit as prerequisites.

## Question and deliverable

Can Fog of Walk let tracking become inactive while the user is stationary and automatically capture the beginning of the next walk with the phone locked, without requiring the user to reopen the app?

Deliver the smallest credible answer quickly: a supported implementation approach, a Study-only working prototype or documented platform blocker, regression/full-suite results, one focused locked-screen idle-to-walk trial when a viable prototype exists, and an explicit proceed/reject/inconclusive decision. A practical rejection is a useful outcome. Existing manual OFF tests cannot answer the automatic-resume question.

The motivation is avoiding major unnecessary stationary work in a recreational app. Quantifying a battery-saving percentage, proving an optimal tracking policy, or collecting a large reliability matrix is outside this feasibility delivery. The experiment does not promise that automatic pausing will save a material amount of battery.

## Implementation path

1. Inspect the existing location ownership and installed SDK. Verify the chosen API's availability at the iOS 18.6 deployment floor and supported stationary/resume/background behavior before implementation. The earlier proposal's platform live-update approach is an initial candidate, not an already-qualified solution. Record a small supported design or an actual blocker; do not require a new energy baseline first.
2. Implement the smallest selectable Study-only stationary-aware source, preserving the legacy tracker as immediate fallback. The default for normal Fog and absent/unknown experimental settings stays legacy. Do not replace the production source as part of this feasibility answer.
3. Keep source/session ownership alive independently of map-view recreation. Cancel/invalidate replaced generations, reject their late callbacks, and prevent two primary trackers from operating together. Respect authorization changes, explicit stops, foreground recovery and errors. Preserve actual-sample-only 50 m exploration, local history, no haptics and existing recording behavior; avoid unrelated validation/store refactors.
4. Let the supported framework manage stationary/resume lifecycle. Do not manually stop every source and assume a timer, motion callback or coarse significant-change event will promptly restart it. Do not simply flip the legacy automatic-pausing flag: the earlier design records a background-resume regression.
5. Audit MapKit user-location requests so they do not unintentionally keep a second background location consumer active and defeat the prototype's stationary behavior. Make the smallest justified Study-only adjustment and document its effect on the location dot/follow behavior. This source check does not require a new resource-attribution study.
6. Extend existing bounded local diagnostics only as needed to identify source start/stop, actual framework stationary/resume state, fresh sample receipt and downstream visited cells. Callback silence or a hidden dot alone is not evidence of stationary suspension. Preserve app data and the installed Study identity when deploying a tested build.

No implementation or physical result is claimed by this plan. If the platform cannot supply a credible automatic-resume mechanism under these constraints, document that finding and keep legacy tracking rather than invent a wake-up guarantee.

## Software verification before phone time

Add meaningful XCTest regressions for source replacement/cancellation, stale callback rejection, permission/restart paths, stationary-state handling, and resumed fresh delivery reaching exploration. Follow the repository's actor-isolation conventions. Run the normal build and full XCTest suite. Use deterministic injected source events for software logic; simulator success does not establish physical background wake-up.

Prefer one review of the bounded prototype/lifecycle and proposed phone procedure before installation to additional instrumentation preparation. A concrete review finding can expand necessary work; the former multi-stage energy-study approvals are not prerequisites for this scope.

## First focused phone check

One initial feasibility trial, approximately 15–30 minutes stationary followed by a short 5–10 minute walk, is the starting budget. The prototype must record the actual stationary state before the departure portion can establish pause/resume feasibility. Predeclare that stationary observation bound before starting. If it never enters that state, report the test as inconclusive and investigate the specific reason; do not keep extending or repeating recordings without a diagnosis.

Before capture, choose a nearby early walking checkpoint and a simple route so the owner can judge whether the beginning of the walk was captured. Note approximate physical departure and checkpoint times using another clock or post-run recollection with explicit uncertainty. Do not impose the old measured-route, pedometer calibration or statistical departure-scoring procedure. If observations cannot distinguish a prompt resume from a substantial initial gap, the result is inconclusive rather than a pass.

- Use the isolated Study app, preserving its data. Normal Fog must not run a competing tracker. Complete permissions and setup first; ensure manual tracking-OFF control is not disabling the prototype.
- Start the minimal diagnostic capture, lock the phone and leave it stationary until the predeclared bound. Avoid an attached debugger, charging or active development connection; record the actual setup. Do not make Mac-side phone queries while recording.
- Walk the short route with the screen locked, without opening the app or manually restarting tracking. Do not force-quit it: force-quit recovery is a separate unsupported claim.
- After the walk, stop/export diagnostics and inspect the stationary indication, first fresh post-departure receipt, continued samples and resulting cells. Cached fixes, callback silence and a returning map dot cannot substitute for these observations.
- Power Profiler, exact start/end battery percentages, Do Not Disturb, standardized radio isolation and native sleep-lane qualification are not prerequisites for this functional trial. Use convenient representative conditions and record material interruptions. An optional power trace must not delay the question being answered.

## Decision and stopping rules

**Proceed with a limited next step:** Actual stationary handling is observed, walking produces fresh samples without app reopening, exploration captures the beginning of the route through the preselected checkpoint and continues, and no meaningful regression appears. State that this is one-phone feasibility evidence, not universal reliability or a quantified battery benefit.

**Reject the approach:** A specific platform/lifecycle limitation or reproducible failure makes automatic capture unreliable. Keep legacy tracking and record why. A physical test is unnecessary if a concrete implementation blocker already answers feasibility.

**Inconclusive:** Stationary state was never established, departure evidence is too ambiguous, or another specific problem prevents interpretation. Identify that problem and propose only the smallest targeted follow-up. Do not automatically request long idle trials, repeated pairs or a week of ordinary-use testing.

After one usable trial, report the answer before scheduling any more phone time. A failure can justify a software correction and one targeted retest; additional test scope requires a concrete unresolved question. Unrelated whole-app battery hunting is deferred unless it directly blocks this experiment.

## Delivery boundary

The feasibility deliverable is the Study prototype, tested code, redacted evidence and decision. Commit/publish task-owned implementation through the repository's authorized delivery workflow after review/checks; keep raw locations, device IDs and traces private. A normal-app default change or broader rollout is a separate owner decision after seeing the answer. Restore a functioning legacy source if the experiment is abandoned or fails. The existing 50 m grid, actual-sample behavior and user history remain protected.

Current work lifecycle, milestones and next actions remain in the authorized workspace initiative. Earlier protocols retain historical evidence value; their unpassed gates do not become Passed under this scope revision.
