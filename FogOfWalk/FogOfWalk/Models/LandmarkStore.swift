import CoreData
import CoreLocation
import MapKit
import Observation

@MainActor
@Observable
final class LandmarkStore {

    // MARK: - State

    /// All landmarks (discovered + undiscovered) for overlay rendering.
    private(set) var allLandmarks: [Landmark] = []
    /// Count of discovered landmarks for HUD display.
    private(set) var totalDiscovered: Int = 0

    private var knownIdentifiers: Set<String> = []

    // MARK: - Category discovery radii (meters)

    static let categoryRadius: [String: Double] = {
        var map: [String: Double] = [:]

        // Wikidata category strings (used by new bundled landmarks).
        map["airport"]      = 500
        map["stadium"]      = 300
        map["amusementPark"] = 400
        map["nationalPark"]  = 300
        map["zoo"]           = 200
        map["university"]    = 200
        map["museum"]        = 100
        map["theater"]       = 100
        map["library"]       = 100
        map["landmark"]      = 100

        return map
    }()

    // MARK: - Migration

    /// UserDefaults key written after the one-time purge of pre-Wikidata landmarks.
    static let wikidataMigrationKey = "fog_of_walk_wikidata_migration_v1"

    // MARK: - Dependencies

    private let container: NSPersistentContainer

    // MARK: - Init

    init(container: NSPersistentContainer) {
        self.container = container
        purgeNonWikidataLandmarksIfNeeded()
        loadFromStore()
    }

    /// Testability — inject a pre-configured container.
    static func makeInMemory() -> LandmarkStore {
        let c = NSPersistentContainer(name: "FogOfWalk")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        c.persistentStoreDescriptions = [desc]
        c.loadPersistentStores { _, _ in }
        return LandmarkStore(container: c)
    }

    // MARK: - Load

    private func loadFromStore() {
        let request = Landmark.fetchRequest()
        guard let results = try? container.viewContext.fetch(request) else { return }
        allLandmarks = results
        knownIdentifiers = Set(results.map { $0.identifier })
        totalDiscovered = results.filter { $0.isDiscovered }.count
    }

    // MARK: - Write

    /// Persist landmarks from the bundled Wikidata dataset. Deduplicates by identifier.
    func addLandmarks(_ items: [WikidataLandmark]) {
        let ctx = container.viewContext
        var added = false
        for item in items {
            guard !knownIdentifiers.contains(item.id) else { continue }

            let radius = Self.categoryRadius[item.category] ?? 100

            let entity = Landmark(context: ctx)
            entity.identifier            = item.id
            entity.name                  = item.name
            entity.category              = item.category
            entity.latitude              = item.lat
            entity.longitude             = item.lon
            entity.discoveryRadiusMeters = radius
            entity.isDiscovered          = false
            entity.firstSeen             = Date()

            knownIdentifiers.insert(item.id)
            added = true
        }

        if added {
            do {
                try ctx.save()
                loadFromStore()
            } catch {
                print("LandmarkStore: save failed: \(error)")
                ctx.rollback()
            }
        }
    }

    /// Check whether any undiscovered landmarks fall within the given visited cells.
    /// Returns newly discovered landmarks so the caller can trigger haptics.
    @discardableResult
    func checkDiscovery(visitedCells: Set<CellID>) -> [Landmark] {
        let undiscovered = allLandmarks.filter { !$0.isDiscovered }
        guard !undiscovered.isEmpty else { return [] }

        var newlyDiscovered: [Landmark] = []
        let ctx = container.viewContext

        for landmark in undiscovered {
            let coord = CLLocationCoordinate2D(
                latitude: landmark.latitude,
                longitude: landmark.longitude
            )
            if isWithinVisitedCells(coord: coord,
                                    radius: landmark.discoveryRadiusMeters,
                                    cells: visitedCells) {
                landmark.isDiscovered    = true
                landmark.firstDiscovered = Date()
                newlyDiscovered.append(landmark)
            }
        }

        guard !newlyDiscovered.isEmpty else { return [] }

        do {
            try ctx.save()
            totalDiscovered = allLandmarks.filter { $0.isDiscovered }.count
        } catch {
            print("LandmarkStore: discovery save failed: \(error)")
            ctx.rollback()
            // After rollback the managed objects may have stale in-memory state.
            // Reload from Core Data so allLandmarks reflects the persisted truth.
            loadFromStore()
            return []
        }

        return newlyDiscovered
    }

    // MARK: - Query

    /// Default cap on the number of pins handed to `LandmarkOverlayView`.
    ///
    /// `LandmarkOverlayView` linear-scans its pin array in `draw` (every frame), `hitTest`
    /// (every touch) and `handleTap`, and the off-screen cull happens *after* the per-pin
    /// coordinate conversion. Users who world-zoomed before `maxIngestSpanDegrees` existed
    /// have up to ~15,000 rows in Core Data permanently, so the array must be bounded
    /// regardless of how much is stored.
    static let maxRenderedPins = 300

    /// All landmarks visible within a coordinate region, for overlay rendering.
    ///
    /// When more than `limit` landmarks fall inside `region`, discovered ones are kept in
    /// preference to undiscovered hints — they carry a name label and are the only tappable
    /// pins, so dropping them would lose functionality rather than just detail.
    func landmarks(in region: MKCoordinateRegion,
                   limit: Int = LandmarkStore.maxRenderedPins) -> [Landmark] {
        let latDelta = region.span.latitudeDelta / 2
        let lonDelta = region.span.longitudeDelta / 2
        let center   = region.center

        let visible = allLandmarks.filter { landmark in
            abs(landmark.latitude  - center.latitude)  <= latDelta
                && abs(landmark.longitude - center.longitude) <= lonDelta
        }

        guard visible.count > limit else { return visible }

        var capped = visible.filter { $0.isDiscovered }
        if capped.count >= limit { return Array(capped.prefix(limit)) }
        capped.append(contentsOf: visible.lazy.filter { !$0.isDiscovered }
                                             .prefix(limit - capped.count))
        return capped
    }

    // MARK: - Migration

    /// Deletes any landmarks whose identifier is not a Wikidata QID (`Q` + digits).
    /// Runs exactly once, guarded by a UserDefaults flag.
    private func purgeNonWikidataLandmarksIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.wikidataMigrationKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: Self.wikidataMigrationKey) }

        let ctx = container.viewContext
        let request = Landmark.fetchRequest()
        // Keep only identifiers that match the Wikidata QID pattern: Q followed by digits.
        request.predicate = NSPredicate(format: "NOT (identifier MATCHES %@)", "Q[0-9]+")
        guard let old = try? ctx.fetch(request), !old.isEmpty else { return }
        old.forEach { ctx.delete($0) }
        try? ctx.save()
    }

    // MARK: - Private helpers

    private func isWithinVisitedCells(coord: CLLocationCoordinate2D,
                                      radius: Double,
                                      cells: Set<CellID>) -> Bool {
        // Pre-filter to the CellID bounding box for the discovery radius. This avoids
        // O(all_visited_cells) geodesic math — only the small set of cells near the
        // landmark are checked precisely.
        let step = kCellSizeMeters / GridMath.metersPerDegree
        // Add one cell of padding to account for cells that overlap the radius boundary.
        let latPad = (radius / GridMath.metersPerDegree) + step
        let lonPad = (radius / GridMath.metersPerDegree) + step
        let minX = Int32(floor((coord.longitude - lonPad) / step))
        let maxX = Int32(floor((coord.longitude + lonPad) / step))
        let minY = Int32(floor((coord.latitude  - latPad) / step))
        let maxY = Int32(floor((coord.latitude  + latPad) / step))

        let landmarkLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        for cell in cells where cell.x >= minX && cell.x <= maxX && cell.y >= minY && cell.y <= maxY {
            let cellCenter = GridMath.center(for: cell)
            let cellLoc = CLLocation(latitude: cellCenter.latitude, longitude: cellCenter.longitude)
            if cellLoc.distance(from: landmarkLoc) <= radius {
                return true
            }
        }
        return false
    }
}
