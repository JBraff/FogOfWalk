# Destination-first route comparison prototype

The normal app's **Compare routes** button opens a destination search. Submit a
place name or address, choose a result, and compare the walking routes Apple
returns. Each option shows walking time, distance and **≈ N new cells**. The
fastest returned route is selected initially; tapping another highlights it above
the fog and fits the map to that route. **Done** closes the sheet
while retaining the preview. **Route options** reopens it; **Clear** removes it.
The medium-height sheet also permits map interaction.

This is a comparison of Apple's alternatives, not a discovery-optimized route
generator. One returned route is a supported result. New searches and route
requests require connectivity. The preview remains in memory when backgrounded;
it is not saved across app launches. In-flight requests are cancelled when the
sheet closes or the app becomes inactive, and a generation guard ignores stale
completions even if cancellation races with a response. Requests happen only on
submission or explicit retry, never on each location update or keystroke.

The origin is an existing recorded location sample no more than 60 seconds old,
with valid coordinates and horizontal accuracy between 0 and 100 metres. When
unavailable the sheet explains the problem and offers retry. The feature adds no
location stream and does not alter permission or tracking policy. Its entry point
is hidden in Study. Production services are unchanged.

## Discovery estimate

`RouteCellEstimator` traverses each route segment in the existing degree-aligned
50 m grid. It counts unique crossed cells, subtracting the local visited set.
Repeated portions count once. Exact corner crossings advance both axes, excluding
adjacent cells touched only at the corner; vertices themselves use the same
half-open cell convention as recording. The number is potential discovery, not a
promise: GPS sampling and the path actually walked determine recorded exploration.
The renderer's soft fog holes are not a separate exploration metric.

Geometry processing has a total 50,000-operation budget, including vertices and
repeated crossings. Empty, invalid, antimeridian-spanning or excessive geometry
has an unavailable estimate, never a misleading partial count. Apple routes over
50,000 vertices are omitted before coordinate allocation. Existing visit and
landmark data are read only; neither route selection nor preview uncovers cells.
Visited history is never sent to Apple; only search and routing inputs are used.

## Verification and review

Tests cover intermediate-cell traversal, corners, boundaries, negative coordinates,
repeat paths, invalid/excessive geometry, subtraction, fresh origins, search and
routing races, network failure, no-route/single-route results, selection, clear,
overlay ordering and preservation of fog/history. An offline UI test exercises
comparison, selection, another destination search and clear.

The Debug-only `-route-prototype-fixture` launch argument supplies two synthetic
paths between public coordinates and an in-memory visited history. They are
illustrations, not Apple walking directions or route-quality evidence. The gate
runs before production store/service construction, starts no location services,
and leaves standard preferences unchanged. This is also the reproducible visual
review demo; it is excluded from Release builds.

The feasibility probe requested walking alternatives for three public-landmark
pairs (two NYC pairs and one SF pair); all three returned two routes. This small
Mac API sample supports a prototype, not guaranteed walking alternatives in every
area. Phone checks remain necessary for route legibility, search near the owner,
portrait/landscape layout and the practical value of the discovery differences.
No phone installation or release is part of this prototype delivery.
