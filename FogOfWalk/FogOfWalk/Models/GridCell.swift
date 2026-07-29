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

    /// Smallest cosine of latitude used when padding a longitude range.
    ///
    /// Longitude degrees shrink as `cos(latitude)`, so a metre-radius converted to degrees
    /// of longitude diverges near the poles. This floor (cos 85°) keeps the resulting cell
    /// box from exploding; the northernmost landmark in the bundled database is at 82.5°.
    private static let minCosLatitude: Double = cos(85.0 * .pi / 180.0)

    /// Grid-coordinate bounding box covering every cell that could lie within
    /// `radiusMeters` of `coord`.
    ///
    /// **Invariant: the returned box is a strict superset of the disc.** It is a cheap
    /// prefilter, so it must never exclude a cell that the precise distance check would
    /// accept. Two things buy that:
    ///
    /// 1. Longitude padding divides by `cos(latitude)`. The grid is uniform in *degrees*,
    ///    so a cell is only `kCellSizeMeters * cos(latitude)` wide east-west. Omitting this
    ///    factor makes the box too narrow and silently drops landmarks that sit due east or
    ///    west of the walked cell — the bug this helper exists to prevent.
    /// 2. `cosφ` is taken at the latitude *farthest from the equator* in the box, where
    ///    longitude degrees are shortest and therefore the padding in degrees is largest.
    ///    The precise check uses `cos(latitude)` at the landmark, which is always ≥ this
    ///    value, so the box can only ever be too wide — never too narrow.
    ///
    /// Do not "simplify" both sides to use `cos(latitude)`: that breaks the superset
    /// property at the top edge of the box and reintroduces missed discoveries.
    ///
    /// One cell of padding is added on every side so cells that merely overlap the radius
    /// boundary are still considered.
    ///
    /// Known limitation, pre-existing and unchanged: a coordinate within `radiusMeters` of
    /// the antimeridian produces a box whose x range crosses the ±180° wrap and includes
    /// cell coordinates that do not exist. No landmark in the bundled database is affected.
    static func cellBox(
        around coord: CLLocationCoordinate2D,
        radiusMeters radius: Double
    ) -> (minX: Int32, maxX: Int32, minY: Int32, maxY: Int32) {
        let step   = kCellSizeMeters / metersPerDegree
        let latPad = (radius / metersPerDegree) + step

        // Farthest-from-equator latitude in the box → smallest cos → largest lon padding.
        let worstLat = min(abs(coord.latitude) + latPad, 90.0)
        let cosLat   = max(cos(worstLat * .pi / 180.0), minCosLatitude)
        let lonPad   = (radius / (metersPerDegree * cosLat)) + step

        return (
            minX: Int32(floor((coord.longitude - lonPad) / step)),
            maxX: Int32(floor((coord.longitude + lonPad) / step)),
            minY: Int32(floor((coord.latitude  - latPad) / step)),
            maxY: Int32(floor((coord.latitude  + latPad) / step))
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
