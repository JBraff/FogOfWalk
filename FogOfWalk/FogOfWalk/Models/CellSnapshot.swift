import CoreLocation

/// Immutable, thread-safe snapshot of visited cell state for background fog rendering.
/// Created on the main thread from ExplorationStore.visitedCellsCache (a value-type
/// Set copy), then read concurrently by background MKOverlayRenderer draw calls.
struct CellSnapshot: Sendable {

    // Cells bucketed by y-coordinate so spatial tile queries only iterate the
    // rows that intersect the current tile — O(rows_in_tile * cells_per_row)
    // instead of O(all_visited_cells).
    // Dictionary<Int32, Set<CellID>> is Sendable because both key and value types
    // are Sendable (Int32 is Sendable; Set<CellID> is Sendable when CellID is Sendable).
    private let cellBuckets:   [Int32: Set<CellID>]
    private let recentBuckets: [Int32: Set<CellID>]
    let cellSizeMeters: Double

    init(cells: Set<CellID>, recentCells: Set<CellID> = [], cellSizeMeters: Double) {
        var cb: [Int32: Set<CellID>] = [:]
        for cell in cells {
            cb[cell.y, default: []].insert(cell)
        }
        var rb: [Int32: Set<CellID>] = [:]
        for cell in recentCells {
            rb[cell.y, default: []].insert(cell)
        }
        self.cellBuckets    = cb
        self.recentBuckets  = rb
        self.cellSizeMeters = cellSizeMeters
    }

    /// All visited cells (flattened from buckets). Used by tests; production code
    /// prefers `visitedCells(inLatRange:lonRange:)`.
    var cells: Set<CellID> {
        cellBuckets.values.reduce(into: Set()) { $0.formUnion($1) }
    }

    /// All recent cells (flattened from buckets). Used by tests; production code
    /// prefers `recentCells(inLatRange:lonRange:)`.
    var recentCells: Set<CellID> {
        recentBuckets.values.reduce(into: Set()) { $0.formUnion($1) }
    }

    /// Visited cells whose grid-coordinate bounds intersect the given lat/lon rectangle.
    /// Unlike GridMath.cellBounds(in:cellSizeMeters:), there is no cell-count cap here —
    /// this is safe because each tile query covers only a small geographic area.
    func visitedCells(
        inLatRange latRange: ClosedRange<Double>,
        lonRange:  ClosedRange<Double>
    ) -> [CellID] {
        filtered(cellBuckets, latRange: latRange, lonRange: lonRange)
    }

    /// Recent cells (subset of `cells`) intersecting the given lat/lon rectangle.
    func recentCells(
        inLatRange latRange: ClosedRange<Double>,
        lonRange:  ClosedRange<Double>
    ) -> [CellID] {
        filtered(recentBuckets, latRange: latRange, lonRange: lonRange)
    }

    private func filtered(
        _ buckets: [Int32: Set<CellID>],
        latRange: ClosedRange<Double>,
        lonRange: ClosedRange<Double>
    ) -> [CellID] {
        let step = cellSizeMeters / GridMath.metersPerDegree
        let minX = Int32(floor(lonRange.lowerBound / step))
        let maxX = Int32(floor(lonRange.upperBound / step))
        let minY = Int32(floor(latRange.lowerBound / step))
        let maxY = Int32(floor(latRange.upperBound / step))
        guard minY <= maxY else { return [] }
        var result: [CellID] = []
        for y in minY...maxY {
            guard let row = buckets[y] else { continue }
            for cell in row where cell.x >= minX && cell.x <= maxX {
                result.append(cell)
            }
        }
        return result
    }
}
