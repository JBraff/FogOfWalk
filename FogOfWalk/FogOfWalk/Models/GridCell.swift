import CoreLocation
import MapKit

// MARK: - Cell Size Constant

/// The fixed cell size used for all grid calculations.
let kCellSizeMeters: Double = 50.0

// MARK: - Cell ID

/// Integer grid coordinates identifying one fog cell.
struct CellID: Hashable, Equatable, Sendable {
    let x: Int32
    let y: Int32
}

// MARK: - Grid Math

enum GridMath {
    /// Metres per degree of latitude (and simplified longitude).
    static let metersPerDegree: Double = 111_111.0

    /// Widest map span (in degrees) for which landmarks are ingested and pins drawn.
    ///
    /// Above this the map is an orientation view, not a detail view: walking zoom under
    /// `userTrackingMode = .follow` is ~0.005–0.01°, and the fog itself already vanishes
    /// above ~0.045° via the 10,000-cell cap in `cellBounds(in:)`. 1.0° still ingests a
    /// whole metro area, while stopping one pinch-out to world zoom from dumping the
    /// entire bundled database into Core Data.
    ///
    /// `BundledLandmarkSource`'s `LIMIT` depends on this value — see the comment there.
    static let maxIngestSpanDegrees: Double = 1.0

    /// Convert a GPS coordinate to the CellID for the given cell size.
    static func cellID(for coord: CLLocationCoordinate2D) -> CellID {
        let step = kCellSizeMeters / metersPerDegree
        return CellID(
            x: Int32(floor(coord.longitude / step)),
            y: Int32(floor(coord.latitude  / step))
        )
    }

    /// Min/max corners of a cell's bounding box.
    static func bounds(for cell: CellID) -> (min: CLLocationCoordinate2D, max: CLLocationCoordinate2D) {
        let step   = kCellSizeMeters / metersPerDegree
        let minLon = Double(cell.x) * step
        let minLat = Double(cell.y) * step
        return (
            min: CLLocationCoordinate2D(latitude: minLat,        longitude: minLon),
            max: CLLocationCoordinate2D(latitude: minLat + step, longitude: minLon + step)
        )
    }

    /// Center coordinate of a cell.
    static func center(for cell: CellID) -> CLLocationCoordinate2D {
        let b = bounds(for: cell)
        return CLLocationCoordinate2D(
            latitude:  (b.min.latitude  + b.max.latitude)  / 2,
            longitude: (b.min.longitude + b.max.longitude) / 2
        )
    }

    /// Grid-coordinate bounding box for a map region. Returns nil when the region
    /// would produce more than 10,000 cells (fog stays fully opaque at those scales).
    static func cellBounds(
        in region: MKCoordinateRegion
    ) -> (minX: Int32, maxX: Int32, minY: Int32, maxY: Int32)? {
        let step    = kCellSizeMeters / metersPerDegree
        let halfLat = region.span.latitudeDelta  / 2
        let halfLon = region.span.longitudeDelta / 2

        let minLat = region.center.latitude  - halfLat
        let maxLat = region.center.latitude  + halfLat
        let minLon = region.center.longitude - halfLon
        let maxLon = region.center.longitude + halfLon

        let minX = Int32(floor(minLon / step))
        let maxX = Int32(floor(maxLon / step))
        let minY = Int32(floor(minLat / step))
        let maxY = Int32(floor(maxLat / step))

        guard maxX >= minX, maxY >= minY else { return nil }

        let countX = Int(maxX) - Int(minX) + 1
        let countY = Int(maxY) - Int(minY) + 1
        guard countX * countY <= 10_000 else { return nil }

        return (minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    /// All CellIDs whose bounding boxes intersect the given map region.
    static func cells(in region: MKCoordinateRegion) -> [CellID] {
        guard let b = cellBounds(in: region) else { return [] }

        let countX = Int(b.maxX) - Int(b.minX) + 1
        let countY = Int(b.maxY) - Int(b.minY) + 1
        var result: [CellID] = []
        result.reserveCapacity(countX * countY)
        for y in b.minY...b.maxY {
            for x in b.minX...b.maxX {
                result.append(CellID(x: x, y: y))
            }
        }
        return result
    }
}
