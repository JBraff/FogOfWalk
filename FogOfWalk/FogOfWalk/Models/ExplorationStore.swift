import CoreData
import CoreLocation
import MapKit
import Observation

@MainActor
@Observable
final class ExplorationStore {
    private(set) var container: NSPersistentContainer

    /// Set if Core Data failed to load and recovery could not safely complete. The app stays
    /// open, but new exploration cannot be saved this launch.
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

    /// Set when the on-disk store could not be opened, whether recovery succeeded or stopped.
    /// The UI shows the storage outcome once per launch.
    private(set) var recoveryNotice: StoreRecoveryNotice?

    /// - Parameter storeURL: Overrides the default SQLite location. Tests use this to
    ///   exercise recovery against a real on-disk store.
    init(storeURL: URL? = nil,
         copyStoreFile: (URL, URL) throws -> Void = {
             try FileManager.default.copyItem(at: $0, to: $1)
         }) {
        let c = NSPersistentContainer(name: "FogOfWalk")
        let description = c.persistentStoreDescriptions.first ?? NSPersistentStoreDescription()
        if let storeURL { description.url = storeURL }
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        c.persistentStoreDescriptions = [description]
        container = c

        if let error = Self.loadStores(c) {
            loadError = error
            var backups: [URL] = []
            if let url = description.url {
                print("Core Data failed to load: \(error.localizedDescription). Attempting recovery.")
                do {
                    // Every existing file must be copied before any original is removed.
                    // In particular, the WAL may hold the only copy of recent visits.
                    backups = try Self.backUpStoreFiles(at: url, copyFile: copyStoreFile)
                    try c.persistentStoreCoordinator.destroyPersistentStore(at: url, type: .sqlite)
                    loadError = Self.loadStores(c)
                } catch {
                    // Stop on backup/reset failure. Do not fall back to deleting originals.
                    print("Core Data recovery stopped: \(error.localizedDescription)")
                    loadError = error
                }
            }
            recoveryNotice = StoreRecoveryNotice(backupURLs: backups, storeIsUsable: loadError == nil)
        }
        c.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// Call after the UI has shown `recoveryNotice` so it is not shown again this launch.
    func acknowledgeRecoveryNotice() {
        recoveryNotice = nil
    }

    /// Loads the container's stores synchronously (the SQLite default) and returns the
    /// first error, if any.
    private static func loadStores(_ container: NSPersistentContainer) -> Error? {
        final class ErrorBox { var error: Error? }
        let box = ErrorBox()
        container.loadPersistentStores { _, error in
            if let error, box.error == nil { box.error = error }
        }
        return box.error
    }

    /// The SQLite store file and its sidecars.
    static func storeFiles(at url: URL) -> [URL] {
        ["", "-wal", "-shm"].map { URL(fileURLWithPath: url.path + $0) }
    }

    /// Copies every existing store file to a unique sibling, without overwriting a backup.
    /// Throws on any inspection/copy failure; the caller must then preserve all originals.
    static func backUpStoreFiles(at url: URL, now: Date = Date(),
                                 copyFile: (URL, URL) throws -> Void = {
                                     try FileManager.default.copyItem(at: $0, to: $1)
                                 }) throws -> [URL] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fm = FileManager.default
        let suffixes = ["", "-wal", "-shm"]
        let timestamp = formatter.string(from: now)
        var stamp = timestamp
        while suffixes.contains(where: { fm.fileExists(atPath: url.path + ".corrupt-\(stamp)" + $0) }) {
            stamp = timestamp + "-" + UUID().uuidString
        }
        var copies: [URL] = []
        for (file, suffix) in zip(storeFiles(at: url), suffixes) {
            do {
                _ = try fm.attributesOfItem(atPath: file.path)
            } catch let error as NSError where error.domain == NSCocoaErrorDomain
                && error.code == NSFileReadNoSuchFileError {
                continue
            }
            let copy = URL(fileURLWithPath: url.path + ".corrupt-\(stamp)" + suffix)
            try copyFile(file, copy)
            copies.append(copy)
        }
        return copies
    }

    /// Testability hook — inject a pre-configured container (e.g. in-memory).
    init(container: NSPersistentContainer) {
        self.container = container
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    // MARK: - Cache Management

    /// Call on app launch to populate the in-memory cache from Core Data.
    func configure() {
        guard loadError == nil, !hasConfigured else { return }
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
        guard loadError == nil, !visitedCellsCache.contains(cell) else { return false }

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

    /// Merge-imports backup cell records. Inserts cells absent locally (matched by grid
    /// coordinate at the current cell size); for cells that already exist, keeps the earlier
    /// of the two `firstVisited` dates without touching `locality` — `state`/`country` are
    /// handled the same way, set only when a cell is newly inserted and never overwritten on
    /// merge for existing cells. Returns the number of newly inserted cells.
    ///
    /// Throws if the Core Data save fails, so a real failure is distinguishable from the
    /// legitimate "nothing new to merge" case (which returns 0). Fetch failures and the
    /// empty-input early return are not treated as failures — they aren't caused by this
    /// merge and there is nothing to roll back.
    @discardableResult
    func addCells(_ records: [BackupVisitedCell]) throws -> Int {
        if let loadError { throw loadError }
        guard !records.isEmpty else { return 0 }

        let ctx = container.viewContext
        let request = NSFetchRequest<VisitedCell>(entityName: "VisitedCell")
        request.predicate = NSPredicate(format: "cellSizeMeters == %f", kCellSizeMeters)
        let existing: [VisitedCell]
        do {
            existing = try ctx.fetch(request)
        } catch {
            print("ExplorationStore: addCells fetch failed: \(error)")
            return 0
        }

        var byID: [CellID: VisitedCell] = [:]
        for cell in existing {
            byID[CellID(x: cell.cellX, y: cell.cellY)] = cell
        }

        var addedCount = 0
        for record in records {
            let id = CellID(x: record.cellX, y: record.cellY)
            if let existingCell = byID[id] {
                if let imported = record.firstVisited,
                   let current = existingCell.firstVisited,
                   imported < current {
                    existingCell.firstVisited = imported
                }
                continue
            }

            let entity = VisitedCell(context: ctx)
            entity.cellX          = record.cellX
            entity.cellY          = record.cellY
            entity.cellSizeMeters = kCellSizeMeters
            entity.firstVisited   = record.firstVisited ?? nowProvider()
            entity.locality       = record.locality
            entity.state          = record.state
            entity.country        = record.country
            byID[id] = entity
            addedCount += 1
        }

        guard ctx.hasChanges else { return 0 }

        do {
            try ctx.save()
        } catch {
            print("ExplorationStore: addCells save failed: \(error)")
            ctx.rollback()
            throw error
        }

        reloadCache()
        return addedCount
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
        guard loadError == nil else { return }
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

/// Describes the outcome after a store failed to open.
struct StoreRecoveryNotice: Equatable {
    /// Complete backup copies, when all existing files were successfully copied.
    let backupURLs: [URL]
    /// False when recovery stopped or the fresh store failed to open.
    let storeIsUsable: Bool
}
