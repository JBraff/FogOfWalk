import CoreLocation

/// Immutable, thread-safe snapshot of visited cell state for background fog rendering.
/// Created on the main thread from ExplorationStore.visitedCellsCache (a value-type
/// Set copy), then read concurrently by background MKOverlayRenderer draw calls.
struct CellSnapshot: Sendable {
    let cells: Set<CellID>
    let recentCells: Set<CellID>
    let cellSizeMeters: Double

    init(cells: Set<CellID>, recentCells: Set<CellID> = [], cellSizeMeters: Double) {
        self.cells = cells
        self.recentCells = recentCells
        self.cellSizeMeters = cellSizeMeters
    }

    /// Visited cells whose grid-coordinate bounds intersect the given lat/lon rectangle.
    /// Unlike GridMath.cellBounds(in:cellSizeMeters:), there is no cell-count cap here —
    /// this is safe because each tile query covers only a small geographic area.
    func visitedCells(
        inLatRange latRange: ClosedRange<Double>,
        lonRange:  ClosedRange<Double>
    ) -> [CellID] {
        filtered(cells, latRange: latRange, lonRange: lonRange)
    }

    /// Recent cells (subset of `cells`) intersecting the given lat/lon rectangle.
    func recentCells(
        inLatRange latRange: ClosedRange<Double>,
        lonRange:  ClosedRange<Double>
    ) -> [CellID] {
        filtered(recentCells, latRange: latRange, lonRange: lonRange)
    }

    private func filtered(
        _ set: Set<CellID>,
        latRange: ClosedRange<Double>,
        lonRange: ClosedRange<Double>
    ) -> [CellID] {
        let step = cellSizeMeters / GridMath.metersPerDegree
        let minX = Int32(floor(lonRange.lowerBound / step))
        let maxX = Int32(floor(lonRange.upperBound / step))
        let minY = Int32(floor(latRange.lowerBound / step))
        let maxY = Int32(floor(latRange.upperBound / step))
        return set.filter { $0.x >= minX && $0.x <= maxX && $0.y >= minY && $0.y <= maxY }
    }
}
