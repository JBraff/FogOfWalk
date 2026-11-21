import SwiftUI

struct StatsView: View {
    @Environment(ExplorationStore.self)  private var store
    @Environment(LandmarkStore.self)     private var landmarkStore
    @Environment(LocationService.self)   private var locationService
    @Environment(GridSettings.self)      private var gridSettings
    @Binding var showStats: Bool
    @Binding var showSettings: Bool

    var body: some View {
        HStack(spacing: 16) {
            Button {
                gridSettings.todayHighlight = gridSettings.todayHighlight.next
            } label: {
                Text(todayText)
                    .font(.headline)
                    .foregroundStyle(gridSettings.todayHighlight == .off ? Color.primary : highlightColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todayAccessibilityLabel)

            if landmarkStore.totalDiscovered > 0 {
                Button {
                    gridSettings.showLandmarks.toggle()
                } label: {
                    Label("\(landmarkStore.totalDiscovered)",
                          systemImage: gridSettings.showLandmarks ? "star.fill" : "star")
                        .font(.subheadline)
                        .foregroundStyle(gridSettings.showLandmarks ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(gridSettings.showLandmarks
                    ? "Showing landmarks. Tap to hide."
                    : "\(landmarkStore.totalDiscovered) discovered. Tap to show landmarks on the map.")
            }

            Spacer()

            if locationService.isPaused {
                Label("Paused", systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button { showStats = true } label: {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2)
            }
            .accessibilityLabel("Discovery statistics")

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.title2)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    /// Matches the map: the trail colour for Trail, gold otherwise.
    private var highlightColor: Color {
        gridSettings.fogStyle == .trail ? Color(SoftFogRenderer.trailColor) : Color.yellow
    }

    private var todayText: String {
        gridSettings.todayHighlight == .walkedToday
            ? "\(store.walkedTodayCount) walked today"
            : "\(store.todayVisitedCount) new today"
    }

    private var todayAccessibilityLabel: String {
        switch gridSettings.todayHighlight {
        case .off:
            "\(store.todayVisitedCount) new today. Tap to highlight new areas."
        case .newToday:
            "Highlighting \(store.todayVisitedCount) new today. Tap to highlight every area walked today."
        case .walkedToday:
            "Highlighting \(store.walkedTodayCount) walked today. Tap to turn off."
        }
    }
}
