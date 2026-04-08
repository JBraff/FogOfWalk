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
        for coord in coords {
            let cell   = GridMath.cellID(for: coord)
            let bounds = GridMath.bounds(for: cell)
            XCTAssertLessThanOrEqual(bounds.min.latitude,  coord.latitude,  "lat min")
            XCTAssertGreaterThan(    bounds.max.latitude,  coord.latitude,  "lat max")
            XCTAssertLessThanOrEqual(bounds.min.longitude, coord.longitude, "lon min")
            XCTAssertGreaterThan(    bounds.max.longitude, coord.longitude, "lon max")
        }
    }

    // Cell centre should be within half a step of the input coordinate.
    func testCentreIsWithinHalfStep() {
        let nyc  = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        let cell = GridMath.cellID(for: nyc)
        let c    = GridMath.center(for: cell)
        let step = kCellSizeMeters / GridMath.metersPerDegree
        XCTAssertLessThanOrEqual(abs(c.latitude  - nyc.latitude),  step / 2 + 1e-10)
        XCTAssertLessThanOrEqual(abs(c.longitude - nyc.longitude), step / 2 + 1e-10)
    }

    // cells(in:) must include the cell that contains the region centre.
    func testRegionCellsContainCentre() {
        let sf     = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let region = MKCoordinateRegion(center: sf, latitudinalMeters: 500, longitudinalMeters: 500)
        let cells  = GridMath.cells(in: region)
        let centreCell = GridMath.cellID(for: sf)
        XCTAssertTrue(cells.contains(centreCell))
    }

    // cells(in:) for a 100m region at 50m cells must return at least 1 cell.
    func testRegionCellsMinCount() {
        let london = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        let region = MKCoordinateRegion(center: london, latitudinalMeters: 100, longitudinalMeters: 100)
        let cells  = GridMath.cells(in: region)
        XCTAssertGreaterThanOrEqual(cells.count, 1)
    }

    // Negative coordinates (southern / western hemisphere) round-trip correctly.
    func testNegativeCoordinates() {
        let sydney = CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)
        let cell   = GridMath.cellID(for: sydney)
        let bounds = GridMath.bounds(for: cell)
        XCTAssertLessThan(bounds.min.latitude, 0, "Southern hemisphere: min lat should be negative")
        XCTAssertLessThan(cell.y,              0, "Southern hemisphere: cellY should be negative")
    }

    // A world-zoom region produces > 10 000 cells and must return [].
    func testCellsInRegionCappedAt10000() {
        let world = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span:   MKCoordinateSpan(latitudeDelta: 170, longitudeDelta: 350)
        )
        let cells = GridMath.cells(in: world)
        XCTAssertEqual(cells, [], "World-zoom region must return [] (> 10 000 cells)")
    }

    // (0,0) maps to cell (0,0); a point just below/left of origin maps to (-1,-1).
    func testCellIDAtOriginBoundary() {
        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let cell   = GridMath.cellID(for: origin)
        XCTAssertEqual(cell, CellID(x: 0, y: 0), "Origin should be in cell (0,0)")

        let epsilon  = 1e-10
        let negCoord = CLLocationCoordinate2D(latitude: -epsilon, longitude: -epsilon)
        let negCell  = GridMath.cellID(for: negCoord)
        XCTAssertEqual(negCell, CellID(x: -1, y: -1),
                       "Just below/left of origin should be in cell (-1,-1)")
    }

    // A region smaller than one cell must still return at least one cell.
    func testCellsInTinyRegion() {
        let coord  = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        let region = MKCoordinateRegion(center: coord,
                                        latitudinalMeters: 1, longitudinalMeters: 1)
        let cells  = GridMath.cells(in: region)
        XCTAssertGreaterThanOrEqual(cells.count, 1,
                                    "Sub-cell region must return at least 1 cell")
    }

    // Western-hemisphere coordinate round-trips through bounds correctly.
    func testBoundsRoundTripNegativeLongitude() {
        let la     = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        let cell   = GridMath.cellID(for: la)
        let bounds = GridMath.bounds(for: cell)

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
