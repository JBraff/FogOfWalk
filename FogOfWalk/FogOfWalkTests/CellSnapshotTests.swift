import XCTest
@testable import FogOfWalk

final class CellSnapshotTests: XCTestCase {

    let cellSize = 50.0

    func testSnapshotIsImmutableAfterOriginalSetMutates() {
        var original: Set<CellID> = [CellID(x: 0, y: 0)]
        let snap = CellSnapshot(cells: original, cellSizeMeters: cellSize)
        original.insert(CellID(x: 1, y: 1))   // mutate the original

        XCTAssertEqual(snap.cells.count, 1,
            "Snapshot must be an independent copy; original mutation must not propagate")
    }

    func testSnapshotBoundsFilterExcludesOutOfBoundsCells() {
        let inRange  = CellID(x: 0, y: 0)
        let outRange = CellID(x: 100, y: 100)
        let snap = CellSnapshot(cells: [inRange, outRange], cellSizeMeters: cellSize)

        let step = cellSize / GridMath.metersPerDegree
        let result = snap.visitedCells(inLatRange: -step...step, lonRange: -step...step)
        XCTAssertTrue(result.contains(inRange),   "In-range cell must be returned")
        XCTAssertFalse(result.contains(outRange), "Out-of-range cell must be excluded")
    }

    func testSnapshotBoundsFilterReturnsEmptyForEmptySnapshot() {
        let snap = CellSnapshot(cells: [], cellSizeMeters: cellSize)
        let result = snap.visitedCells(inLatRange: -1...1, lonRange: -1...1)
        XCTAssertTrue(result.isEmpty, "Empty snapshot must return empty result")
    }

    // MARK: - Recent cells

    func testRecentCellsDefaultsToEmpty() {
        let snap = CellSnapshot(cells: [CellID(x: 0, y: 0)], cellSizeMeters: cellSize)
        XCTAssertTrue(snap.recentCells.isEmpty, "recentCells should default to empty")
    }

    func testRecentCellsFilterExcludesOutOfBoundsCells() {
        let inRange  = CellID(x: 0, y: 0)
        let outRange = CellID(x: 100, y: 100)
        let snap = CellSnapshot(cells: [inRange, outRange],
                                recentCells: [inRange, outRange],
                                cellSizeMeters: cellSize)

        let step = cellSize / GridMath.metersPerDegree
        let result = snap.recentCells(inLatRange: -step...step, lonRange: -step...step)
        XCTAssertTrue(result.contains(inRange),   "In-range recent cell must be returned")
        XCTAssertFalse(result.contains(outRange), "Out-of-range recent cell must be excluded")
    }

    func testRecentCellsFilterReturnsEmptyForEmptySet() {
        let snap = CellSnapshot(cells: [CellID(x: 0, y: 0)],
                                recentCells: [],
                                cellSizeMeters: cellSize)
        let result = snap.recentCells(inLatRange: -1...1, lonRange: -1...1)
        XCTAssertTrue(result.isEmpty, "Empty recent set must return empty result")
    }

    func testRecentCellsIsSubsetOfVisitedCells() {
        let all    = CellID(x: 0, y: 0)
        let recent = CellID(x: 0, y: 0)
        let snap = CellSnapshot(cells: [all, CellID(x: 1, y: 1)],
                                recentCells: [recent],
                                cellSizeMeters: cellSize)
        let step = cellSize / GridMath.metersPerDegree
        let recentResult  = snap.recentCells(inLatRange: -step * 10...step * 10,
                                             lonRange: -step * 10...step * 10)
        let visitedResult = snap.visitedCells(inLatRange: -step * 10...step * 10,
                                              lonRange: -step * 10...step * 10)
        XCTAssertTrue(recentResult.count <= visitedResult.count,
                      "Recent cells must be a subset of visited cells")
    }
}
