import MapKit
import Observation

struct RouteDestination: Identifiable {
    let id = UUID()
    let item: MKMapItem
    var name: String { item.name ?? "Destination" }
}

struct DiscoveryRoute: Identifiable {
    let id = UUID()
    let name: String
    let distance: CLLocationDistance
    let travelTime: TimeInterval
    let polyline: MKPolyline
    let cells: Set<CellID>?

    init(name: String, distance: CLLocationDistance, travelTime: TimeInterval, polyline: MKPolyline) {
        self.name = name
        self.distance = distance
        self.travelTime = travelTime
        self.polyline = polyline
        var coordinates = [CLLocationCoordinate2D](repeating: .init(), count: polyline.pointCount)
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: coordinates.count))
        cells = RouteCellEstimator.cells(along: coordinates)
    }

    func newCellCount(visited: Set<CellID>) -> Int? { cells.map { $0.subtracting(visited).count } }
}

@MainActor
protocol RoutePreviewClient {
    func search(_ query: String, near: CLLocationCoordinate2D?) async throws -> [RouteDestination]
    func routes(from: CLLocationCoordinate2D, to: RouteDestination) async throws -> [DiscoveryRoute]
    func cancel()
}

@MainActor
final class AppleRoutePreviewClient: RoutePreviewClient {
    private var search: MKLocalSearch?
    private var directions: MKDirections?

    func cancel() {
        search?.cancel(); search = nil
        directions?.cancel(); directions = nil
    }

    func search(_ query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [RouteDestination] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let coordinate {
            request.region = MKCoordinateRegion(center: coordinate,
                latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        }
        let operation = MKLocalSearch(request: request)
        search = operation
        let response = try await operation.start()
        return response.mapItems.prefix(10).map { RouteDestination(item: $0) }
    }

    func routes(from source: CLLocationCoordinate2D, to destination: RouteDestination) async throws -> [DiscoveryRoute] {
        let request = MKDirections.Request()
        if #available(iOS 26.0, *) {
            request.source = MKMapItem(location: CLLocation(latitude: source.latitude, longitude: source.longitude), address: nil)
        } else {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        }
        request.destination = destination.item
        request.transportType = .walking
        request.requestsAlternateRoutes = true
        let operation = MKDirections(request: request)
        directions = operation
        let response = try await operation.calculate()
        return response.routes.filter {
            $0.transportType == .walking && $0.distance.isFinite && $0.distance >= 0
                && $0.expectedTravelTime.isFinite && $0.expectedTravelTime >= 0
                && $0.polyline.pointCount > 1 && $0.polyline.pointCount <= 50_000
        }.prefix(5).map {
            DiscoveryRoute(name: $0.name, distance: $0.distance,
                travelTime: $0.expectedTravelTime, polyline: $0.polyline)
        }.sorted { $0.travelTime < $1.travelTime }
    }
}

/// UI-owned, in-memory preview. No persisted state or location streams.
@MainActor @Observable
final class RoutePreviewModel {
    private(set) var destinations: [RouteDestination] = []
    private(set) var destination: RouteDestination?
    private(set) var routes: [DiscoveryRoute] = []
    private(set) var selectedRouteID: UUID?
    private(set) var isLoading = false
    private(set) var message: String?
    private let client: RoutePreviewClient
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(client: RoutePreviewClient? = nil) { self.client = client ?? AppleRoutePreviewClient() }
    var selectedRoute: DiscoveryRoute? { routes.first { $0.id == selectedRouteID } }

    static func usableOrigin(_ location: CLLocation?, now: Date = Date()) -> CLLocationCoordinate2D? {
        guard let location, CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy.isFinite, location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 100,
              (0...60).contains(now.timeIntervalSince(location.timestamp)) else { return nil }
        return location.coordinate
    }

    func search(_ text: String, near origin: CLLocationCoordinate2D?) {
        cancelPending()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        destinations = []; message = nil
        guard !query.isEmpty else { return }
        isLoading = true
        let token = generation
        task = Task { [weak self] in
            guard let self, self.generation == token, !Task.isCancelled else { return }
            do {
                let results = try await client.search(query, near: origin)
                guard generation == token, !Task.isCancelled else { return }
                destinations = results
                if results.isEmpty { message = "No places found. Try a place name or address." }
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                message = "Search unavailable. Check your connection and try again."
            }
            if generation == token { isLoading = false }
        }
    }

    func loadRoutes(to target: RouteDestination, from origin: CLLocationCoordinate2D?) {
        cancelPending()
        destinations = []; routes = []; selectedRouteID = nil
        destination = target; message = nil
        guard let origin else {
            message = "Waiting for a recent, accurate location. Try again when your location is available."
            return
        }
        isLoading = true
        let token = generation
        task = Task { [weak self] in
            guard let self, self.generation == token, !Task.isCancelled else { return }
            do {
                let results = try await client.routes(from: origin, to: target)
                guard generation == token, !Task.isCancelled else { return }
                routes = results
                selectedRouteID = results.first?.id
                if results.isEmpty { message = "No walking route found. Try another destination." }
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                message = "Routes unavailable. Check your connection and try again."
            }
            if generation == token { isLoading = false }
        }
    }

    func select(_ route: DiscoveryRoute) {
        guard routes.contains(where: { $0.id == route.id }) else { return }
        selectedRouteID = route.id
    }

    func cancelPending() {
        generation = UUID()
        task?.cancel(); task = nil
        client.cancel()
        isLoading = false
    }

    func clear() {
        cancelPending()
        destinations = []; routes = []; destination = nil; selectedRouteID = nil; message = nil
    }
}
