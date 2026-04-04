import XCTest
import CoreLocation
import MapKit
@testable import FogOfWalk

final class GridCellTests: XCTestCase {

    // A coordinate should land inside its own cell's bounding box.
    func testCoordinateInsideBounds() {
        let coords: [CLLocationCoordinate2D] = [
            .init(latitude:  40.7128, longitude: -74.0060),  // New York
            .init(latitude: -33.8688, longitude: 151.2093),  // Sydney
            .init(latitude:  51.5074, longitude:  -0.1278),  // London
            .init(latitude:  48.8566, longitude:   2.3522),  // Paris
            .init(latitude:   0.0,    longitude:   0.0),     // Equator / Prime Meridian
        ]
        for size in [25.0, 50.0, 100.0, 200.0] {
            for coord in coords {
                let cell   = GridMath.cellID(for: coord, cellSizeMeters: size)
                let bounds = GridMath.bounds(for: cell, cellSizeMeters: size)
                XCTAssertLessThanOrEqual(bounds.min.latitude,  coord.latitude,  "lat min, size=\(size)")
                XCTAssertGreaterThan(    bounds.max.latitude,  coord.latitude,  "lat max, size=\(size)")
                XCTAssertLessThanOrEqual(bounds.min.longitude, coord.longitude, "lon min, size=\(size)")
                XCTAssertGreaterThan(    bounds.max.longitude, coord.longitude, "lon max, size=\(size)")
            }
        }
    }

    // Cell centre should be within half a step of the input coordinate.
    func testCentreIsWithinHalfStep() {
        let nyc  = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        let size = 50.0
        let cell = GridMath.cellID(for: nyc, cellSizeMeters: size)
        let c    = GridMath.center(for: cell, cellSizeMeters: size)
        let step = size / GridMath.metersPerDegree
        XCTAssertLessThanOrEqual(abs(c.latitude  - nyc.latitude),  step / 2 + 1e-10)
        XCTAssertLessThanOrEqual(abs(c.longitude - nyc.longitude), step / 2 + 1e-10)
    }

    // cells(in:) must include the cell that contains the region centre.
    func testRegionCellsContainCentre() {
        let sf     = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let region = MKCoordinateRegion(center: sf, latitudinalMeters: 500, longitudinalMeters: 500)
        let cells  = GridMath.cells(in: region, cellSizeMeters: 50)
        let centreCell = GridMath.cellID(for: sf, cellSizeMeters: 50)
        XCTAssertTrue(cells.contains(centreCell))
    }

    // cells(in:) for a 100m region at 50m cells must return at least 1 cell.
    func testRegionCellsMinCount() {
        let london = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        let region = MKCoordinateRegion(center: london, latitudinalMeters: 100, longitudinalMeters: 100)
        let cells  = GridMath.cells(in: region, cellSizeMeters: 50)
        XCTAssertGreaterThanOrEqual(cells.count, 1)
    }

    // Different cell sizes produce different CellID grid coordinates for the same location.
    func testDifferentSizesProduceDifferentIDs() {
        let paris = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
        let c50   = GridMath.cellID(for: paris, cellSizeMeters: 50)
        let c100  = GridMath.cellID(for: paris, cellSizeMeters: 100)
        let step50  = 50.0  / GridMath.metersPerDegree
        let step100 = 100.0 / GridMath.metersPerDegree
        XCTAssertEqual(c50.x,  Int32(floor(paris.longitude / step50)))
        XCTAssertEqual(c100.x, Int32(floor(paris.longitude / step100)))
        XCTAssertNotEqual(c50.x, c100.x)
    }

    // Negative coordinates (southern / western hemisphere) round-trip correctly.
    func testNegativeCoordinates() {
        let sydney = CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)
        let cell   = GridMath.cellID(for: sydney, cellSizeMeters: 50)
        let bounds = GridMath.bounds(for: cell, cellSizeMeters: 50)
        XCTAssertLessThan(bounds.min.latitude, 0, "Southern hemisphere: min lat should be negative")
        XCTAssertLessThan(cell.y,              0, "Southern hemisphere: cellY should be negative")
    }

    // A world-zoom region produces > 10 000 cells and must return [].
    func testCellsInRegionCappedAt10000() {
        let world = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span:   MKCoordinateSpan(latitudeDelta: 170, longitudeDelta: 350)
        )
        let cells = GridMath.cells(in: world, cellSizeMeters: 50)
        XCTAssertEqual(cells, [], "World-zoom region must return [] (> 10 000 cells)")
    }

    // (0,0) maps to cell (0,0); a point just below/left of origin maps to (-1,-1).
    func testCellIDAtOriginBoundary() {
        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let cell   = GridMath.cellID(for: origin, cellSizeMeters: 50)
        XCTAssertEqual(cell, CellID(x: 0, y: 0), "Origin should be in cell (0,0)")

        let epsilon  = 1e-10
        let negCoord = CLLocationCoordinate2D(latitude: -epsilon, longitude: -epsilon)
        let negCell  = GridMath.cellID(for: negCoord, cellSizeMeters: 50)
        XCTAssertEqual(negCell, CellID(x: -1, y: -1),
                       "Just below/left of origin should be in cell (-1,-1)")
    }

    // A region smaller than one cell must still return at least one cell.
    func testCellsInTinyRegion() {
        let coord  = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        let region = MKCoordinateRegion(center: coord,
                                        latitudinalMeters: 1, longitudinalMeters: 1)
        let cells  = GridMath.cells(in: region, cellSizeMeters: 50)
        XCTAssertGreaterThanOrEqual(cells.count, 1,
                                    "Sub-cell region must return at least 1 cell")
    }

    // Western-hemisphere coordinate round-trips through bounds correctly.
    func testBoundsRoundTripNegativeLongitude() {
        let la     = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        let cell   = GridMath.cellID(for: la, cellSizeMeters: 50)
        let bounds = GridMath.bounds(for: cell, cellSizeMeters: 50)

        XCTAssertLessThanOrEqual(bounds.min.longitude, la.longitude,
                                 "Cell min.longitude must be ≤ coordinate longitude")
        XCTAssertGreaterThan(bounds.max.longitude, la.longitude,
                             "Cell max.longitude must be > coordinate longitude")
        XCTAssertLessThanOrEqual(bounds.min.latitude, la.latitude,
                                 "Cell min.latitude must be ≤ coordinate latitude")
        XCTAssertGreaterThan(bounds.max.latitude, la.latitude,
                             "Cell max.latitude must be > coordinate latitude")
        XCTAssertLessThan(bounds.min.longitude, 0, "Western hemisphere: min longitude must be negative")
        XCTAssertLessThan(bounds.max.longitude, 0, "Western hemisphere: max longitude must be negative")
    }
}
