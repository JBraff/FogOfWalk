import MapKit
import SwiftUI

struct MapNavigationTarget {
    let id = UUID()
    let center: CLLocationCoordinate2D
    let span: MKCoordinateSpan
}

struct ContentView: View {
    @Environment(ExplorationStore.self)  private var store
    @Environment(GridSettings.self)      private var gridSettings
    @Environment(LandmarkStore.self)     private var landmarkStore
    @State private var showSettings      = false
    @State private var showStats         = false
    @State private var selectedLandmarkID: String?
    @State private var mapTarget: MapNavigationTarget?

    var body: some View {
        ZStack(alignment: .bottom) {
            MapContainerView(
                onLandmarkTapped: { id in selectedLandmarkID = id },
                navigateTo: mapTarget
            )
            .ignoresSafeArea()

            StatsView(showSettings: $showSettings, showStats: $showStats)
                .padding(.bottom, 8)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showStats) {
            DiscoveryStatsView(onNavigate: { target in
                mapTarget = target
                showStats = false
            })
        }
        .sheet(isPresented: Binding(
            get: { selectedLandmarkID != nil },
            set: { if !$0 { selectedLandmarkID = nil } }
        )) {
            if let id = selectedLandmarkID,
               let landmark = landmarkStore.allLandmarks.first(where: { $0.identifier == id }) {
                LandmarkDetailView(landmark: landmark)
            }
        }
        .onAppear {
            store.configure(cellSizeMeters: gridSettings.cellSizeMeters)
            store.loadRecentCells(since: gridSettings.highlightPeriod.cutoffDate)
        }
        .onChange(of: gridSettings.cellSizeMeters) { _, newSize in
            store.configure(cellSizeMeters: newSize)
            store.loadRecentCells(since: gridSettings.highlightPeriod.cutoffDate)
        }
        .onChange(of: gridSettings.highlightPeriod) { _, newPeriod in
            store.loadRecentCells(since: newPeriod.cutoffDate)
        }
    }
}
