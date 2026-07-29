import CoreLocation
import MapKit
import Observation

// MARK: - EmptyLandmarkSource

/// Fallback when the bundled database is unavailable (e.g. missing from bundle).
struct EmptyLandmarkSource: LandmarkDataProviding {
    func landmarks(in region: MKCoordinateRegion) -> [WikidataLandmark] { [] }
}

// MARK: - LandmarkSearchService

/// Loads nearby landmarks from the bundled Wikidata database as the map region changes.
/// Rate-limited to avoid unnecessary SQLite work on every small pan gesture.
@MainActor
@Observable
final class LandmarkSearchService {

    // MARK: - Configuration

    private let minimumSearchInterval: TimeInterval = 30
    private let minimumCenterDelta: CLLocationDistance = 500

    // MARK: - State

    private var lastSearchCenter: CLLocationCoordinate2D?
    private var lastSearchTime: Date = .distantPast
    private var activeTask: Task<Void, Never>?

    // MARK: - Dependencies

    private let source: any LandmarkDataProviding

    // MARK: - Init

    init(source: any LandmarkDataProviding = EmptyLandmarkSource()) {
        self.source = source
    }

    /// Convenience initialiser that opens the bundled `landmarks.sqlite` database.
    @MainActor
    static func makeBundled() -> LandmarkSearchService {
        guard let url = Bundle.main.url(forResource: "landmarks", withExtension: "sqlite"),
              let bundledSource = try? BundledLandmarkSource(databaseURL: url)
        else {
            return LandmarkSearchService(source: EmptyLandmarkSource())
        }
        return LandmarkSearchService(source: bundledSource)
    }

    // MARK: - Public API

    /// Load landmarks for `region` into `landmarkStore` if enough time or distance has elapsed.
    ///
    /// `visitedCells` is threaded through to `addLandmarks` so a landmark ingested for ground
    /// the user has already walked is discovered immediately rather than waiting for them to
    /// walk a *new* cell nearby — which they may never do.
    func searchIfNeeded(region: MKCoordinateRegion,
                        landmarkStore: LandmarkStore,
                        visitedCells: Set<CellID>) {
        // Skip zoomed-out regions entirely. One pinch to world zoom would otherwise ingest
        // the whole bundled database into Core Data, where it stays forever and makes every
        // subsequent discovery check more expensive.
        //
        // This guard deliberately sits *above* the `lastSearchTime`/`lastSearchCenter` writes
        // below: a skipped wide zoom must not consume the rate-limit budget, or the next
        // legitimate walking-zoom query would be suppressed for `minimumSearchInterval`.
        let widestSpan = max(region.span.latitudeDelta, region.span.longitudeDelta)
        guard widestSpan <= GridMath.maxIngestSpanDegrees else { return }

        let now = Date()
        let timeSinceLast = now.timeIntervalSince(lastSearchTime)
        let distanceSinceLast: CLLocationDistance = {
            guard let last = lastSearchCenter else { return .greatestFiniteMagnitude }
            let a = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let b = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
            return a.distance(from: b)
        }()

        guard timeSinceLast >= minimumSearchInterval || distanceSinceLast >= minimumCenterDelta else {
            return
        }

        lastSearchTime   = now
        lastSearchCenter = region.center

        // This Task inherits the main actor, so the SQLite query and the Core Data insert both
        // run on the main thread. That is deliberate: bounded by the span guard above and the
        // query's LIMIT, this is ≤500 R-tree-indexed rows (244 in the worst real region) plus
        // one `save()` — well under a frame. Moving it off-actor would mean `@unchecked
        // Sendable`, a lock, and `NSManagedObjectID` round-tripping, because `allLandmarks`
        // hands managed objects straight to the UI.
        //
        // Gotcha for whoever tries anyway: with `SWIFT_APPROACHABLE_CONCURRENCY = YES` a plain
        // `nonisolated async func` called from a `@MainActor` context still runs on the
        // caller's actor. Reaching the global executor needs `@concurrent` or `Task.detached`.
        activeTask?.cancel()
        activeTask = Task {
            let items = source.landmarks(in: region)
            guard !Task.isCancelled else { return }
            landmarkStore.addLandmarks(items, visitedCells: visitedCells)
        }
    }
}
