import SwiftUI

struct StatsView: View {
    @Environment(ExplorationStore.self)  private var store
    @Environment(LandmarkStore.self)     private var landmarkStore
    @Environment(LocationService.self)   private var locationService
    @Binding var showSettings: Bool
    @Binding var showStats: Bool

    var body: some View {
        HStack(spacing: 16) {
            Text("\(store.todayVisitedCount) new today")
                .font(.headline)

            if landmarkStore.totalDiscovered > 0 {
                Label("\(landmarkStore.totalDiscovered)", systemImage: "star.fill")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)
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
                Image(systemName: "slider.horizontal.3")
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
