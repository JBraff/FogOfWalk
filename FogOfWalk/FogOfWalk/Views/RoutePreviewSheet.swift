import SwiftUI
import MapKit

struct RoutePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ExplorationStore.self) private var store
    @Bindable var model: RoutePreviewModel
    var origin: () -> CLLocationCoordinate2D?
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                if model.isLoading {
                    HStack { ProgressView(); Text("Finding places and walking routes…") }
                }
                if let message = model.message {
                    Section {
                        Text(message)
                        if let target = model.destination, model.routes.isEmpty {
                            Button("Try routes again") { load(target) }
                        }
                    }
                }
                if !model.destinations.isEmpty {
                    Section("Choose a destination") {
                        ForEach(Array(model.destinations.enumerated()), id: \.element.id) { index, target in
                            RouteDestinationButton(target: target) { load(target) }
                                .accessibilityIdentifier("route-destination-\(index)")
                        }
                    }
                }
                if !model.routes.isEmpty {
                    Section {
                        ForEach(Array(model.routes.enumerated()), id: \.element.id) { index, route in
                            Button { model.select(route) } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: model.selectedRouteID == route.id
                                          ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(index == 0 ? "Fastest returned" : "Alternative \(index)")
                                            .font(.headline)
                                        Text("\(Self.minutes(route.travelTime)) min · \(Self.distance(route.distance))")
                                        if let count = route.newCellCount(visited: store.visitedCellsCache) {
                                            Text("≈ \(count) new cells").fontWeight(.semibold)
                                        } else {
                                            Text("Discovery estimate unavailable").font(.caption)
                                        }
                                        if !route.name.isEmpty { Text(route.name).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    .foregroundStyle(.primary)
                                }
                            }
                            .accessibilityIdentifier("route-option-\(index)")
                            .accessibilityValue(model.selectedRouteID == route.id ? "Selected" : "Not selected")
                        }
                    } header: {
                        Text("Walk to \(model.destination?.name ?? "destination")")
                    } footer: {
                        Text(model.routes.count == 1
                            ? "Apple Maps returned one walking route. New cells are estimates; only walking records exploration."
                            : "Tap a route to highlight it on the map. New cells are estimates; only walking records exploration.")
                    }
                } else if !model.isLoading && model.message == nil && model.destinations.isEmpty {
                    Text("Search a place or address to compare walking routes. Apple Maps search requires internet; your explored cells stay on this device.")
                        .foregroundStyle(.secondary)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Place or address")
            .searchFocused($searchFocused)
            .onSubmit(of: .search, search)
            .navigationTitle("Compare routes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .cancellationAction) {
                    if !model.routes.isEmpty {
                        Button("Clear routes", role: .destructive) { model.clear() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private func search() {
        let submittedQuery = query
        searchFocused = false
        model.search(submittedQuery, near: origin())
    }
    private func load(_ target: RouteDestination) {
        searchFocused = false
        model.loadRoutes(to: target, from: origin())
    }
    static func minutes(_ seconds: TimeInterval) -> Int { max(1, Int(ceil(seconds / 60))) }
    static func distance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

/// Reads dismissSearch from inside the searchable hierarchy, so selecting a result
/// restores the route toolbar as well as dismissing the keyboard.
private struct RouteDestinationButton: View {
    @Environment(\.dismissSearch) private var dismissSearch
    let target: RouteDestination
    let choose: () -> Void
    var body: some View {
        Button {
            dismissSearch()
            choose()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(target.name).foregroundStyle(.primary)
                Text(Self.address(for: target.item)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private static func address(for item: MKMapItem) -> String {
        if #available(iOS 26.0, *) { return item.address?.fullAddress ?? "" }
        return item.placemark.title ?? ""
    }
}
