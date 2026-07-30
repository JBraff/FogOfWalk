import MapKit
import SwiftUI
import UIKit

struct MapNavigationTarget {
    let id = UUID()
    let center: CLLocationCoordinate2D
    let span: MKCoordinateSpan
}

struct ContentView: View {
    @Environment(ExplorationStore.self)   private var store
    @Environment(GridSettings.self)       private var gridSettings
    @Environment(LandmarkStore.self)      private var landmarkStore
    @Environment(LocationService.self)    private var locationService
    @State private var showStats          = false
    @State private var selectedLandmark: Landmark?
    @State private var mapTarget: MapNavigationTarget?
    @State private var upgradeBannerDismissed = false

    private var showUpgradeBanner: Bool {
        locationService.needsAlwaysUpgrade && !upgradeBannerDismissed
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            MapContainerView(
                onLandmarkTapped: { id in
                    selectedLandmark = landmarkStore.allLandmarks.first(where: { $0.identifier == id })
                },
                navigateTo: mapTarget,
                highlightGeneration: store.recentCellsGeneration
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if showUpgradeBanner {
                    AlwaysLocationBanner {
                        upgradeBannerDismissed = true
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                StatsView(showStats: $showStats)
                    .padding(.bottom, 8)
            }
            .animation(.easeInOut, value: showUpgradeBanner)
        }
        .sheet(isPresented: $showStats) {
            DiscoveryStatsView(onNavigate: { target in
                mapTarget = target
                showStats = false
            })
        }
        .sheet(item: $selectedLandmark) { landmark in
            LandmarkDetailView(landmark: landmark)
        }
        .onAppear {
            store.configure()
            store.loadRecentCells(since: gridSettings.highlightCutoffDate)
        }
        .onChange(of: gridSettings.highlightToday) { _, newValue in
            let cutoff = newValue ? Calendar.current.startOfDay(for: Date()) : nil
            store.loadRecentCells(since: cutoff)
        }
        // Best-effort day-rollover triggers for a user actively watching the app as
        // midnight passes. Each loop never returns, so each needs its own .task —
        // putting them in FogOfWalkApp's setup .task would strand that task's real
        // work behind an infinite loop.
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                store.refreshForDayChangeIfNeeded()
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(
                named: UIApplication.significantTimeChangeNotification
            ) {
                store.refreshForDayChangeIfNeeded()
            }
        }
    }
}
