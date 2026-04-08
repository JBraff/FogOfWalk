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

    /// Maximum number of pending clusters. New enqueues beyond this limit are dropped
    /// to prevent the queue from growing unboundedly when many cells are untagged.
    static let maxQueueSize = 200

    // MARK: - Dependencies

    private let geocoder: any GeocoderProtocol
    let requestDelay: Duration

    // MARK: - Init

    init(geocoder: any GeocoderProtocol = CLGeocoder(), requestDelay: Duration = .seconds(1)) {
        self.geocoder = geocoder
        self.requestDelay = requestDelay
    }

    // MARK: - Public API

    /// Enqueue a single newly-discovered cell for geocoding.
    func enqueue(_ cell: VisitedCell) {
        guard cell.locality == nil else { return }
        guard let ctx = cell.managedObjectContext else { return }
        let coord = GridMath.center(for: CellID(x: cell.cellX, y: cell.cellY))
        guard queue.count < Self.maxQueueSize else { return }
        queue.append(PendingCluster(coord: coord, objectIDs: [cell.objectID], context: ctx))
        processNext()
    }

    /// Backfill all untagged cells for the given cell size, clustering nearby cells to minimise geocode requests.
    /// Runs at most once per app lifecycle — repeated calls (e.g. on app foreground) are no-ops.
    func geocodeUntaggedCells(context: NSManagedObjectContext) {
        guard !hasBackfilled else { return }
        hasBackfilled = true
        let request = VisitedCell.fetchRequest()
        request.predicate = NSPredicate(
            format: "cellSizeMeters == %f AND locality == nil",
            kCellSizeMeters
        )
        guard let cells = try? context.fetch(request), !cells.isEmpty else { return }

        // Group cells into ~0.5° geographic buckets (~55 km) to minimise CLGeocoder requests.
        var buckets: [BucketKey: [VisitedCell]] = [:]
        for cell in cells {
            let coord = GridMath.center(for: CellID(x: cell.cellX, y: cell.cellY))
            let key = BucketKey(
                lat: Int(floor(coord.latitude / 0.5)),
                lon: Int(floor(coord.longitude / 0.5))
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
                context: context
            ))
        }

        processNext()
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
            let name = p.locality ?? p.subAdministrativeArea ?? p.administrativeArea ?? "Unknown"
            let ctx = cluster.context
            for id in cluster.objectIDs {
                guard let cell = try? ctx.existingObject(with: id) as? VisitedCell else { continue }
                cell.locality = name
            }
            try? ctx.save()
        } catch {
            // Silently swallow — cells stay nil and will be retried on next launch.
        }
    }
}
