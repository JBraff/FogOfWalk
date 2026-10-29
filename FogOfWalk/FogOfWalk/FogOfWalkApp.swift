import SwiftUI

@main
struct FogOfWalkApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store:          ExplorationStore
    @State private var gridSettings:    GridSettings
    @State private var locationService: LocationService
    @State private var geocoder:        LocalityGeocoder
    @State private var landmarkStore:  LandmarkStore
    @State private var searchService:  LandmarkSearchService

    init() {
        let g = GridSettings()
        let s = ExplorationStore()
        s.configure()
        let landmarks = LandmarkStore(container: s.container)
        let location = LocationService()
        let geocoder = LocalityGeocoder()
        let landmarkSource = LandmarkSearchService.bundledSource()
        // Recording is owned by the app, not the map: when iOS relaunches the app in the
        // background (significant-location change) it may not create a scene, so neither
        // the map nor any view `.task` runs. Wire recording and re-arm tracking here.
        ExplorationRecorder.connect(location: location, store: s, landmarks: landmarks,
                                    geocoder: geocoder, landmarkSource: landmarkSource)
        location.restartIfAuthorized(reason: .launch)
        _locationService = State(initialValue: location)
        _store         = State(initialValue: s)
        _gridSettings  = State(initialValue: g)
        _geocoder      = State(initialValue: geocoder)
        _landmarkStore = State(initialValue: landmarks)
        _searchService = State(initialValue: LandmarkSearchService(source: landmarkSource))
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-landmark-interaction-fixture") {
                LandmarkInteractionFixture()
            } else {
                appContent
            }
            #else
            appContent
            #endif
        }
    }

    private var appContent: some View {
        ContentView()
            .environment(store)
            .environment(gridSettings)
            .environment(locationService)
            .environment(geocoder)
            .environment(landmarkStore)
            .environment(searchService)
            .task {
                // Requests permission if needed. Already-authorized tracking was
                // re-armed in `init`, which also runs for scene-less background launches.
                locationService.requestPermissionAndStart()
                locationService.recordStudyTrackingState()

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
                LocationStudyDiagnostics.shared.recordLifecycle(
                    "scene_phase", detail: "\(newPhase)"
                )
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
