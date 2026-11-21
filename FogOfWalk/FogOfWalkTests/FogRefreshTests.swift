import XCTest
import MapKit
import SwiftUI
@testable import FogOfWalk

/// Records redraw requests instead of passing them to MapKit.
final class RecordingFogRenderer: FogOverlayRenderer {
    var fullRedraws = 0
    var partialRedraws: [MKMapRect] = []

    init() { super.init(overlay: FogOverlay(), snapshot: CellSnapshot(cells: [])) }

    override func setNeedsDisplay() { fullRedraws += 1 }
    override func setNeedsDisplay(_ mapRect: MKMapRect) { partialRedraws.append(mapRect) }
}

// Observable stores must be created and released inside a Task (see LandmarkStoreTests).
final class FogRefreshTests: XCTestCase {

    static let center = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)

    /// A coordinator wired to a recording renderer and a map at walking zoom. The first
    /// push always redraws everything, so it is made here.
    @MainActor
    func makeCoordinator() -> (MapContainerView.Coordinator, RecordingFogRenderer, MKMapView) {
        let coordinator = makeLandmarkCoordinator()
        let renderer = RecordingFogRenderer()
        let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        mapView.setRegion(MKCoordinateRegion(center: Self.center, latitudinalMeters: 1_000,
                                             longitudinalMeters: 1_000), animated: false)
        coordinator.fogRenderer = renderer
        coordinator.mapView = mapView
        XCTAssertTrue(coordinator.refreshFogIfChanged(in: .active))
        XCTAssertEqual(renderer.fullRedraws, 1)
        return (coordinator, renderer, mapView)
    }

    func testNewCellRedrawsOnlyTheAreaAroundIt() async {
        await MainActor.run {
            let (coordinator, renderer, mapView) = makeCoordinator()
            let cell = GridMath.cellID(for: Self.center)
            coordinator.store.addCell(cell)
            XCTAssertTrue(coordinator.refreshFogIfChanged(in: .active))

            XCTAssertEqual(renderer.fullRedraws, 1, "A new cell must not redraw every tile")
            XCTAssertEqual(renderer.partialRedraws.count, 1)
            let dirty = renderer.partialRedraws[0]
            XCTAssertTrue(dirty.contains(MKMapPoint(GridMath.center(for: cell))))
            // The area covers the neighbouring cell a trail line runs to, but stays far
            // smaller than the visible map.
            let neighbour = CellID(x: cell.x + 1, y: cell.y + 1)
            XCTAssertTrue(dirty.contains(MKMapPoint(GridMath.center(for: neighbour))))
            XCTAssertLessThan(dirty.size.width, mapView.visibleMapRect.size.width / 4)
            XCTAssertTrue(renderer.snapshot.cells.contains(cell))
        }
    }

    func testStyleAndAppearanceChangesRedrawEverything() async {
        await MainActor.run {
            let (coordinator, renderer, _) = makeCoordinator()
            XCTAssertFalse(coordinator.refreshFogIfChanged(in: .active))

            coordinator.gridSettings.fogStyle = .trail
            XCTAssertTrue(coordinator.refreshFogIfChanged(in: .active))
            XCTAssertEqual(renderer.fullRedraws, 2)
            XCTAssertEqual(renderer.appearance.style, .trail)

            coordinator.isDark = true
            XCTAssertTrue(coordinator.refreshFogIfChanged(in: .active))
            XCTAssertEqual(renderer.fullRedraws, 3)
            XCTAssertTrue(renderer.appearance.isDark)

            coordinator.gridSettings.todayHighlight = .walkedToday
            XCTAssertTrue(coordinator.refreshFogIfChanged(in: .active))
            XCTAssertEqual(renderer.fullRedraws, 4)
            XCTAssertTrue(renderer.appearance.highlightActive)

            // Background pushes wait for the foreground, as before.
            coordinator.gridSettings.fogStyle = .spotlight
            XCTAssertFalse(coordinator.refreshFogIfChanged(in: .background))
            XCTAssertEqual(renderer.appearance.style, .trail)
            XCTAssertTrue(renderer.partialRedraws.isEmpty)
        }
    }

    func testChangedCellsFallsBackToAFullRedraw() async {
        await MainActor.run {
            typealias C = MapContainerView.Coordinator
            let a = CellID(x: 1, y: 1), b = CellID(x: 2, y: 1), c = CellID(x: 3, y: 1)

            let changed = C.changedCells(visited: ([a], [a, b]), recent: ([a], [b]))
            XCTAssertEqual(Set(changed ?? []), [a, b], "New cells and highlight changes both redraw")

            XCTAssertNil(C.changedCells(visited: ([a, b], [a, c]), recent: ([], [])),
                         "A removed cell (import or reset) redraws everything")
            XCTAssertNil(C.changedCells(visited: ([a, b], [a]), recent: ([], [])))

            let many = Set((0..<Int32(C.maxPartialRedrawCells + 1)).map { CellID(x: $0, y: 9) })
            XCTAssertNil(C.changedCells(visited: ([], many), recent: ([], [])))
            XCTAssertNil(C.changedCells(visited: ([], []), recent: ([], many)))

            XCTAssertNil(C.fogDirtyRect(changedCells: nil, zoomScale: 1))
            XCTAssertNil(C.fogDirtyRect(changedCells: [a], zoomScale: nil))
            XCTAssertEqual(C.fogDirtyRect(changedCells: [], zoomScale: 1)?.isNull, true)
        }
    }

    /// Zoomed out, a cell is smaller than its 3 pt minimum and the blur, so the redrawn
    /// area grows with the on-screen reach rather than staying one cell wide.
    func testDirtyAreaCoversTheOnScreenReachWhenZoomedOut() async {
        await MainActor.run {
            let cell = GridMath.cellID(for: Self.center)
            let zoomScale: MKZoomScale = 0.001
            let rect = MapContainerView.Coordinator.fogDirtyRect(changedCells: [cell], zoomScale: zoomScale)
            let reach = Double(SoftFogRenderer.maxReachPoints) / Double(zoomScale)
            XCTAssertGreaterThanOrEqual(rect?.size.width ?? 0, 2 * reach)
        }
    }
}
