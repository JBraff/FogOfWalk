import SwiftUI

@main
struct FogOfWalkApp: App {
    @State private var store:          ExplorationStore
    @State private var gridSettings:    GridSettings
    @State private var locationService = LocationService()
    @State private var geocoder        = LocalityGeocoder()
    @State private var landmarkStore:  LandmarkStore
    @State private var searchService:  LandmarkSearchService

    init() {
        let g = GridSettings()
        let s = ExplorationStore()
        s.configure(cellSizeMeters: g.cellSizeMeters)
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
                    geocoder.geocodeUntaggedCells(
                        context: store.viewContext,
                        cellSizeMeters: gridSettings.cellSizeMeters
                    )
                }
        }
    }
}
