import CoreLocation

/// Display-only estimate using the recording grid. Never feeds locations to the recorder.
enum RouteCellEstimator {
    /// Bound total work, including repeated segments, rather than just unique cells.
    static let maxWork = 50_000

    /// Enumerates every half-open grid cell along each segment (not just its vertices).
    /// A corner crossing advances both axes: cells touched only at that corner are excluded.
    /// Invalid, antimeridian-spanning or excessive geometry has no estimate, not a partial one.
    static func cells(along coordinates: [CLLocationCoordinate2D], workLimit: Int = maxWork) -> Set<CellID>? {
        guard !coordinates.isEmpty, coordinates.count <= workLimit,
              coordinates.allSatisfy({ CLLocationCoordinate2DIsValid($0) }) else { return nil }
        let step = kCellSizeMeters / GridMath.metersPerDegree
        var cells: Set<CellID> = []
        var work = coordinates.count
        cells.insert(GridMath.cellID(for: coordinates[0]))
        for (start, end) in zip(coordinates, coordinates.dropFirst()) {
            guard abs(end.longitude - start.longitude) <= 180 else { return nil }
            let x0 = start.longitude / step, y0 = start.latitude / step
            let x1 = end.longitude / step, y1 = end.latitude / step
            var x = Int32(floor(x0)), y = Int32(floor(y0))
            let endX = Int32(floor(x1)), endY = Int32(floor(y1))
            let dx = x1 - x0, dy = y1 - y0
            let sx: Int32 = dx > 0 ? 1 : -1, sy: Int32 = dy > 0 ? 1 : -1
            let deltaX = dx == 0 ? Double.infinity : 1 / abs(dx)
            let deltaY = dy == 0 ? Double.infinity : 1 / abs(dy)
            var nextX = dx == 0 ? Double.infinity
                : ((dx > 0 ? Double(x) + 1 : Double(x)) - x0) / dx
            var nextY = dy == 0 ? Double.infinity
                : ((dy > 0 ? Double(y) + 1 : Double(y)) - y0) / dy
            while x != endX || y != endY {
                work += 1
                guard work <= workLimit else { return nil }
                // An axis already at its endpoint cell must not advance past it at t=1.
                let tx = x == endX ? Double.infinity : nextX
                let ty = y == endY ? Double.infinity : nextY
                if tx < ty {
                    x += sx; nextX += deltaX
                } else if ty < tx {
                    y += sy; nextY += deltaY
                } else {
                    x += sx; y += sy; nextX += deltaX; nextY += deltaY
                }
                cells.insert(CellID(x: x, y: y))
            }
        }
        return cells
    }
}
