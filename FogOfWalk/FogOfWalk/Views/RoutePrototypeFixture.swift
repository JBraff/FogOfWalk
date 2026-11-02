#if DEBUG
import SwiftUI
import MapKit
import CoreData

/// Offline public-coordinate demo. Launch gate skips all production stores and services.
struct RoutePrototypeFixture: View {
    static func isRequested(arguments: [String]) -> Bool { arguments.contains("-route-prototype-fixture") }
    @State private var model = RoutePreviewModel(client: DemoRouteClient())
    @State private var showRoutes = false
    private let store: ExplorationStore
    private let coordinator: MapContainerView.Coordinator

    init() {
        let container = NSPersistentContainer(name: "FogOfWalk")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in precondition(error == nil) }
        store = ExplorationStore(container: container)
        store.configure()
        // The short route is partly explored; the dogleg offers more new cells.
        for cell in DemoRouteClient.routes[0].cells!.sorted(by: { ($0.x, $0.y) < ($1.x, $1.y) }).prefix(12) {
            store.addCell(cell)
        }
        coordinator = MapContainerView.Coordinator(store: store, gridSettings: GridSettings(defaults: nil),
            landmarkStore: LandmarkStore(container: container, defaults: nil),
            searchService: LandmarkSearchService(source: EmptyLandmarkSource()))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RouteFixtureMap(coordinator: coordinator, routes: model.routes, selection: model.selectedRouteID)
                .ignoresSafeArea()
            HStack {
                Button("Compare routes") { showRoutes = true }
                if !model.routes.isEmpty { Button("Clear route preview") { model.clear() } }
            }
            .padding().background(.regularMaterial, in: Capsule()).padding(.bottom, 24)
        }
        .sheet(isPresented: $showRoutes, onDismiss: { model.cancelPending() }) {
            RoutePreviewSheet(model: model, origin: { DemoRouteClient.start }).environment(store)
        }
        .task { model.loadRoutes(to: DemoRouteClient.destination, from: DemoRouteClient.start) }
    }
}

private struct RouteFixtureMap: UIViewRepresentable {
    let coordinator: MapContainerView.Coordinator
    let routes: [DiscoveryRoute]
    let selection: UUID?
    func makeCoordinator() -> MapContainerView.Coordinator { coordinator }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = false
        map.addOverlay(FogOverlay(), level: .aboveLabels)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.updateRoutes(routes, selectedID: selection, mapView: map)
    }
}

private final class DemoRouteClient: RoutePreviewClient {
    static let start = CLLocationCoordinate2D(latitude: 40.7536, longitude: -73.9832)
    static var destination: RouteDestination {
        let item: MKMapItem
        if #available(iOS 26.0, *) {
            item = MKMapItem(location: CLLocation(latitude: 40.745, longitude: -73.99), address: nil)
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: 40.745, longitude: -73.99)))
        }
        item.name = "Demo destination"
        return RouteDestination(item: item)
    }
    static var routes: [DiscoveryRoute] {
        let end = CLLocationCoordinate2D(latitude: 40.745, longitude: -73.99)
        let direct = [start, end]
        let alternative = [start, CLLocationCoordinate2D(latitude: 40.7536, longitude: -73.997),
                           CLLocationCoordinate2D(latitude: 40.745, longitude: -73.997), end]
        return [DiscoveryRoute(name: "Direct walk", distance: 1200, travelTime: 960,
                    polyline: MKPolyline(coordinates: direct, count: direct.count)),
                DiscoveryRoute(name: "Discovery alternative", distance: 1800, travelTime: 1320,
                    polyline: MKPolyline(coordinates: alternative, count: alternative.count))]
    }
    func search(_ query: String, near: CLLocationCoordinate2D?) async throws -> [RouteDestination] { [Self.destination] }
    func routes(from: CLLocationCoordinate2D, to: RouteDestination) async throws -> [DiscoveryRoute] { Self.routes }
    func cancel() {}
}
#endif
