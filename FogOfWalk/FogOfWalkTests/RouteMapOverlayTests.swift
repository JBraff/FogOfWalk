import XCTest
import MapKit
@testable import FogOfWalk

@MainActor
final class RouteMapOverlayTests: XCTestCase {
    func testSelectionDrawsAboveFogClearsOnlyRoutesAndDoesNotRefitOnUnrelatedUpdates() {
        let coordinator = makeLandmarkCoordinator()
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        map.delegate = coordinator
        let fog = FogOverlay()
        map.addOverlay(fog, level: .aboveLabels)
        let points = [CLLocationCoordinate2D(latitude: 40, longitude: -74), .init(latitude: 40.001, longitude: -74)]
        let first = DiscoveryRoute(name: "First", distance: 100, travelTime: 100,
            polyline: MKPolyline(coordinates: points, count: points.count))
        let second = DiscoveryRoute(name: "Second", distance: 100, travelTime: 100,
            polyline: MKPolyline(coordinates: points.reversed(), count: points.count))
        let before = coordinator.store.visitedCellsCache
        coordinator.updateRoutes([first, second], selectedID: second.id, mapView: map)
        XCTAssertTrue(map.overlays.first === fog)
        XCTAssertTrue(map.overlays.last === second.polyline)
        let selected = coordinator.mapView(map, rendererFor: second.polyline) as? MKPolylineRenderer
        XCTAssertEqual(selected?.strokeColor, .systemBlue)
        XCTAssertEqual(selected?.lineWidth, 6)
        XCTAssertEqual((coordinator.mapView(map, rendererFor: first.polyline) as? MKPolylineRenderer)?.lineWidth, 4)
        let target = CLLocationCoordinate2D(latitude: 41, longitude: -73)
        map.setCenter(target, animated: false)
        coordinator.updateRoutes([first, second], selectedID: second.id, mapView: map)
        XCTAssertEqual(map.centerCoordinate.latitude, target.latitude, accuracy: 0.001)
        coordinator.updateRoutes([], selectedID: nil, mapView: map)
        XCTAssertEqual(map.overlays.count, 1)
        XCTAssertTrue(map.overlays.first === fog)
        XCTAssertEqual(coordinator.store.visitedCellsCache, before)
        XCTAssertTrue(coordinator.landmarkStore.allLandmarks.isEmpty)
    }
}
