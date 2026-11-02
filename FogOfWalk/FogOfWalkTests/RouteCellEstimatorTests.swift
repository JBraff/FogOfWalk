import XCTest
import MapKit
@testable import FogOfWalk

@MainActor
final class RouteCellEstimatorTests: XCTestCase {
    private func point(_ x: Double, _ y: Double) -> CLLocationCoordinate2D {
        let step = kCellSizeMeters / GridMath.metersPerDegree
        return .init(latitude: y * step, longitude: x * step)
    }

    func testSparseSegmentIncludesIntermediateCellsAndDeduplicatesReturnWalk() {
        let route = [point(0.25, 0.25), point(4.75, 0.25), point(0.25, 0.25)]
        XCTAssertEqual(RouteCellEstimator.cells(along: route), Set((0...4).map { CellID(x: Int32($0), y: 0) }))
    }
    func testVerticalNegativeAndDiagonalSegments() {
        XCTAssertEqual(RouteCellEstimator.cells(along: [point(-2.5, -3.5), point(-2.5, 0.5)]),
                       Set((-4...0).map { CellID(x: -3, y: Int32($0)) }))
        let diagonal = [point(0.25, 0.25), point(3.75, 3.75)]
        let expected = Set((0...3).map { CellID(x: Int32($0), y: Int32($0)) })
        XCTAssertEqual(RouteCellEstimator.cells(along: diagonal), expected)
        XCTAssertEqual(RouteCellEstimator.cells(along: diagonal.reversed()), expected)
    }
    func testBoundaryEndpointsAndRepeatedVertices() {
        let route = [point(0, 0), point(0, 0), point(-2, 0)]
        XCTAssertEqual(RouteCellEstimator.cells(along: route),
                       [CellID(x: 0, y: 0), CellID(x: -1, y: 0), CellID(x: -2, y: 0)])
        XCTAssertEqual(RouteCellEstimator.cells(along: route.reversed()), RouteCellEstimator.cells(along: route))
    }
    func testNearCornerDoesNotSkipShortCellCrossing() {
        let result = RouteCellEstimator.cells(along: [point(0.1, 0.1), point(2.9, 2.8)])
        XCTAssertTrue(result?.contains(CellID(x: 1, y: 0)) == true)
        XCTAssertTrue(result?.contains(CellID(x: 2, y: 1)) == true)
    }
    func testInvalidAndExcessiveGeometryNeverReturnsPartialEstimate() {
        XCTAssertNil(RouteCellEstimator.cells(along: []))
        XCTAssertNil(RouteCellEstimator.cells(along: [.init(latitude: .nan, longitude: 0)]))
        XCTAssertNil(RouteCellEstimator.cells(along: [.init(latitude: 91, longitude: 0)]))
        XCTAssertNil(RouteCellEstimator.cells(along: [.init(latitude: 0, longitude: 179.9), .init(latitude: 0, longitude: -179.9)]))
        XCTAssertNil(RouteCellEstimator.cells(along: [point(0.1, 0.1), point(20.1, 0.1)], workLimit: 10))
        // Work is capped even if the same small set is traversed many times.
        XCTAssertNil(RouteCellEstimator.cells(along: (0..<10).map { point($0.isMultiple(of: 2) ? 0.1 : 5.1, 0.1) }, workLimit: 20))
    }
    func testScoringUsesVisitedCellsWithoutMutatingThemAndCountsZero() async {
        await MainActor.run {
            let coordinates = [point(0.25, 0.25), point(2.75, 0.25)]
            let route = DiscoveryRoute(name: "Walk", distance: 100, travelTime: 60,
                polyline: MKPolyline(coordinates: coordinates, count: coordinates.count))
            let visited: Set<CellID> = [CellID(x: 0, y: 0)]
            XCTAssertEqual(route.newCellCount(visited: visited), 2)
            XCTAssertEqual(visited.count, 1)
            XCTAssertEqual(route.newCellCount(visited: route.cells!), 0)
        }
    }
}
