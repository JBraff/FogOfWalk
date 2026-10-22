import CoreData
import CoreLocation
import MapKit
import Observation

// MARK: - Protocol (enables mock injection in tests)

protocol GeocoderProtocol {
    func reverseGeocodeLocation(_ location: CLLocation) async throws -> [CLPlacemark]
}

extension CLGeocoder: GeocoderProtocol {}

// MARK: - LocalityGeocoder

@MainActor
@Observable
final class LocalityGeocoder {

    // MARK: - Private types

    private struct PendingCluster {
        let coord: CLLocationCoordinate2D
        let objectIDs: [NSManagedObjectID]
        let context: NSManagedObjectContext
        /// Launch backfill work, which yields to newly walked cells (see `enqueue`).
        let isBackfill: Bool
    }

    private struct BucketKey: Hashable {
        let lat: Int
        let lon: Int
    }

    // MARK: - State

    private var queue: [PendingCluster] = []
    private var isProcessing = false
    /// Guards against re-enqueuing untagged cells on every app foreground.
    private var hasBackfilled = false

    /// Maximum number of pending clusters, so the queue cannot grow unboundedly when many
    /// cells are untagged. Backfill may fill it, but a newly walked cell then displaces the
    /// newest backfill cluster; only a queue full of walked cells drops new ones.
    static let maxQueueSize = 200

    /// Backfill cluster size in degrees (~1.1 km of latitude). Every untagged cell in a cluster
    /// receives the representative cell's placemark, so this must stay well below town scale:
    /// at 0.5° (~55 km) a whole region was labelled with one town's name. Clusters beyond
    /// `maxQueueSize` are picked up on later launches, since their cells stay untagged.
    static let backfillClusterDegrees = 0.01

    // MARK: - Dependencies

    private let geocoder: any GeocoderProtocol
    let requestDelay: Duration

    // MARK: - Init

    init(geocoder: any GeocoderProtocol = CLGeocoder(), requestDelay: Duration = .seconds(1)) {
        self.geocoder = geocoder
        self.requestDelay = requestDelay
    }

    // MARK: - Public API

    /// Enqueue a single newly-discovered cell for geocoding. It is queued ahead of any
    /// launch backfill, and when the queue is full it displaces the newest backfill cluster,
    /// whose cells stay untagged and are retried on a later launch.
    func enqueue(_ cell: VisitedCell) {
        guard cell.locality == nil || Self.resolvedCountry(cell.country) == nil else { return }
        guard let ctx = cell.managedObjectContext else { return }
        let coord = GridMath.center(for: CellID(x: cell.cellX, y: cell.cellY))
        if queue.count >= Self.maxQueueSize {
            guard let last = queue.lastIndex(where: { $0.isBackfill }) else { return }
            queue.remove(at: last)
        }
        let index = queue.firstIndex(where: { $0.isBackfill }) ?? queue.endIndex
        queue.insert(PendingCluster(coord: coord, objectIDs: [cell.objectID], context: ctx,
                                    isBackfill: false), at: index)
        processNext()
    }

    /// Backfill all untagged cells for the given cell size, clustering nearby cells to minimise geocode requests.
    /// Runs at most once per app lifecycle — repeated calls (e.g. on app foreground) are no-ops.
    func geocodeUntaggedCells(context: NSManagedObjectContext) {
        guard !hasBackfilled else { return }
        hasBackfilled = true
        let request = VisitedCell.fetchRequest()
        request.predicate = NSPredicate(
            format: "cellSizeMeters == %f AND (locality == nil OR state == nil OR country == nil OR country ==[c] 'Unknown' OR country == '')",
            kCellSizeMeters
        )
        guard let cells = try? context.fetch(request), !cells.isEmpty else { return }

        // Group nearby cells to limit CLGeocoder requests without crossing town boundaries.
        var buckets: [BucketKey: [VisitedCell]] = [:]
        for cell in cells {
            let coord = GridMath.center(for: CellID(x: cell.cellX, y: cell.cellY))
            let key = BucketKey(
                lat: Int(floor(coord.latitude / Self.backfillClusterDegrees)),
                lon: Int(floor(coord.longitude / Self.backfillClusterDegrees))
            )
            buckets[key, default: []].append(cell)
        }

        for (_, group) in buckets {
            guard let rep = group.first else { continue }
            guard queue.count < Self.maxQueueSize else { break }
            let coord = GridMath.center(for: CellID(x: rep.cellX, y: rep.cellY))
            queue.append(PendingCluster(
                coord: coord,
                objectIDs: group.map { $0.objectID },
                context: context,
                isBackfill: true
            ))
        }

        processNext()
    }

    /// The trimmed country name, or nil for a missing, blank, or legacy "Unknown" label.
    /// Shared with `DiscoveryStatsModel` so statistics and retries agree on what is unresolved.
    static func resolvedCountry(_ raw: String?) -> String? {
        guard let country = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !country.isEmpty,
              country.caseInsensitiveCompare("Unknown") != .orderedSame else { return nil }
        return country
    }

    // MARK: - Private

    private func processNext() {
        guard !isProcessing, !queue.isEmpty else { return }
        isProcessing = true
        let cluster = queue.removeFirst()
        // Strong capture is intentional: the task must run to completion even if the caller
        // released its reference (e.g. in tests). The task is short-lived — no retain cycle.
        Task {
            await geocodeCluster(cluster)
            if requestDelay > .zero {
                try? await Task.sleep(for: requestDelay)
            }
            isProcessing = false
            processNext()
        }
    }

    private func geocodeCluster(_ cluster: PendingCluster) async {
        let location = CLLocation(latitude: cluster.coord.latitude, longitude: cluster.coord.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let p = placemarks.first else { return }
            let name    = p.locality ?? p.subAdministrativeArea ?? p.administrativeArea ?? "Unknown"
            let state   = p.administrativeArea ?? "Unknown"
            let country = Self.resolvedCountry(p.country)
            let ctx = cluster.context
            for id in cluster.objectIDs {
                guard let cell = try? ctx.existingObject(with: id) as? VisitedCell else { continue }
                if cell.locality == nil { cell.locality = name }
                if cell.state    == nil { cell.state    = state }
                // Missing countries must remain retryable, including the old Unknown sentinel.
                // Never replace an existing known country with a clustered lookup. Trade-off:
                // a cluster Apple never assigns a country (open water) is re-requested on each
                // launch, bounded by `maxQueueSize`.
                if let country, Self.resolvedCountry(cell.country) == nil {
                    cell.country = country
                }
            }
            try? ctx.save()
        } catch {
            // Silently swallow — cells stay nil and will be retried on next launch.
        }
    }
}
