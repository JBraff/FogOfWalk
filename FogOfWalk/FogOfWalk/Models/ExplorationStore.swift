import CoreData
import CoreLocation
import MapKit
import Observation

@MainActor
@Observable
final class ExplorationStore {
    private(set) var container: NSPersistentContainer

    /// Set if Core Data failed to load and could not recover. The app remains usable
    /// but exploration history will be empty until the user reinstalls.
    private(set) var loadError: Error?

    /// In-memory cache of visited cells for the active cell size — O(1) fog lookups.
    private(set) var visitedCellsCache: Set<CellID> = []
    /// In-memory cache of recently visited cells for the active highlight period.
    private(set) var recentCellsCache: Set<CellID> = []
    private(set) var totalVisitedCount: Int = 0
    private var cachedCellSize: Double = 0

    /// Called after a new cell is successfully persisted. Used by LocalityGeocoder.
    var onNewCell: ((VisitedCell) -> Void)?

    /// The Core Data view context. Use for queries in DiscoveryStatsModel and LocalityGeocoder.
    var viewContext: NSManagedObjectContext { container.viewContext }

    init() {
        let c = NSPersistentContainer(name: "FogOfWalk")
        let description = c.persistentStoreDescriptions.first ?? NSPersistentStoreDescription()
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        c.persistentStoreDescriptions = [description]
        container = c
        c.loadPersistentStores { [weak self] storeDescription, error in
            guard let error else { return }
            print("Core Data failed to load: \(error.localizedDescription). Attempting recovery.")

            if let url = storeDescription.url {
                // Back up the corrupt store before removing it so data is not
                // permanently destroyed by a transient failure (e.g. disk full).
                let backupURL = url.appendingPathExtension("bak")
                try? FileManager.default.copyItem(at: url, to: backupURL)
                try? FileManager.default.removeItem(at: url)
            }

            c.loadPersistentStores { _, retryError in
                if let retryError {
                    print("Core Data recovery failed: \(retryError.localizedDescription)")
                    self?.loadError = retryError
                }
            }
        }
        c.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// Testability hook — inject a pre-configured container (e.g. in-memory).
    init(container: NSPersistentContainer) {
        self.container = container
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    // MARK: - Cache Management

    /// Call on app launch and whenever the user changes cell size.
    func configure(cellSizeMeters: Double) {
        guard cellSizeMeters != cachedCellSize else { return }
        reloadCache(for: cellSizeMeters)
    }

    private func reloadCache(for cellSizeMeters: Double) {
        let request = NSFetchRequest<VisitedCell>(entityName: "VisitedCell")
        request.predicate = NSPredicate(format: "cellSizeMeters == %f", cellSizeMeters)
        do {
            let cells = try container.viewContext.fetch(request)
            visitedCellsCache = Set(cells.map { CellID(x: $0.cellX, y: $0.cellY) })
            totalVisitedCount = visitedCellsCache.count
            cachedCellSize    = cellSizeMeters  // only set on successful fetch
        } catch {
            print("ExplorationStore: cache reload failed: \(error)")
        }
    }

    // MARK: - Recent cells

    /// Populates `recentCellsCache` from Core Data using `cutoffDate`.
    /// Pass nil (for `.off`) to clear the cache.
    func loadRecentCells(since cutoffDate: Date?) {
        guard let cutoff = cutoffDate else {
            recentCellsCache = []
            return
        }
        guard cachedCellSize > 0 else { return }
        let request = NSFetchRequest<VisitedCell>(entityName: "VisitedCell")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "cellSizeMeters == %f", cachedCellSize),
            NSPredicate(format: "firstVisited >= %@", cutoff as NSDate)
        ])
        do {
            let cells = try container.viewContext.fetch(request)
            recentCellsCache = Set(cells.map { CellID(x: $0.cellX, y: $0.cellY) })
        } catch {
            print("ExplorationStore: recent cells load failed: \(error)")
            recentCellsCache = []
        }
    }

    // MARK: - Write

    /// Idempotent insert. Returns true when a new cell was recorded.
    @discardableResult
    func addCell(_ cell: CellID, cellSizeMeters: Double) -> Bool {
        let matchesCache = cellSizeMeters == cachedCellSize

        if matchesCache {
            guard !visitedCellsCache.contains(cell) else { return false }
        } else {
            // Cache tracks a different size; check Core Data directly for this size.
            let req = NSFetchRequest<VisitedCell>(entityName: "VisitedCell")
            req.predicate = NSPredicate(
                format: "cellX == %d AND cellY == %d AND cellSizeMeters == %f",
                cell.x, cell.y, cellSizeMeters)
            if (try? container.viewContext.count(for: req)) ?? 0 > 0 { return false }
        }

        let ctx    = container.viewContext
        let entity = VisitedCell(context: ctx)
        entity.cellX          = cell.x
        entity.cellY          = cell.y
        entity.cellSizeMeters = cellSizeMeters
        entity.firstVisited   = Date()

        do {
            try ctx.save()
            if matchesCache {
                visitedCellsCache.insert(cell)
                totalVisitedCount = visitedCellsCache.count
                // A newly walked cell is always "recent" while the highlight is active.
                if !recentCellsCache.isEmpty {
                    recentCellsCache.insert(cell)
                }
            }
            onNewCell?(entity)
            return true
        } catch {
            print("ExplorationStore: save failed: \(error)")
            ctx.rollback()
            return false
        }
    }

    func isVisited(_ cell: CellID) -> Bool {
        visitedCellsCache.contains(cell)
    }

    // MARK: - Query

    func visitedCells(in region: MKCoordinateRegion, cellSizeMeters: Double) -> Set<CellID> {
        // Filter the in-memory cache directly by bounds instead of materialising all
        // region cells into a [CellID] array (which can reach 10,000 elements per call).
        guard let b = GridMath.cellBounds(in: region, cellSizeMeters: cellSizeMeters) else {
            return []
        }
        return visitedCellsCache.filter { $0.x >= b.minX && $0.x <= b.maxX &&
                                          $0.y >= b.minY && $0.y <= b.maxY }
    }

    /// Visited cells inside a circle (city % numerator).
    func visitedCellCount(in circle: CLCircularRegion, cellSizeMeters: Double) -> Int {
        let center = CLLocation(latitude: circle.center.latitude, longitude: circle.center.longitude)
        return visitedCellsCache.lazy.filter { cell in
            let coord = GridMath.center(for: cell, cellSizeMeters: cellSizeMeters)
            return CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                .distance(from: center) <= circle.radius
        }.count
    }

    /// Total grid cells that fit inside a circle (city % denominator).
    func totalCellCount(in circle: CLCircularRegion, cellSizeMeters: Double) -> Int {
        let cosLat = cos(circle.center.latitude * .pi / 180)
        let span = MKCoordinateSpan(
            latitudeDelta:  (circle.radius / GridMath.metersPerDegree) * 2,
            longitudeDelta: (circle.radius / (GridMath.metersPerDegree * cosLat)) * 2
        )
        let region    = MKCoordinateRegion(center: circle.center, span: span)
        let circleLoc = CLLocation(latitude: circle.center.latitude, longitude: circle.center.longitude)
        return GridMath.cells(in: region, cellSizeMeters: cellSizeMeters).filter { cell in
            let coord = GridMath.center(for: cell, cellSizeMeters: cellSizeMeters)
            return CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                .distance(from: circleLoc) <= circle.radius
        }.count
    }

    // MARK: - Delete

    func deleteAllCells() {
        let isInMemory = container.persistentStoreCoordinator.persistentStores.contains {
            $0.type == NSInMemoryStoreType
        }

        var deleteSucceeded = false

        if !isInMemory {
            let request     = NSFetchRequest<NSFetchRequestResult>(entityName: "VisitedCell")
            let batchDelete = NSBatchDeleteRequest(fetchRequest: request)
            batchDelete.resultType = .resultTypeObjectIDs
            do {
                let result = try container.viewContext.execute(batchDelete) as? NSBatchDeleteResult
                let ids    = result?.result as? [NSManagedObjectID] ?? []
                NSManagedObjectContext.mergeChanges(
                    fromRemoteContextSave: [NSDeletedObjectsKey: ids],
                    into: [container.viewContext]
                )
                deleteSucceeded = true
            } catch {
                print("ExplorationStore: batch delete failed: \(error)")
            }
        } else {
            let fallback = NSFetchRequest<NSManagedObject>(entityName: "VisitedCell")
            do {
                let objects = try container.viewContext.fetch(fallback)
                objects.forEach { container.viewContext.delete($0) }
                try container.viewContext.save()
                deleteSucceeded = true
            } catch {
                print("ExplorationStore: in-memory delete failed: \(error)")
                container.viewContext.rollback()
            }
        }

        guard deleteSucceeded else { return }
        visitedCellsCache.removeAll()
        recentCellsCache.removeAll()
        totalVisitedCount = 0
        cachedCellSize    = 0
    }
}
