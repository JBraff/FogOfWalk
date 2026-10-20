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
    /// The prompt the user dismissed. A different prompt (e.g. permission later revoked)
    /// still shows.
    @State private var dismissedPermissionPrompt: LocationService.PermissionPrompt?
    @State private var showSettings = false

    private var visiblePermissionPrompt: LocationService.PermissionPrompt? {
        guard let prompt = locationService.permissionPrompt,
              prompt != dismissedPermissionPrompt else { return nil }
        return prompt
    }

    private var showRecoveryAlert: Binding<Bool> {
        Binding(get: { store.recoveryNotice != nil },
                set: { if !$0 { store.acknowledgeRecoveryNotice() } })
    }

    private var recoveryMessage: String {
        guard let notice = store.recoveryNotice else { return "" }
        if !notice.storeIsUsable {
            return "Fog of Walk couldn\u{2019}t open its storage, so new exploration won\u{2019}t be saved. Try restarting the app."
        }
        return notice.backupURLs.isEmpty
            ? "Fog of Walk couldn\u{2019}t read your saved exploration history and started a new one."
            : "Fog of Walk couldn\u{2019}t read your saved exploration history and started a new one. A copy of the old data was kept on this device."
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            MapContainerView(
                onLandmarkTapped: { id in
                    selectedLandmark = landmarkStore.allLandmarks.first(where: { $0.identifier == id })
                },
                navigateTo: mapTarget,
                highlightGeneration: store.recentCellsGeneration,
                visitedCellCount: store.visitedCellsCache.count
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if let prompt = visiblePermissionPrompt {
                    LocationPermissionBanner(prompt: prompt) {
                        dismissedPermissionPrompt = prompt
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                StatsView(showStats: $showStats, showSettings: $showSettings)
                    .padding(.bottom, 8)
            }
            .animation(.easeInOut, value: visiblePermissionPrompt)
        }
        .alert(store.recoveryNotice?.storeIsUsable == true
               ? "Exploration History Reset" : "Exploration Storage Unavailable",
               isPresented: showRecoveryAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recoveryMessage)
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
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
