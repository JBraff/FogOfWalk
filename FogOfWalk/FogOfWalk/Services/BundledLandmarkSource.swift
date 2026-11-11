import Foundation
import MapKit
import SQLite3

// MARK: - Protocol

/// Provides landmarks for a given map region. Abstracted for testability.
protocol LandmarkDataProviding {
    func landmarks(in region: MKCoordinateRegion) -> [WikidataLandmark]
    func landmark(withIdentifier identifier: String) -> WikidataLandmark?
}

extension LandmarkDataProviding {
    func landmark(withIdentifier identifier: String) -> WikidataLandmark? { nil }
}

// MARK: - BundledLandmarkSource

/// Reads landmarks from a SQLite database bundled with the app.
/// Uses an R-tree index for efficient bounding-box queries.
final class BundledLandmarkSource: LandmarkDataProviding {

    private var db: OpaquePointer?

    /// - Parameter databaseURL: Path to the `.sqlite` file (typically from `Bundle.main`).
    /// - Throws: If the file cannot be opened as a SQLite database.
    init(databaseURL: URL) throws {
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil)
        guard rc == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            throw BundledLandmarkSourceError.cannotOpen(path: databaseURL.path, code: rc)
        }
        db = handle
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - LandmarkDataProviding

    func landmarks(in region: MKCoordinateRegion) -> [WikidataLandmark] {
        guard let db else { return [] }

        let minLat = region.center.latitude  - region.span.latitudeDelta  / 2
        let maxLat = region.center.latitude  + region.span.latitudeDelta  / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2

        // Join against the R-tree for fast bounding-box filtering.
        //
        // The LIMIT is a blast-radius cap, not a pagination scheme: callers are expected to
        // stay within `GridMath.maxIngestSpanDegrees` (1.0°), and the densest 1.0°×1.0° window
        // in the shipped database holds 244 rows (central Italy). 500 therefore never truncates
        // a legitimate result — but it does stop an unguarded world-zoom query from returning
        // all ~15,000 rows and inserting them into Core Data permanently.
        //
        // If `maxIngestSpanDegrees` is ever raised, re-measure the worst-case density first:
        // beyond that point this LIMIT becomes a silent truncator.
        let sql = """
            SELECT l.id, l.name, l.description, l.lat, l.lon, l.category, l.image
            FROM landmarks l
            JOIN landmarks_rtree r ON l.rowid = r.rowid
            WHERE r.max_lat >= ?
              AND r.min_lat <= ?
              AND r.max_lon >= ?
              AND r.min_lon <= ?
            ORDER BY l.rowid
            LIMIT 500
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, minLat)
        sqlite3_bind_double(stmt, 2, maxLat)
        sqlite3_bind_double(stmt, 3, minLon)
        sqlite3_bind_double(stmt, 4, maxLon)

        var results: [WikidataLandmark] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id       = column(stmt, index: 0) ?? ""
            let name     = column(stmt, index: 1) ?? ""
            let desc     = column(stmt, index: 2)
            let lat      = sqlite3_column_double(stmt, 3)
            let lon      = sqlite3_column_double(stmt, 4)
            let category = column(stmt, index: 5) ?? "landmark"
            let image    = column(stmt, index: 6)

            guard !id.isEmpty, !name.isEmpty else { continue }

            results.append(WikidataLandmark(
                id: id, name: name, description: desc,
                lat: lat, lon: lon, category: category, imageURL: image
            ))
        }
        return results
    }

    // MARK: - Private

    /// Backup replacement can restore a discovery before its region has ever been shown.
    func landmark(withIdentifier identifier: String) -> WikidataLandmark? {
        guard let db else { return nil }
        let sql = "SELECT id, name, description, lat, lon, category, image FROM landmarks WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, identifier, -1, transient)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let id = column(stmt, index: 0), let name = column(stmt, index: 1) else { return nil }
        return WikidataLandmark(id: id, name: name, description: column(stmt, index: 2),
                                lat: sqlite3_column_double(stmt, 3), lon: sqlite3_column_double(stmt, 4),
                                category: column(stmt, index: 5) ?? "landmark", imageURL: column(stmt, index: 6))
    }

    private func column(_ stmt: OpaquePointer?, index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: ptr)
    }
}

// MARK: - Error

enum BundledLandmarkSourceError: Error, LocalizedError {
    case cannotOpen(path: String, code: Int32)

    var errorDescription: String? {
        switch self {
        case let .cannotOpen(path, code):
            return "Cannot open landmark database at \(path) (SQLite error \(code))"
        }
    }
}
