Fog of Walk — Navigation & Explore Mode

Product Requirements Brief

Status: Proposal for Engineering Review
Scope: Walking navigation, exploration-aware routing, and guided discovery
Priority: Incremental delivery, with engineering discretion

⸻

1. Executive Summary

Fog of Walk helps users discover the world by revealing areas of a map as they physically explore them.

Today, the application is primarily an exploration tracker. This initiative aims to make it a more useful real-time companion for walking through unfamiliar cities, helping users understand where they are, navigate to destinations, and discover interesting places and unexplored streets along the way.

The guiding product principle:

Fog of Walk should become a better way to discover a city on foot, not a general-purpose replacement for Google Maps.

The proposed functionality has three pillars:

1. Map Orientation: Make it easier to determine which direction the user is facing, follow their movement, and recenter the map.
2. Exploration-Aware Navigation: Offer walking routes that balance travel time, route quality, and the amount of new territory uncovered.
3. Explore Mode: Help users discover unexplored streets and interesting landmarks without needing a destination.

Engineering should evaluate the existing implementation and recommend the most practical architecture, scope, and delivery sequence.

2. Problem Statement

While walking through an unfamiliar city, users currently face several challenges.

2.1 Difficult to determine walking direction

The map displays the user’s location as a blue dot but does not clearly communicate which direction they are facing.

This makes it difficult to identify the next street or block to explore, particularly when stationary or arriving at an intersection.

2.2 Difficulty keeping the map centered

After manually panning the map, users lack an obvious way to return to their current position.

They may need to manually reposition the map or close and reopen the app.

2.3 No exploration-aware navigation

Traditional mapping applications optimize primarily for travel time or distance.

Fog of Walk has a unique opportunity to recommend routes based on how much new territory the user could uncover.

A user may happily walk 15 minutes instead of 12 if the longer route passes through several unexplored blocks.

2.4 No proactive exploration guidance

Users can visually inspect the fog-of-war map but must manually decide which direction to explore.

The application could offer helpful suggestions based on unexplored streets, route quality, and nearby landmarks.

3. Goals and Product Principles

Goals

* Improve orientation and map usability while walking.
* Help users navigate toward a destination while discovering new territory.
* Make it easier to explore unfamiliar places without a destination.
* Incorporate existing landmark information into exploration suggestions.
* Preserve the app’s core exploration-tracking experience.
* Deliver useful functionality incrementally.

Product Principles

Exploration is the differentiator. Prioritize functionality that helps users discover more of their surroundings.

Walking quality matters. Routes should be pleasant, practical, and pedestrian-friendly, not simply maximize the amount of fog cleared.

Keep the map central. Navigation features should complement the existing map rather than replace it.

Preserve existing functionality. Existing exploration history, background tracking, and offline behavior must not regress.

Reuse existing capabilities. Prefer the application’s current map, location tracking, exploration logic, saved places, and landmark datasets over creating parallel systems.

Engineering flexibility. This brief communicates desired outcomes and proposed behavior. It does not prescribe architecture or mandate a specific implementation.

4. Feature Requirements

4.1 Map Orientation and Controls

Suggested priority: P0

Add the following capabilities to the existing map.

Directional indicator

* Display the user’s approximate facing direction using a directional cone, arrow, or comparable visual indicator.
* Keep the map north-up by default.
* Handle unavailable or unreliable heading information gracefully.
* Prefer platform-native location and heading capabilities where appropriate.

Recenter button

* Add a clearly visible control to recenter the map on the current location.
* Recenter without requiring the app to restart.
* Support a follow mode in which the map tracks the user’s location.
* Allow manual panning without the map immediately snapping back.
* Provide an obvious way to resume following the user.

Optional heading-up mode

* Allow the user to switch between north-up and heading-up map orientations.
* Potentially reuse the recenter control for toggling modes.
* Defer if map rotation introduces significant complexity.

The minimum acceptable initial implementation is a reliable directional indicator and recenter control.

4.2 Destination-Based Navigation

Suggested priority: P0, implemented incrementally

Users should be able to enter a destination and compare walking routes that offer different levels of exploration.

Destination selection

Prioritize:

* Address and place-name search.
* Existing saved places.
* Integration with Collections or equivalent saved-location functionality, where available.

Lower priority:

* Selecting a destination by tapping or long-pressing the map.
* Specifying a custom starting location.

For the initial implementation, routes should start at the user’s current GPS location.

Route generation

Offer up to three route types:

Route	Objective	Suggested detour
Fastest	Reach the destination efficiently	None
Balanced	Gain meaningful exploration with modest extra walking	Up to 20%
Maximum Exploration	Favor new territory within reasonable limits	Up to 50%

These percentages represent maximum additional walking time, not targets.

Engineering should consider reasonable absolute detour limits for longer walks.

The system should not generate unnecessary detours merely to reach a percentage.

Meaningful alternatives only

Do not force three routes when they are substantially similar.

If only one route makes sense, present one route.

When exploration benefits are limited, explain that the surrounding area is already well explored or that alternatives offer minimal benefit.

Route visualization and comparison

* Display alternative routes directly on the existing map.
* Visually distinguish the alternatives.
* Highlight the selected route.
* Allow users to switch between routes.
* Show estimated walking time, distance, and exploration benefits.
* Highlight which portions of each route are currently unexplored.
* Show estimated additional map area that could be uncovered.
* Where useful, show what percentage of a route is unexplored.

Estimates should derive from the application’s existing fog-of-war logic wherever practical and avoid counting already-explored territory as new.

These estimates need not be perfectly precise, but should support meaningful comparison.

4.3 In-App Navigation

Suggested priority: P0 foundation, enhanced as feasible

After selecting a route, users should be able to follow it using Fog of Walk.

Minimum navigation experience

* Display the selected route over the existing map.
* Continuously update the user’s position.
* Display basic upcoming turn instructions.
* Show remaining distance and estimated travel time.
* Clearly distinguish completed and upcoming route segments.
* Update remaining exploration opportunities as the walk progresses.

Interface

Keep the existing map as the primary interface.

Use a compact, expandable navigation panel displaying relevant information.

Users should be able to collapse the panel to maximize map visibility.

Route deviation

Maintain a stable selected route rather than continuously recalculating.

When users deviate significantly, offer to recalculate the route while preserving the original destination and exploration objectives.

Automatic rerouting may be added where practical, but should avoid becoming distracting or intrusive.

Enhanced navigation

If straightforward to implement with existing frameworks, consider including:

* More comprehensive turn-by-turn instructions.
* Automatic rerouting.
* Native navigation capabilities.
* Voice guidance.

These should not delay delivery of the core exploration-aware routing experience.

External navigation

Investigate an option to open a selected route in Apple Maps or Google Maps.

This is useful only if the intended route can be preserved reasonably well. Simply opening the destination in another mapping application may discard the exploration-aware route.

If faithful route transfer is not supported, engineering should clearly identify the limitation and recommend whether the feature is worthwhile.

4.4 Fog-of-War Integration

Suggested priority: P0

Navigation must preserve Fog of Walk’s fundamental exploration mechanics.

* Keep fog visible during navigation.
* Make the navigation route readable over unexplored territory.
* Permit optional route previews that reveal enough street detail for navigation.
* Do not permanently uncover territory merely because a route was generated, previewed, or selected.
* Continue permanently uncovering territory only through the application’s existing physical exploration rules.
* Preserve existing exploration data and tracking behavior.

The implementation should avoid separate, conflicting definitions of explored territory between the mapping, tracking, and navigation systems.

4.5 Explore Mode

Suggested priority: P0 foundation, with progressive enhancements

Explore Mode is a dedicated experience for discovering new territory without specifying a destination.

Activation

* Provide a prominent Explore control on the existing map.
* Activate exploration guidance only when explicitly requested.
* Keep the normal map relatively uncluttered when Explore Mode is inactive.

Unexplored street highlighting

Highlight nearby streets or areas that the user has not explored.

Suggestions should consider opportunities several blocks ahead, not just the nearest unexplored point.

Directional suggestions

Offer approximately two or three useful suggestions, such as:

* “Head north to explore several new blocks.”
* “Turn right for a mostly unexplored neighborhood.”
* “Continue west to discover an unvisited landmark.”

Tapping a suggestion should preview an appropriate path on the map without necessarily initiating formal navigation.

Walking quality

Prefer suggestions that result in pleasant, logical walks.

Where supporting data is available, favor pedestrian-friendly streets, parks, interesting neighborhoods, and walkable public spaces.

Avoid unnecessary backtracking, inaccessible routes, excessive zigzags, or frequent U-turns.

Exploration coverage should be balanced against walking quality rather than optimized in isolation.

4.6 Generated Exploration Walks

Suggested priority: P0/P1, depending on complexity

Allow users to request an exploration walk without entering a destination.

Suggested duration presets

* 15 minutes
* 30 minutes
* 60 minutes

Walk types

Round trip: Generate a route that begins and ends near the user’s current location.

One way: Generate a route that explores new territory and finishes at a suggested endpoint.

The app should balance duration, newly uncovered territory, route quality, and optional landmarks.

These walks should integrate with the same map display, progress tracking, and basic navigation functionality used for destination routing.

Engineering may implement round-trip walks before one-way walks if appropriate.

Future enhancements may include custom durations, starting points, ending points, and more advanced preferences.

4.7 Landmark-Aware Exploration

Suggested priority: P0/P1, phased based on existing capabilities

Fog of Walk already maintains lists of famous and interesting locations and has mechanisms for displaying them.

These existing capabilities should be the starting point.

Functional requirements

* Reuse existing curated landmark datasets.
* Reuse existing landmark display functionality.
* Identify nearby landmarks relevant to exploration.
* Prioritize landmarks the user has not previously visited.
* Use existing location or exploration history to infer whether landmarks have been visited, where reliable.
* Include worthwhile landmarks in directional suggestions and generated routes when feasible.

Optional landmark preference

Explore Mode should eventually allow users to choose between:

1. Territory-focused exploration.
2. Exploration that also favors notable landmarks.

Landmark-aware routing should not force large detours or significantly worsen route quality.

Previously visited landmarks

P0 should prioritize unvisited landmarks.

P1 may allow previously visited landmarks to be suggested when they contribute to a particularly worthwhile route.

Later enhancements

Additional points-of-interest sources, personalized interests, scenic preferences, and recommendations beyond the existing datasets can be considered separately.

Avoid building a new POI database unless necessary.

4.8 Navigation Progress

Suggested priority: P0

During active navigation, provide lightweight progress information.

* Completed portion of route.
* Remaining distance and estimated walking time.
* Estimated unexplored territory still ahead.

Avoid overwhelming the user with statistics.

Post-walk summary — P1

After completing a walk, optionally display:

* Total distance walked.
* Duration.
* Additional map area uncovered.
* Landmarks visited, if determinable.

Gamification, achievements, and exploration challenges are not in scope for the initial implementation.

5. Existing Functionality and Non-Regression Requirements

The following are hard requirements.

Background location tracking

Fog of Walk already supports ongoing exploration tracking while the phone is locked or the app is in the background.

This behavior must remain unchanged.

Navigation must not require the application to remain open or the screen to stay on for existing exploration tracking to work.

Spoken directions and lock-screen navigation notifications are optional P1/P2 enhancements.

Offline functionality

The application already has offline capabilities.

All existing offline functionality must continue working.

In particular:

* Offline exploration tracking must continue.
* Exploration progress must remain properly recorded.
* Existing offline map behavior must not regress.
* Previously loaded routes should remain available when connectivity is lost, where technically feasible.
* New route generation may require connectivity initially.

Full offline route calculation and downloadable offline routing data are potential future features.

Performance and battery

Navigation should not introduce unnecessary polling, battery drain, or duplicated location services.

Prefer reusing existing location tracking infrastructure.

Data integrity

Navigation and route previews must not modify historical exploration data incorrectly.

Existing exploration records should remain compatible.

6. Proposed Prioritization

The following is an initial product recommendation, not a mandatory development sequence.

Engineering should adjust priorities after assessing architectural dependencies, implementation cost, and user value.

Priority	Capability
P0	Directional indicator and recenter control
P0	Reliable map following and manual pan behavior
P0	Preservation of background tracking and offline functionality
P0	Destination search and existing saved-place entry points
P0	Exploration-aware route generation and visual comparison
P0	Basic in-app navigation and route progress
P0	Correct fog behavior during navigation
P0	Dedicated Explore Mode with unexplored-area highlighting
P0/P1	Directional exploration suggestions
P0/P1	Generated round-trip and one-way exploration walks
P0/P1	Landmark-aware suggestions using existing datasets
P1	Heading-up map rotation
P1	Custom starting location
P1	Post-walk exploration summary
P1	Previously visited landmarks as optional suggestions
P1	External map integration, where selected routes can be preserved
P1/P2	Spoken instructions and lock-screen navigation alerts
Later	Adjustable exploration detour sliders
Later	Custom exploration preferences and additional POI sources
Later	Full offline navigation and route calculation
Later	Multi-stop itinerary planning
Later	Cycling and driving modes
Later	Gamification and advanced exploration statistics

7. Key User Journeys

Journey A: Exploring an unfamiliar city

1. The user opens Fog of Walk while walking.
2. The map shows their current location and facing direction.
3. They pan the map to examine a nearby neighborhood.
4. They tap the recenter button to return to their current location.
5. They activate Explore Mode.
6. The map highlights nearby unexplored streets.
7. They view a few suggested directions.
8. They select a promising suggestion and continue walking.
9. The fog clears normally as they physically explore.

Success: The user can quickly determine where to walk next without repeatedly stopping to examine the map.

Journey B: Navigating to a destination while exploring

1. The user searches for a café 12 minutes away.
2. Fog of Walk calculates meaningful alternatives.
3. It might offer a 12-minute fastest route, a 15-minute balanced route, and an 18-minute exploration route.
4. The user compares them visually, including unexplored sections and estimated new territory.
5. They select Balanced.
6. The selected route appears on the map with navigation guidance.
7. As they walk, the app tracks their progress and clears fog.
8. If they deviate substantially, the app offers recalculation.
9. They reach the café and navigation concludes.

Success: The user can deliberately trade modest additional walking time for meaningful new exploration.

Journey C: Exploring with limited time

1. The user has 30 minutes available.
2. They open Explore Mode.
3. They select a 30-minute round-trip walk.
4. Fog of Walk generates a walk emphasizing unexplored territory and reasonable pedestrian routes.
5. If landmark-aware exploration is enabled, the route may pass an unvisited landmark.
6. They follow the route and return close to their starting point.

Success: The user discovers an interesting part of a city without needing to research or plan a route.

8. Success Criteria

The primary goal is improved usefulness while walking, rather than simply increased feature usage.

Suggested indicators:

Usability

* Users can immediately identify their approximate direction.
* Recenter behavior is obvious and reliable.
* Navigation requires minimal interaction once started.

Exploration

* Users can easily identify nearby unexplored areas.
* Alternative routes offer measurably different exploration opportunities when they are presented.
* Route estimates are useful enough to guide decisions.

Navigation quality

* Suggested routes are practical and pedestrian-friendly.
* Routes do not introduce unreasonable detours.
* Users can follow selected routes without excessive manual map manipulation.

Reliability

* No regression in background tracking or offline exploration.
* No corruption or unintended changes to exploration history.
* No unacceptable increase in battery consumption.

Engineering and product should determine which metrics can be measured with existing telemetry and whether additional instrumentation is warranted.

9. Non-Goals

This initiative is not intended to:

* Replace Apple Maps or Google Maps for general navigation.
* Support every transportation mode.
* Build a comprehensive new points-of-interest database.
* Create a travel-booking or itinerary-management platform.
* Guarantee optimal routes for every city or street network.
* Introduce complex gamification.
* Require full offline navigation from the first release.

These capabilities should not distract from the central objective of making walking exploration easier and more enjoyable.

10. Engineering Review and Decision Authority

The engineering team is explicitly encouraged to challenge and modify any aspect of this brief.

This includes proposed behavior, design, feature boundaries, priorities, sequencing, architectural approach, algorithms, and integrations.

Before implementation, engineering should:

1. Review the existing codebase. Identify relevant map, GPS, background tracking, fog, navigation, saved-place, and landmark capabilities.
2. Identify reusable infrastructure. Determine whether existing routing frameworks, map providers, or platform APIs can significantly reduce effort.
3. Evaluate routing feasibility. Recommend how to generate routes that account for walking quality and unexplored territory without disproportionate computational expense.
4. Evaluate navigation feasibility. Determine which in-app navigation capabilities can be implemented relatively easily and which require substantial additional infrastructure.
5. Assess data availability. Identify limitations in pedestrian routes, landmark datasets, visited-place inference, and fog-coverage estimation.
6. Propose implementation milestones. Favor incremental delivery of independently useful functionality.
7. Identify risks and tradeoffs. Particularly around battery usage, heading accuracy, map rendering, offline behavior, and route quality.
8. Recommend alternative designs wherever a simpler approach would accomplish the same user goal.

Priority classifications in this document are recommendations, not contractual requirements.

The main exceptions are the fundamental product principles and non-regression requirements: existing exploration behavior, background tracking, offline capabilities, and data integrity must be preserved.

11. Suggested Delivery Strategy

Engineering should determine the final phases, but an incremental strategy is preferred.

Milestone 1 — Map Usability

Ship directional awareness, recentering, and improved map-following behavior.

This solves the immediate orientation problems independently of routing.

Milestone 2 — Exploration-Aware Destination Routing

Enable destination search, route alternatives, map comparison, and exploration estimates.

Milestone 3 — Active Navigation

Provide basic guidance, progress tracking, and practical route deviation handling.

Milestones 2 and 3 can be combined if the architecture supports it.

Milestone 4 — Explore Mode

Add unexplored-area highlighting, directional suggestions, and integration with existing landmarks.

Milestone 5 — Generated Walks and Enhancements

Introduce timed exploration walks, deeper landmark-aware routing, navigation improvements, and post-walk summaries.

The order should change if implementation dependencies or engineering findings suggest a better approach.

12. Final Product Vision

Fog of Walk should evolve from an application that records where users have explored into one that actively helps them decide where to explore next.

When walking through an unfamiliar city, users should be able to answer three questions effortlessly:

* Where am I, and which direction am I facing?
* How can I get to my destination while discovering interesting new territory?
* If I have nowhere particular to go, where should I walk next?

The best implementation is the one that answers these questions reliably, intuitively, and with minimal distraction, while preserving everything users already value about Fog of Walk.

Engineering is empowered to choose the simplest and most maintainable path to that outcome.
