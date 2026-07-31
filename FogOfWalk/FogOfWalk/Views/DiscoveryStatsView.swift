import Charts
import CoreData
import MapKit
import SwiftUI

struct DiscoveryStatsView: View {
    @Environment(ExplorationStore.self)  private var store
    @Environment(LandmarkStore.self)     private var landmarkStore
    @Environment(\.dismiss)              private var dismiss

    var onNavigate: ((MapNavigationTarget) -> Void)?

    @State private var model = DiscoveryStatsModel()
    @State private var localityPeriod: LocalityPeriod = .thisWeek

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    summaryCards
                    weeklyChart
                    localitySection
                    statesSection
                    countriesSection
                    allTimeSection
                    landmarksSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .navigationTitle("Discovery Stats")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                model.refresh(context: store.viewContext)
            }
        }
    }

    // MARK: - Summary cards

    private var summaryCards: some View {
        HStack(spacing: 12) {
            StatCard(title: "Today", count: model.last24HourCount)
            StatCard(title: "This Week", count: model.last7DaysByDay.reduce(0) { $0 + $1.count })
        }
    }

    // MARK: - 7-day bar chart

    private var weeklyChart: some View {
        GroupBox {
            Chart(model.last7DaysByDay) { entry in
                BarMark(
                    x: .value("Day", entry.date, unit: .day),
                    y: .value("Areas", entry.count)
                )
                .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("Bar chart showing areas explored each day for the past 7 days")
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 180)
        } label: {
            Text("Daily Discoveries — Past 7 Days")
                .font(.headline)
        }
    }

    // MARK: - By location

    private var localitySection: some View {
        let data = model.locality(for: localityPeriod)
        return GroupBox {
            if data.isEmpty {
                Text("No areas explored \(localityPeriod.emptyStateLabel).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(data) { stat in
                        LocalityRow(
                            stat: stat,
                            maxCount: data.first?.count ?? 1,
                            action: onNavigate.map { navigate in {
                                navigate(MapNavigationTarget(center: stat.center, span: stat.span))
                                dismiss()
                            }}
                        )
                        if stat.id != data.last?.id {
                            Divider()
                        }
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("By Location")
                    .font(.headline)
                Picker("Period", selection: $localityPeriod) {
                    ForEach(LocalityPeriod.allCases) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - States

    private var statesSection: some View {
        LocalityListSection(title: "States", emptyText: "No states explored yet.",
                             data: model.stateStats, onNavigate: onNavigate, dismiss: { dismiss() })
    }

    // MARK: - Countries

    private var countriesSection: some View {
        LocalityListSection(title: "Countries", emptyText: "No countries explored yet.",
                             data: model.countryStats, onNavigate: onNavigate, dismiss: { dismiss() })
    }

    // MARK: - All time

    private var allTimeSection: some View {
        GroupBox {
            VStack(spacing: 8) {
                LabeledContent("Total areas", value: "\(model.allTimeTotal)")
                if let first = model.firstWalkDate {
                    LabeledContent(
                        "First walk",
                        value: first.formatted(date: .abbreviated, time: .omitted)
                    )
                }
                if let best = model.bestDayDate, model.bestDayCount > 0 {
                    LabeledContent(
                        "Best day",
                        value: "\(model.bestDayCount) areas on \(best.formatted(date: .abbreviated, time: .omitted))"
                    )
                }
                if model.totalDaysActive > 0 {
                    LabeledContent("Days active", value: "\(model.totalDaysActive)")
                }
                if model.currentStreak > 0 {
                    LabeledContent("Current streak", value: "\(model.currentStreak) \(model.currentStreak == 1 ? "day" : "days")")
                }
                if model.longestStreak > 0 {
                    LabeledContent("Longest streak", value: "\(model.longestStreak) \(model.longestStreak == 1 ? "day" : "days")")
                }
                if model.estimatedDistanceMeters > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        LabeledContent(
                            "Est. distance",
                            value: String(format: "%.1f km", model.estimatedDistanceMeters / 1000)
                        )
                        Text("Based on grid cell coverage")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        } label: {
            Text("All Time")
                .font(.headline)
        }
    }

    // MARK: - Famous Locations

    private var landmarksSection: some View {
        let discovered = landmarkStore.allLandmarks.filter { $0.isDiscovered }
            .sorted { ($0.firstDiscovered ?? .distantPast) > ($1.firstDiscovered ?? .distantPast) }
        let total = landmarkStore.allLandmarks.count

        return GroupBox {
            if total == 0 {
                Text("Walk around to discover famous nearby locations!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Discovered", value: "\(discovered.count) of \(total)")
                    if !discovered.isEmpty {
                        Divider()
                        ForEach(discovered.prefix(5), id: \.identifier) { landmark in
                            Button {
                                let target = MapNavigationTarget(
                                    center: CLLocationCoordinate2D(latitude: landmark.latitude,
                                                                   longitude: landmark.longitude),
                                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                                )
                                onNavigate?(target)
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: LandmarkOverlayView.categoryIcon[landmark.category] ?? "mappin.fill")
                                        .foregroundStyle(.blue)
                                        .frame(width: 20)
                                    Text(landmark.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    HStack(spacing: 4) {
                                        if let date = landmark.firstDiscovered {
                                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if onNavigate != nil {
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(onNavigate == nil)
                        }
                    }
                }
            }
        } label: {
            Label("Famous Locations", systemImage: "star.fill")
                .font(.headline)
        }
    }

}

// MARK: - StatCard

private struct StatCard: View {
    let title: String
    let count: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text(count == 1 ? "area" : "areas")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - LocalityRow

private struct LocalityRow: View {
    let stat: LocalityStats
    let maxCount: Int
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            Text(stat.name)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            GeometryReader { geo in
                let fraction = maxCount > 0 ? CGFloat(stat.count) / CGFloat(maxCount) : 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: geo.size.width, height: 8)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * fraction, height: 8)
                }
            }
            .frame(width: 80, height: 8)

            Text("\(stat.count)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 32, alignment: .trailing)

            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - LocalityListSection

private struct LocalityListSection: View {
    let title: String
    let emptyText: String
    let data: [LocalityStats]
    var onNavigate: ((MapNavigationTarget) -> Void)?
    var dismiss: () -> Void

    var body: some View {
        GroupBox {
            if data.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(data) { stat in
                        LocalityRow(
                            stat: stat,
                            maxCount: data.first?.count ?? 1,
                            action: onNavigate.map { navigate in {
                                navigate(MapNavigationTarget(center: stat.center, span: stat.span))
                                dismiss()
                            }}
                        )
                        if stat.id != data.last?.id {
                            Divider()
                        }
                    }
                }
            }
        } label: {
            Text(title)
                .font(.headline)
        }
    }
}
