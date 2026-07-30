import CoreData
import Foundation

// MARK: - Payload

/// One row of a user's exploration history, as stored in a backup file.
struct BackupVisitedCell: Codable, Equatable {
    let cellX: Int32
    let cellY: Int32
    let cellSizeMeters: Double
    let firstVisited: Date?
    let locality: String?
}

/// One discovered landmark, as stored in a backup file. Only the identifier and discovery
/// date travel — name/category/coordinates are re-derived from the bundled reference data
/// on the importing device, so the backup never goes stale relative to landmark metadata.
struct BackupLandmark: Codable, Equatable {
    let identifier: String
    let firstDiscovered: Date?
}

/// The full contents of a backup file. `schemaVersion` guards against importing a file
/// produced by a future, incompatible version of the app.
struct BackupPayload: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let exportedAt: Date
    let visitedCells: [BackupVisitedCell]
    let landmarks: [BackupLandmark]
}

// MARK: - Errors

enum BackupError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "This backup file uses a newer format (version \(version)) that this version of the app doesn't support."
        }
    }
}

// MARK: - Merge summary

/// Counts surfaced to the user after an import: how many rows were actually new, as opposed
/// to already present on the device (and therefore silently merged/skipped).
struct MergeSummary: Equatable {
    let cellsAdded: Int
    let landmarksAdded: Int
}

// MARK: - Encode / decode

enum BackupService {
    static func encode(_ payload: BackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    /// Decodes and validates a backup file. Throws `BackupError.unsupportedSchemaVersion`
    /// if the file was produced by a schema version this app doesn't understand, or a
    /// `DecodingError` if the file isn't a valid backup at all.
    static func decode(_ data: Data) throws -> BackupPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)
        guard payload.schemaVersion == BackupPayload.currentSchemaVersion else {
            throw BackupError.unsupportedSchemaVersion(payload.schemaVersion)
        }
        return payload
    }

    // MARK: - Export

    /// Builds a backup payload from the current state of both stores and encodes it.
    /// Only discovered landmarks are included — undiscovered ones carry no user data worth
    /// backing up, and their metadata is re-derived from bundled reference data on import.
    @MainActor
    static func exportData(explorationStore: ExplorationStore, landmarkStore: LandmarkStore) throws -> Data {
        let request = NSFetchRequest<VisitedCell>(entityName: "VisitedCell")
        let cells = try explorationStore.viewContext.fetch(request)
        let cellRecords = cells.map {
            BackupVisitedCell(cellX: $0.cellX, cellY: $0.cellY, cellSizeMeters: $0.cellSizeMeters,
                               firstVisited: $0.firstVisited, locality: $0.locality)
        }

        let landmarkRecords = landmarkStore.allLandmarks
            .filter { $0.isDiscovered }
            .map { BackupLandmark(identifier: $0.identifier, firstDiscovered: $0.firstDiscovered) }

        let payload = BackupPayload(schemaVersion: BackupPayload.currentSchemaVersion,
                                     exportedAt: Date(),
                                     visitedCells: cellRecords,
                                     landmarks: landmarkRecords)
        return try encode(payload)
    }

    // MARK: - Import

    /// Merges a decoded backup payload into both stores. Never partially applies: both
    /// underlying merge calls are all-or-nothing at the Core Data save level (see
    /// `ExplorationStore.addCells(_:)` and `LandmarkStore.restoreDiscovered(_:)`).
    @MainActor
    static func merge(_ payload: BackupPayload,
                       into explorationStore: ExplorationStore,
                       landmarkStore: LandmarkStore) -> MergeSummary {
        let cellsAdded = explorationStore.addCells(payload.visitedCells)
        let landmarksAdded = landmarkStore.restoreDiscovered(
            payload.landmarks.map { ($0.identifier, $0.firstDiscovered ?? Date()) }
        )
        return MergeSummary(cellsAdded: cellsAdded, landmarksAdded: landmarksAdded)
    }
}
