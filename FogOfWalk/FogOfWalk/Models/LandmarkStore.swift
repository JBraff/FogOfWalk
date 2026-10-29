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
    /// Includes count-neutral edits and reloads, not just insertions and discoveries.
    private(set) var renderGeneration: UInt64 = 0
    @ObservationIgnored private var contextChangeObserver: NSObjectProtocol?

    private var knownIdentifiers: Set<String> = []

    /// Undiscovered landmarks indexed by the coarse bucket containing them, so a newly walked
    /// cell can find its candidates without touching the other ~15,000 rows. Rebuilt by
    /// `loadFromStore()`; entries are removed as landmarks become discovered.
    private var undiscoveredBuckets: [BucketKey: [Landmark]] = [:]

    /// Count of cell/landmark pairs examined by the last `checkDiscovery` call.
    ///
    /// A test seam: complexity is not observable in a return value, so the only way to pin the
    /// asymptotics is to count the work. Declared unconditionally and `@ObservationIgnored` —
    /// a tracked property incremented once per probe would fire an observation notification
    /// thousands of times per location update, inside the very loop being measured.
    @ObservationIgnored private(set) var lastDiscoveryProbeCount: Int = 0

    /// Buckets whose bundled landmarks have already been ingested by `ingestLandmarks(near:)`
    /// this launch, so walking stays at one SQLite query per ~1.6 km bucket.
    @ObservationIgnored private var ingestedBuckets: Set<BucketKey> = []

    // MARK: - Spatial bucketing

    /// Coarse spatial key covering 32x32 cells (~1600 m of latitude).
    struct BucketKey: Hashable {
        let bx: Int32
        let by: Int32
    }

    /// The one and only quantizer. Both sides of every bucket comparison must go through this,
    /// or a landmark and the cell that should discover it can land in different buckets.
    ///
    /// `>>` rather than `/ 32` because integer division truncates toward zero, which would map
    /// x = -31...-1 and x = 0...31 into the same bucket and make it twice as wide. That is a
    /// performance wart rather than a correctness bug — correctness only needs both sides to
    /// quantize identically — but there is no reason to accept it.
    static func bucket(for cell: CellID) -> BucketKey {
        BucketKey(bx: cell.x >> 5, by: cell.y >> 5)
    }

    /// Largest discovery radius across all categories.
    ///
    /// Derived rather than hardcoded: in the cell→landmark direction a candidate's own radius
    /// is unknown until it has been found, so the search must use the maximum. Reading it from
    /// `categoryRadius` means adding a category can never silently shrink the search.
    static let maxDiscoveryRadius: Double = categoryRadius.values.max() ?? 100

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
    private let defaults: UserDefaults?

    // MARK: - Init

    init(container: NSPersistentContainer, defaults: UserDefaults? = .standard) {
        self.container = container
        self.defaults = defaults
        purgeNonWikidataLandmarksIfNeeded()
        loadFromStore()
        contextChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange, object: container.viewContext, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey,
                            NSRefreshedObjectsKey, NSInvalidatedObjectsKey]
                let changed = notification.userInfo?[NSInvalidatedAllObjectsKey] != nil
                    || keys.contains { key in
                        guard let objects = notification.userInfo?[key] as? NSSet else { return false }
                        for object in objects where object is Landmark { return true }
                        return false
                    }
                if changed { self?.renderGeneration &+= 1 }
            }
        }
    }

    deinit {
        if let contextChangeObserver { NotificationCenter.default.removeObserver(contextChangeObserver) }
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

    /// Reloads every cached derivation of the persisted rows, including the bucket index.
    ///
    /// This is the single rebuild point for `undiscoveredBuckets`: `init` and every rollback
    /// path route through here. The only incremental updates are the removal in `discover`
    /// and the append of freshly saved rows in `persistLandmarks`, which runs during walks and
    /// must not refetch every stored landmark per new bucket.
    private func loadFromStore() {
        let request = Landmark.fetchRequest()
        guard let results = try? container.viewContext.fetch(request) else { return }
        renderGeneration &+= 1
        allLandmarks = results
        knownIdentifiers = Set(results.map { $0.identifier })
        totalDiscovered = results.filter { $0.isDiscovered }.count

        undiscoveredBuckets = [:]
        for landmark in results where !landmark.isDiscovered {
            undiscoveredBuckets[bucket(for: landmark), default: []].append(landmark)
        }
    }

    // MARK: - Write

    /// Persist landmarks from the bundled Wikidata dataset. Deduplicates by identifier.
    ///
    /// `visitedCells` has no default on purpose. A newly inserted landmark covering ground the
    /// user already walked must be discovered immediately, and a defaulted empty set would let
    /// any forgetful call site silently drop those discoveries — the same class of bug this
    /// method's sweep exists to prevent. Tests that genuinely don't care pass `[]` through the
    /// `seed` helper, where the intent is visible.
    ///
    /// Returns the landmarks discovered by the post-insert sweep.
    @discardableResult
    func addLandmarks(_ items: [WikidataLandmark], visitedCells: Set<CellID>) -> [Landmark] {
        do {
            return try persistLandmarks(items, visitedCells: visitedCells)
        } catch {
            print("LandmarkStore: save failed: \(error)")
            return []
        }
    }

    /// Throws only when insertion fails, so walk-time ingest can leave its buckets retryable.
    private func persistLandmarks(_ items: [WikidataLandmark],
                                  visitedCells: Set<CellID>) throws -> [Landmark] {
        let ctx = container.viewContext
        var inserted: [Landmark] = []
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
            inserted.append(entity)
        }

        guard !inserted.isEmpty else { return [] }

        do {
            try ctx.save()
            allLandmarks.append(contentsOf: inserted)
            for landmark in inserted {
                undiscoveredBuckets[bucket(for: landmark), default: []].append(landmark)
            }
        } catch {
            ctx.rollback()
            // Discard identifiers added before the failed save, preserving persisted rows.
            loadFromStore()
            throw error
        }

        // Sweep only the rows just inserted, not every undiscovered landmark. Only new rows can
        // produce a new discovery here, and sweeping everything straight after a bulk insert
        // would reintroduce the O(landmarks x cells) cost at the worst possible moment.
        guard !visitedCells.isEmpty else { return [] }
        return discover(among: inserted, visitedCells: visitedCells)
    }

    /// Ingests bundled landmarks that could be discovered from `cell`, then sweeps them
    /// against `visitedCells`. Returns the landmarks that sweep discovered.
    ///
    /// Map panning is otherwise the only ingest path, so without this a walk through an area
    /// never shown on the map (phone in a pocket, Study recording with no map) discovers
    /// nothing until the area is viewed, and then records the viewing time as the discovery.
    /// Successful bucket ingests are cached per launch; failed inserts remain retryable and
    /// throw, so callers can tell a failure from an area with no landmarks.
    @discardableResult
    func ingestLandmarks(near cell: CellID,
                         from source: any LandmarkDataProviding,
                         visitedCells: Set<CellID>) throws -> [Landmark] {
        let box = GridMath.cellBox(around: GridMath.center(for: cell),
                                   radiusMeters: Self.maxDiscoveryRadius)
        let minBX = box.minX >> 5, maxBX = box.maxX >> 5
        let minBY = box.minY >> 5, maxBY = box.maxY >> 5
        var keys: [BucketKey] = []
        for by in minBY...maxBY {
            for bx in minBX...maxBX { keys.append(BucketKey(bx: bx, by: by)) }
        }
        guard keys.contains(where: { !ingestedBuckets.contains($0) }) else { return [] }

        // Query the whole buckets so marking them ingested is accurate.
        let bucketDegrees = 32 * kCellSizeMeters / GridMath.metersPerDegree
        let minLat = Double(minBY) * bucketDegrees, maxLat = Double(Int(maxBY) + 1) * bucketDegrees
        let minLon = Double(minBX) * bucketDegrees, maxLon = Double(Int(maxBX) + 1) * bucketDegrees
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: maxLat - minLat,
                                   longitudeDelta: maxLon - minLon))
        let items = source.landmarks(in: region)
        let discovered = try persistLandmarks(items, visitedCells: visitedCells)
        ingestedBuckets.formUnion(keys)
        return discovered
    }

    /// Merge-imports discovered-landmark state from a backup. For each record whose
    /// `identifier` matches a landmark known locally, marks it discovered and keeps the
    /// earlier of the existing/imported `firstDiscovered` date. Records whose identifier has
    /// no local match (e.g. bundled reference data differs between devices) are skipped
    /// without error. Returns the number of landmarks newly marked discovered.
    ///
    /// Throws if the Core Data save fails, so a real failure is distinguishable from the
    /// legitimate "nothing new to merge" case (which returns 0).
    @discardableResult
    func restoreDiscovered(_ records: [(identifier: String, firstDiscovered: Date)]) throws -> Int {
        guard !records.isEmpty else { return 0 }

        var byIdentifier: [String: Landmark] = [:]
        for landmark in allLandmarks {
            byIdentifier[landmark.identifier] = landmark
        }

        let ctx = container.viewContext
        var newlyDiscoveredCount = 0
        var touched: [Landmark] = []

        for record in records {
            guard let landmark = byIdentifier[record.identifier] else { continue }

            if landmark.isDiscovered {
                if let current = landmark.firstDiscovered, record.firstDiscovered < current {
                    landmark.firstDiscovered = record.firstDiscovered
                    touched.append(landmark)
                }
            } else {
                landmark.isDiscovered = true
                landmark.firstDiscovered = record.firstDiscovered
                touched.append(landmark)
                newlyDiscoveredCount += 1
            }
        }

        guard !touched.isEmpty else { return 0 }

        do {
            try ctx.save()
        } catch {
            print("LandmarkStore: restoreDiscovered save failed: \(error)")
            ctx.rollback()
            loadFromStore()
            throw error
        }

        loadFromStore()
        return newlyDiscoveredCount
    }

    // MARK: - Discovery

    /// Discovery triggered by one newly walked cell. This is the hot path — it runs on every
    /// 50 m of walking, so its cost must not depend on how much the user has explored.
    ///
    /// Given a single new cell, only landmarks within `maxDiscoveryRadius` of it can possibly
    /// become discoverable, so this looks them up in the bucket index and never touches the
    /// visited set at all. Note there is no cell probing in this direction — do not add any.
    @discardableResult
    func checkDiscovery(newCell cell: CellID) -> [Landmark] {
        lastDiscoveryProbeCount = 0
        guard !undiscoveredBuckets.isEmpty else { return [] }

        let centre = GridMath.center(for: cell)
        let box    = GridMath.cellBox(around: centre, radiusMeters: Self.maxDiscoveryRadius)

        var candidates: [Landmark] = []
        for by in (box.minY >> 5)...(box.maxY >> 5) {
            for bx in (box.minX >> 5)...(box.maxX >> 5) {
                if let bucket = undiscoveredBuckets[BucketKey(bx: bx, by: by)] {
                    candidates.append(contentsOf: bucket)
                }
            }
        }
        guard !candidates.isEmpty else { return [] }

        return discover(among: candidates, visitedCells: [cell])
    }

    /// Full sweep of every undiscovered landmark against the whole visited set.
    ///
    /// Kept for the paths where the cell→landmark direction cannot apply: the launch sweep, and
    /// callers that hold a visited set rather than a single new cell. Bucket-prefiltered, so it
    /// is no longer O(undiscovered x visited).
    @discardableResult
    func checkDiscovery(visitedCells: Set<CellID>) -> [Landmark] {
        lastDiscoveryProbeCount = 0
        guard !visitedCells.isEmpty, !undiscoveredBuckets.isEmpty else { return [] }

        // One pass over the visited set to learn which buckets are occupied, then a handful of
        // Set lookups per landmark to reject the ones with no walked ground anywhere near.
        var occupied: Set<BucketKey> = []
        for cell in visitedCells { occupied.insert(Self.bucket(for: cell)) }

        var candidates: [Landmark] = []
        for landmarks in undiscoveredBuckets.values {
            for landmark in landmarks {
                let coord = CLLocationCoordinate2D(latitude: landmark.latitude,
                                                   longitude: landmark.longitude)
                let box = GridMath.cellBox(around: coord,
                                           radiusMeters: landmark.discoveryRadiusMeters)
                var nearby = false
                for by in (box.minY >> 5)...(box.maxY >> 5) where !nearby {
                    for bx in (box.minX >> 5)...(box.maxX >> 5) {
                        if occupied.contains(BucketKey(bx: bx, by: by)) { nearby = true; break }
                    }
                }
                if nearby { candidates.append(landmark) }
            }
        }

        return discover(among: candidates, visitedCells: visitedCells)
    }

    /// Full sweep under an intention-revealing name, for the once-per-launch self-heal.
    ///
    /// This must run on every launch, not once behind a UserDefaults flag: when `discover`'s
    /// `save()` fails it rolls back, reverting `isDiscovered`, and that cell will never be
    /// "new" again — so without a launch sweep the discovery would be lost permanently.
    ///
    /// Deliberately synchronous and not called from `init`: `init` receives only an
    /// `NSPersistentContainer` and has no route to the visited set, and a sweep fired into a
    /// detached Task from there would race with construction in tests.
    @discardableResult
    func sweepAllUndiscovered(visitedCells: Set<CellID>) -> [Landmark] {
        checkDiscovery(visitedCells: visitedCells)
    }

    /// Precise check, mutation and persistence for an already-narrowed candidate list.
    @discardableResult
    private func discover(among candidates: [Landmark],
                          visitedCells: Set<CellID>) -> [Landmark] {
        var newlyDiscovered: [Landmark] = []
        let ctx = container.viewContext

        for landmark in candidates where !landmark.isDiscovered {
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
            for landmark in newlyDiscovered { removeFromUndiscoveredIndex(landmark) }
        } catch {
            print("LandmarkStore: discovery save failed: \(error)")
            ctx.rollback()
            // After rollback the managed objects may have stale in-memory state. Reload from
            // Core Data so allLandmarks reflects the persisted truth — which also rebuilds the
            // bucket index, returning the rolled-back landmarks to it so the next launch sweep
            // retries them.
            loadFromStore()
            return []
        }

        return newlyDiscovered
    }

    private func bucket(for landmark: Landmark) -> BucketKey {
        Self.bucket(for: GridMath.cellID(for: CLLocationCoordinate2D(
            latitude: landmark.latitude,
            longitude: landmark.longitude
        )))
    }

    private func removeFromUndiscoveredIndex(_ landmark: Landmark) {
        let key = bucket(for: landmark)
        guard var landmarks = undiscoveredBuckets[key] else { return }
        landmarks.removeAll { $0.identifier == landmark.identifier }
        if landmarks.isEmpty {
            undiscoveredBuckets.removeValue(forKey: key)
        } else {
            undiscoveredBuckets[key] = landmarks
        }
    }

    // MARK: - Query

    /// Cap on installed landmark annotations, including the offscreen buffer.
    /// Candidate queries still scan all stored rows before applying this limit.
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

    /// One pass keeps the existing visible selection and fills spare slots from a 2x
    /// buffer. Candidate arrays are bounded; padding never expands ingest requests.
    func landmarksForDisplay(in region: MKCoordinateRegion) -> [Landmark] {
        let limit = Self.maxRenderedPins
        var visible: [Landmark] = [], visibleDiscovered: [Landmark] = [], visibleHints: [Landmark] = []
        var bufferDiscovered: [Landmark] = [], bufferHints: [Landmark] = []
        var visibleCount = 0
        for landmark in allLandmarks {
            let latitudeDelta = abs(landmark.latitude - region.center.latitude)
            let longitudeDelta = abs(landmark.longitude - region.center.longitude)
            guard latitudeDelta <= region.span.latitudeDelta,
                  longitudeDelta <= region.span.longitudeDelta else { continue }
            if latitudeDelta <= region.span.latitudeDelta / 2
                && longitudeDelta <= region.span.longitudeDelta / 2 {
                visibleCount += 1
                if visible.count < limit { visible.append(landmark) }
                if landmark.isDiscovered {
                    if visibleDiscovered.count < limit { visibleDiscovered.append(landmark) }
                } else if visibleHints.count < limit { visibleHints.append(landmark) }
            } else if landmark.isDiscovered {
                if bufferDiscovered.count < limit { bufferDiscovered.append(landmark) }
            } else if bufferHints.count < limit { bufferHints.append(landmark) }
        }
        // Below the cap preserve the legacy query's original order, including mixed hints.
        var result = visibleCount <= limit ? visible
            : visibleDiscovered + visibleHints.prefix(limit - visibleDiscovered.count)
        result.append(contentsOf: bufferDiscovered.prefix(limit - result.count))
        result.append(contentsOf: bufferHints.prefix(limit - result.count))
        return result
    }

    // MARK: - Migration

    /// Deletes any landmarks whose identifier is not a Wikidata QID (`Q` + digits).
    /// Guarded by a UserDefaults flag that is set only once the purge has succeeded, so a
    /// launch whose store failed to open retries on the next launch. With no store loaded a
    /// fetch returns nothing rather than throwing, so that case is checked explicitly.
    private func purgeNonWikidataLandmarksIfNeeded() {
        guard !(defaults?.bool(forKey: Self.wikidataMigrationKey) ?? false) else { return }
        guard !container.persistentStoreCoordinator.persistentStores.isEmpty else { return }

        let ctx = container.viewContext
        let request = Landmark.fetchRequest()
        // Keep only identifiers that match the Wikidata QID pattern: Q followed by digits.
        request.predicate = NSPredicate(format: "NOT (identifier MATCHES %@)", "Q[0-9]+")
        do {
            let old = try ctx.fetch(request)
            if !old.isEmpty {
                old.forEach { ctx.delete($0) }
                try ctx.save()
            }
            defaults?.set(true, forKey: Self.wikidataMigrationKey)
        } catch {
            ctx.rollback()
            print("LandmarkStore: Wikidata migration deferred: \(error)")
        }
    }

    // MARK: - Private helpers

    private func isWithinVisitedCells(coord: CLLocationCoordinate2D,
                                      radius: Double,
                                      cells: Set<CellID>) -> Bool {
        let box = GridMath.cellBox(around: coord, radiusMeters: radius)

        // Squared equirectangular distance rather than `CLLocation.distance(from:)`: this is
        // the innermost loop of discovery, and the geodesic version allocates two ObjC
        // objects and crosses into CoreLocation per candidate. More importantly it shares
        // `metersPerDegree` with `cellBox` above, so the prefilter and the precise check
        // agree about what a metre is — mixing WGS84 geodesics with a 111111 m/deg box is
        // what allowed the original bug to hide. The delta against WGS84 is ~0.1-0.5%, well
        // inside the discovery radii.
        let cosLat      = cos(coord.latitude * .pi / 180.0)
        let radiusSq    = radius * radius
        let landmarkLat = coord.latitude
        let landmarkLon = coord.longitude

        func isWithin(_ cell: CellID) -> Bool {
            let center = GridMath.center(for: cell)
            let dLat = (center.latitude  - landmarkLat) * GridMath.metersPerDegree
            let dLon = (center.longitude - landmarkLon) * GridMath.metersPerDegree * cosLat
            return dLat * dLat + dLon * dLon <= radiusSq
        }

        // Two ways to intersect the visited set with the box, both exact. Pick whichever has
        // less work to do:
        //
        //  - Probing generated CellIDs costs O(cells in box) and is independent of how much
        //    the user has explored. That independence is the point — it is what keeps the
        //    per-step cost flat as the visited set grows into the tens of thousands.
        //  - Iterating the visited set costs O(visited cells) and wins when the user has
        //    barely explored, which is also the case where a large radius at high latitude
        //    makes the box biggest. Without this branch the "fix" would be a regression for
        //    new users.
        //
        // `lastDiscoveryProbeCount` counts every cell *considered* in either branch, not just
        // the ones reaching the distance check, so it reflects the real work done. That makes
        // it a usable complexity assertion: it is bounded by min(visited count, box size), and
        // it is the only way to observe a complexity regression — a purely behavioural test
        // cannot, because the slow implementation produced the correct answer too.
        let probeCount = (Int(box.maxX) - Int(box.minX) + 1) * (Int(box.maxY) - Int(box.minY) + 1)

        if cells.count < probeCount {
            for cell in cells {
                #if DEBUG
                lastDiscoveryProbeCount += 1
                #endif
                guard cell.x >= box.minX, cell.x <= box.maxX,
                      cell.y >= box.minY, cell.y <= box.maxY else { continue }
                if isWithin(cell) { return true }
            }
            return false
        }

        for y in box.minY...box.maxY {
            for x in box.minX...box.maxX {
                #if DEBUG
                lastDiscoveryProbeCount += 1
                #endif
                let cell = CellID(x: x, y: y)
                guard cells.contains(cell) else { continue }
                if isWithin(cell) { return true }
            }
        }
        return false
    }
}
