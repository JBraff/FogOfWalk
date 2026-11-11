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
    var state: String? = nil
    var country: String? = nil
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
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let exportedAt: Date
    let visitedCells: [BackupVisitedCell]
    let landmarks: [BackupLandmark]
}

// MARK: - Errors

enum BackupError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case replacementUnavailable
    case duplicateRecords
    case unknownLandmark(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "This backup file uses a newer format (version \(version)) that this version of the app doesn't support."
        case .replacementUnavailable:
            return "Exploration storage has unsaved changes or is unavailable. Restart the app before importing again."
        case .duplicateRecords:
            return "This backup contains duplicate cells or landmarks and cannot replace your data."
        case .unknownLandmark(let identifier):
            return "This backup contains a landmark (\(identifier)) unavailable in this version of the app. Your data has not been replaced."
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

    /// Decodes and validates a backup file. Older schema versions decode forward-compatibly
    /// (newer optional fields simply default to `nil`), so only files from a *future* schema
    /// version this app doesn't understand are rejected. Throws
    /// `BackupError.unsupportedSchemaVersion` in that case, or a `DecodingError` if the file
    /// isn't a valid backup at all.
    static func decode(_ data: Data) throws -> BackupPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)
        guard payload.schemaVersion <= BackupPayload.currentSchemaVersion else {
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
                               firstVisited: $0.firstVisited, locality: $0.locality,
                               state: $0.state, country: $0.country)
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

    /// Replaces a decoded payload in one save on the stores' shared view context. Ordinary
    /// deletes (not batch deletes) let Core Data roll back both entities on save failure.
    /// No cache is published until that save succeeds, and no recording/geocoding callbacks
    /// run for imported cells. Missing landmark metadata comes from the bundled database;
    /// an unresolvable identifier rejects the replacement rather than silently losing it.
    /// Missing dates use Merge's defaults. The normal launch sweep may subsequently
    /// rediscover omitted landmarks near retained cells; no discovery exclusions are stored.
    @MainActor
    static func replace(_ payload: BackupPayload,
                        into explorationStore: ExplorationStore,
                        landmarkStore: LandmarkStore,
                        landmarkSource: any LandmarkDataProviding) throws {
        if let loadError = explorationStore.loadError { throw loadError }
        let context = explorationStore.viewContext
        guard context === landmarkStore.viewContext, !context.hasChanges else {
            throw BackupError.replacementUnavailable
        }
        struct CellKey: Hashable {
            let x: Int32
            let y: Int32
            let size: Double
        }
        let keys = payload.visitedCells.map { CellKey(x: $0.cellX, y: $0.cellY, size: $0.cellSizeMeters) }
        guard Set(keys).count == keys.count,
              Set(payload.landmarks.map(\.identifier)).count == payload.landmarks.count else {
            throw BackupError.duplicateRecords
        }

        // Resolve and fetch everything before touching existing history.
        let cells = try context.fetch(VisitedCell.fetchRequest())
        let landmarks = try context.fetch(Landmark.fetchRequest())
        let known = Set(landmarks.map(\.identifier))
        let missing = payload.landmarks.filter { !known.contains($0.identifier) }
        var metadata: [WikidataLandmark] = []
        if !missing.isEmpty {
            for record in missing {
                guard let item = landmarkSource.landmark(withIdentifier: record.identifier),
                      item.id == record.identifier else {
                    throw BackupError.unknownLandmark(record.identifier)
                }
                metadata.append(item)
            }
        }

        do {
            for cell in cells { context.delete(cell) }
            for record in payload.visitedCells {
                let cell = VisitedCell(context: context)
                cell.cellX = record.cellX
                cell.cellY = record.cellY
                cell.cellSizeMeters = record.cellSizeMeters
                cell.firstVisited = record.firstVisited ?? explorationStore.nowProvider()
                cell.locality = record.locality
                cell.state = record.state
                cell.country = record.country
            }

            var allLandmarks = landmarks
            for item in metadata {
                allLandmarks.append(landmarkStore.insertReferenceLandmark(item, firstSeen: payload.exportedAt))
            }
            let targets = Dictionary(uniqueKeysWithValues: payload.landmarks.map { ($0.identifier, $0) })
            for landmark in allLandmarks {
                let target = targets[landmark.identifier]
                let discovered = target != nil
                let date = target.map { $0.firstDiscovered ?? payload.exportedAt }
                if landmark.isDiscovered != discovered { landmark.isDiscovered = discovered }
                if landmark.firstDiscovered != date { landmark.firstDiscovered = date }
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        explorationStore.reloadAfterReplacement()
        landmarkStore.reloadAfterReplacement()
    }

    /// Merges a decoded backup payload into both stores.
    ///
    /// Note: the two merges are sequential, not jointly atomic. If the landmark merge fails
    /// after the cell merge already saved, the cell changes remain committed. Both stores
    /// share one persistent container in production, so a true single-save merge is
    /// architecturally possible but not implemented here.
    ///
    /// Throws if either underlying merge fails to save, so the caller can distinguish a real
    /// failure from "nothing new to import" (both of which would otherwise report as
    /// `cellsAdded: 0, landmarksAdded: 0`).
    @MainActor
    static func merge(_ payload: BackupPayload,
                       into explorationStore: ExplorationStore,
                       landmarkStore: LandmarkStore) throws -> MergeSummary {
        let cellsAdded = try explorationStore.addCells(payload.visitedCells)
        let landmarksAdded = try landmarkStore.restoreDiscovered(
            payload.landmarks.map { ($0.identifier, $0.firstDiscovered ?? payload.exportedAt) }
        )
        return MergeSummary(cellsAdded: cellsAdded, landmarksAdded: landmarksAdded)
    }
}
