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
    func searchIfNeeded(region: MKCoordinateRegion, landmarkStore: LandmarkStore) {
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

        activeTask?.cancel()
        activeTask = Task {
            let items = source.landmarks(in: region)
            guard !Task.isCancelled else { return }
            landmarkStore.addLandmarks(items)
        }
    }
}
