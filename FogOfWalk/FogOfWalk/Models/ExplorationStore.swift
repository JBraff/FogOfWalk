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

    /// In-memory cache of visited cells — O(1) fog lookups.
    private(set) var visitedCellsCache: Set<CellID> = []
    /// In-memory cache of recently visited cells for the active highlight period.
    private(set) var recentCellsCache: Set<CellID> = []
    /// Monotonically increasing counter — increments on every `loadRecentCells` call
    /// so `MapContainerView.updateUIView` can detect highlight changes even when the
    /// cell count is unchanged (e.g., toggling on/off with 0 cells today).
    private(set) var recentCellsGeneration: UInt64 = 0
    private(set) var totalVisitedCount: Int = 0
    private(set) var todayVisitedCount: Int = 0
    private var hasConfigured = false
    /// True when highlighting is active (loadRecentCells was called with a non-nil date).
    /// Used by addCell to insert new cells into recentCellsCache even when the cache is
    /// currently empty (e.g., early in the day before any cells are visited).
    private var isHighlightActive = false

    /// Injectable clock, required to test day-rollover behavior deterministically.
    var nowProvider: () -> Date = { Date() }
    /// The calendar day (start-of-day) the caches were last computed for.
    /// `.distantPast` forces the first refresh to do a real recount.
    private var cacheDay: Date = .distantPast

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

    /// Call on app launch to populate the in-memory cache from Core Data.
    func configure() {
        guard !hasConfigured else { return }
        reloadCache()
    }

    private func reloadCache() {
        let request = NSFetchRequest<VisitedCell>(entityName: "VisitedCell")
        request.predicate = NSPredicate(format: "cellSizeMeters == %f", kCellSizeMeters)
        do {
            let cells = try container.viewContext.fetch(request)
            visitedCellsCache = Set(cells.map { CellID(x: $0.cellX, y: $0.cellY) })
            totalVisitedCount = visitedCellsCache.count
            hasConfigured     = true

            let startOfToday = Calendar.current.startOfDay(for: nowProvider())
            todayVisitedCount = fetchTodayCount(since: startOfToday)
            cacheDay          = startOfToday
        } catch {
            print("ExplorationStore: cache reload failed: \(error)")
        }
    }

    private func fetchTodayCount(since startOfToday: Date) -> Int {
        let todayRequest = NSFetchRequest<VisitedCell>(entityName: "VisitedCell")
        todayRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "cellSizeMeters == %f", kCellSizeMeters),
            NSPredicate(format: "firstVisited >= %@", startOfToday as NSDate)
        ])
        return (try? container.viewContext.count(for: todayRequest)) ?? 0
    }

    /// Call on every plausible "time may have advanced" trigger (new location, scene
    /// becoming active, calendar day change notification). Cheap no-op within the same
    /// day. Returns whether a rollover actually happened, since backgrounded callers
    /// (no view update in flight) need to know whether to force a fog repaint.
    @discardableResult
    func refreshForDayChangeIfNeeded() -> Bool {
        guard hasConfigured else { return false }
        let today = Calendar.current.startOfDay(for: nowProvider())
        guard today != cacheDay else { return false }

        todayVisitedCount = fetchTodayCount(since: today)
        cacheDay          = today
        if isHighlightActive {
            loadRecentCells(since: today)
        }
        return true
    }

    // MARK: - Recent cells

    /// Populates `recentCellsCache` from Core Data using `cutoffDate`.
    /// Pass nil (for `.off`) to clear the cache.
    func loadRecentCells(since cutoffDate: Date?) {
        guard let cutoff = cutoffDate else {
            recentCellsCache = []
            isHighlightActive = false
            recentCellsGeneration &+= 1
            return
        }
        guard hasConfigured else { return }
        let request = NSFetchRequest<VisitedCell>(entityName: "VisitedCell")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "cellSizeMeters == %f", kCellSizeMeters),
            NSPredicate(format: "firstVisited >= %@", cutoff as NSDate)
        ])
        do {
            let cells = try container.viewContext.fetch(request)
            recentCellsCache = Set(cells.map { CellID(x: $0.cellX, y: $0.cellY) })
            isHighlightActive = true
            recentCellsGeneration &+= 1
        } catch {
            print("ExplorationStore: recent cells load failed: \(error)")
            recentCellsCache = []
            isHighlightActive = false
            recentCellsGeneration &+= 1
        }
    }

    // MARK: - Write

    /// Idempotent insert. Returns true when a new cell was recorded.
    @discardableResult
    func addCell(_ cell: CellID) -> Bool {
        guard !visitedCellsCache.contains(cell) else { return false }

        let ctx    = container.viewContext
        let entity = VisitedCell(context: ctx)
        entity.cellX          = cell.x
        entity.cellY          = cell.y
        entity.cellSizeMeters = kCellSizeMeters
        entity.firstVisited   = nowProvider()

        do {
            try ctx.save()
            visitedCellsCache.insert(cell)
            totalVisitedCount = visitedCellsCache.count
            todayVisitedCount += 1
            // A newly walked cell is always "recent" while the highlight is active.
            // Use the isHighlightActive flag rather than recentCellsCache.isEmpty so that
            // cells are tracked even when the cache is empty (e.g., early in the day).
            if isHighlightActive {
                recentCellsCache.insert(cell)
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

    /// Visited cells inside a circle (city % numerator).
    func visitedCellCount(in circle: CLCircularRegion) -> Int {
        let center = CLLocation(latitude: circle.center.latitude, longitude: circle.center.longitude)
        return visitedCellsCache.lazy.filter { cell in
            let coord = GridMath.center(for: cell)
            return CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                .distance(from: center) <= circle.radius
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
        isHighlightActive = false
        recentCellsGeneration &+= 1
        totalVisitedCount = 0
        todayVisitedCount = 0
        hasConfigured     = false
        cacheDay          = .distantPast
    }
}
