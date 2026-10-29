import SwiftUI

@main
struct FogOfWalkApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var services: AppServices?

    init() {
        _services = State(initialValue: Self.servicesForLaunch(
            arguments: ProcessInfo.processInfo.arguments, make: { AppServices() }))
    }

    /// The fixture gate precedes every production service, store open and recording hook.
    static func servicesForLaunch<T>(arguments: [String], make: @MainActor () -> T) -> T? {
        #if DEBUG
        if LandmarkInteractionFixture.isRequested(arguments: arguments) { return nil }
        #endif
        return make()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if services == nil {
                LandmarkInteractionFixture()
            } else {
                appContent
            }
            #else
            appContent
            #endif
        }
    }

    @ViewBuilder
    private var appContent: some View {
        if let services {
            ContentView()
                .environment(services.store)
                .environment(services.gridSettings)
                .environment(services.locationService)
                .environment(services.geocoder)
                .environment(services.landmarkStore)
                .environment(services.searchService)
                .task {
                    // Requests permission if needed. Already-authorized tracking was
                    // re-armed in `init`, which also runs for scene-less background launches.
                    services.locationService.requestPermissionAndStart()
                    services.locationService.recordStudyTrackingState()

                    // Backfill any existing cells that don't have a locality yet.
                    services.geocoder.geocodeUntaggedCells(context: services.store.viewContext)

                    // Self-heal any discovery the per-cell path can't reach: a landmark whose
                    // discovery save was rolled back, or one that a since-fixed bug filtered
                    // out. Its cell will never be "new" again, so without this sweep the
                    // discovery would be lost permanently. `services.store.configure()` ran in `init`,
                    // so `visitedCellsCache` is populated.
                    //
                    // The result is deliberately discarded — no haptic. This can surface a
                    // batch of retroactive discoveries on the first launch after a fix, and a
                    // success buzz for landmarks the user visited weeks ago would be noise.
                    services.landmarkStore.sweepAllUndiscovered(visitedCells: services.store.visitedCellsCache)
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
                        services.locationService.restartIfAuthorized()
                        // Catches a day rollover that happened while backgrounded, before
                        // any location update arrives, so the HUD is correct on first frame.
                        services.store.refreshForDayChangeIfNeeded()
                    }
                }
        }
    }
}

/// Constructed at app launch (including scene-less background launches) only for the
/// production UI. The fixture creates its own in-memory store and never builds this.
private struct AppServices {
    let store: ExplorationStore
    let gridSettings: GridSettings
    let locationService: LocationService
    let geocoder: LocalityGeocoder
    let landmarkStore: LandmarkStore
    let searchService: LandmarkSearchService

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
        locationService = location
        store = s
        gridSettings = g
        self.geocoder = geocoder
        landmarkStore = landmarks
        searchService = LandmarkSearchService(source: landmarkSource)
    }
}
