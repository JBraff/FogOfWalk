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
}
