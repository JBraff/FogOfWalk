import SwiftUI

@main
struct FogOfWalkApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store:          ExplorationStore
    @State private var gridSettings:    GridSettings
    @State private var locationService = LocationService()
    @State private var geocoder        = LocalityGeocoder()
    @State private var landmarkStore:  LandmarkStore
    @State private var searchService:  LandmarkSearchService

    init() {
        let g = GridSettings()
        let s = ExplorationStore()
        s.configure()
        _store         = State(initialValue: s)
        _gridSettings  = State(initialValue: g)
        _landmarkStore = State(initialValue: LandmarkStore(container: s.container))
        _searchService = State(initialValue: LandmarkSearchService.makeBundled())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(gridSettings)
                .environment(locationService)
                .environment(geocoder)
                .environment(landmarkStore)
                .environment(searchService)
                .task {
                    // Start location tracking as early as possible so background
                    // relaunches (e.g. via significant-location-change) begin tracking
                    // before the map view ever appears.
                    locationService.requestPermissionAndStart()

                    // Wire new-cell callback so locality is geocoded as cells are discovered.
                    store.onNewCell = { [geocoder] cell in
                        geocoder.enqueue(cell)
                    }
                    // Backfill any existing cells that don't have a locality yet.
                    geocoder.geocodeUntaggedCells(context: store.viewContext)

                    // Self-heal any discovery the per-cell path can't reach: a landmark whose
                    // discovery save was rolled back, or one that a since-fixed bug filtered
                    // out. Its cell will never be "new" again, so without this sweep the
                    // discovery would be lost permanently. `store.configure()` ran in `init`,
                    // so `visitedCellsCache` is populated.
                    //
                    // The result is deliberately discarded — no haptic. This can surface a
                    // batch of retroactive discoveries on the first launch after a fix, and a
                    // success buzz for landmarks the user visited weeks ago would be noise.
                    landmarkStore.sweepAllUndiscovered(visitedCells: store.visitedCellsCache)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // Safety net: re-arm tracking whenever the app returns to the
                    // foreground, in case location updates silently stopped while
                    // backgrounded. `.task` above only fires once per process launch,
                    // so it won't catch this on a warm foreground.
                    if newPhase == .active {
                        locationService.restartIfAuthorized()
                        // Catches a day rollover that happened while backgrounded, before
                        // any location update arrives, so the HUD is correct on first frame.
                        store.refreshForDayChangeIfNeeded()
                    }
                }
        }
    }
}
