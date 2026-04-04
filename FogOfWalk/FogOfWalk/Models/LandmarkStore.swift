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
    func checkDiscovery(visitedCells: Set<CellID>, cellSizeMeters: Double) -> [Landmark] {
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
                                    cells: visitedCells,
                                    cellSizeMeters: cellSizeMeters) {
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
            return []
        }

        return newlyDiscovered
    }

    // MARK: - Query

    /// All landmarks visible within a coordinate region, for overlay rendering.
    func landmarks(in region: MKCoordinateRegion) -> [Landmark] {
        allLandmarks.filter { landmark in
            let lat = landmark.latitude
            let lon = landmark.longitude
            let latDelta = region.span.latitudeDelta / 2
            let lonDelta = region.span.longitudeDelta / 2
            return abs(lat - region.center.latitude) <= latDelta
                && abs(lon - region.center.longitude) <= lonDelta
        }
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
                                      cells: Set<CellID>,
                                      cellSizeMeters: Double) -> Bool {
        let landmarkLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        for cell in cells {
            let cellCenter = GridMath.center(for: cell, cellSizeMeters: cellSizeMeters)
            let cellLoc = CLLocation(latitude: cellCenter.latitude, longitude: cellCenter.longitude)
            if cellLoc.distance(from: landmarkLoc) <= radius {
                return true
            }
        }
        return false
    }
}
