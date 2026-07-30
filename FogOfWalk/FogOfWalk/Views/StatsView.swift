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
                gridSettings.highlightToday.toggle()
            } label: {
                Text("\(store.todayVisitedCount) new today")
                    .font(.headline)
                    .foregroundStyle(gridSettings.highlightToday ? Color.yellow : Color.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(gridSettings.highlightToday
                ? "Highlighting today's areas. Tap to turn off."
                : "\(store.todayVisitedCount) new today. Tap to highlight today's areas.")

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
}
