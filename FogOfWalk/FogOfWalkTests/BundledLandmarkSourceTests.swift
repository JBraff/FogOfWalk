import XCTest
import MapKit
import SQLite3
@testable import FogOfWalk

// MARK: - Helpers

/// Builds a temporary SQLite database with the landmarks schema and returns its URL.
func makeTestDatabase(landmarks: [(id: String, name: String, description: String?,
                                   lat: Double, lon: Double,
                                   category: String, image: String?)]) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("test_landmarks_\(UUID().uuidString).sqlite")

    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
    defer { /* db stays open until we finish inserting */ }

    let schema = """
        CREATE TABLE landmarks (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT,
            lat REAL NOT NULL, lon REAL NOT NULL,
            category TEXT NOT NULL, image TEXT
        );
        CREATE VIRTUAL TABLE landmarks_rtree USING rtree(
            rowid, min_lat, max_lat, min_lon, max_lon
        );
        """
    XCTAssertEqual(sqlite3_exec(db, schema, nil, nil, nil), SQLITE_OK)

    for lm in landmarks {
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db,
            "INSERT INTO landmarks (id,name,description,lat,lon,category,image) VALUES (?,?,?,?,?,?,?)",
            -1, &stmt, nil)
        sqlite3_bind_text(stmt, 1, lm.id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 2, lm.name, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        if let desc = lm.description {
            sqlite3_bind_text(stmt, 3, desc, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        sqlite3_bind_double(stmt, 4, lm.lat)
        sqlite3_bind_double(stmt, 5, lm.lon)
        sqlite3_bind_text(stmt, 6, lm.category, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        if let img = lm.image {
            sqlite3_bind_text(stmt, 7, img, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        let rc = sqlite3_step(stmt)
        XCTAssertEqual(rc, SQLITE_DONE)
        let rowid = sqlite3_last_insert_rowid(db)
        sqlite3_finalize(stmt)

        var rtreeStmt: OpaquePointer?
        sqlite3_prepare_v2(db,
            "INSERT INTO landmarks_rtree (rowid,min_lat,max_lat,min_lon,max_lon) VALUES (?,?,?,?,?)",
            -1, &rtreeStmt, nil)
        sqlite3_bind_int64(rtreeStmt, 1, rowid)
        sqlite3_bind_double(rtreeStmt, 2, lm.lat)
        sqlite3_bind_double(rtreeStmt, 3, lm.lat)
        sqlite3_bind_double(rtreeStmt, 4, lm.lon)
        sqlite3_bind_double(rtreeStmt, 5, lm.lon)
        sqlite3_step(rtreeStmt)
        sqlite3_finalize(rtreeStmt)
    }

    sqlite3_close(db)
    return url
}

// MARK: - Tests

final class BundledLandmarkSourceTests: XCTestCase {

    // MARK: - Fixtures

    let nyMuseum   = (id: "Q11111", name: "NY Museum",   description: "art museum",   lat: 40.7794, lon: -73.9632, category: "museum",  image: "https://example.com/img.jpg")
    let sfAirport  = (id: "Q22222", name: "SFO",         description: "airport",      lat: 37.6213, lon: -122.3790, category: "airport", image: nil as String?)
    let londonPark = (id: "Q33333", name: "Hyde Park",   description: "royal park",   lat: 51.5073, lon: -0.1657, category: "nationalPark", image: nil as String?)

    // MARK: - Open / close

    func testOpenValidDatabase() throws {
        let url = try makeTestDatabase(landmarks: [nyMuseum])
        XCTAssertNoThrow(try BundledLandmarkSource(databaseURL: url))
    }

    func testOpenMissingDatabaseThrows() {
        let url = URL(fileURLWithPath: "/nonexistent/path/to/landmarks.sqlite")
        XCTAssertThrowsError(try BundledLandmarkSource(databaseURL: url))
    }

    func testLookupByIdentifierReturnsMetadataAndBindsInput() throws {
        let url = try makeTestDatabase(landmarks: [nyMuseum, sfAirport])
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try BundledLandmarkSource(databaseURL: url)
        let landmark = try XCTUnwrap(source.landmark(withIdentifier: "Q11111"))
        XCTAssertEqual(landmark.id, "Q11111")
        XCTAssertEqual(landmark.name, "NY Museum")
        XCTAssertEqual(landmark.description, "art museum")
        XCTAssertEqual(landmark.lat, 40.7794)
        XCTAssertEqual(landmark.lon, -73.9632)
        XCTAssertEqual(landmark.category, "museum")
        XCTAssertEqual(landmark.imageURL, "https://example.com/img.jpg")
        XCTAssertNil(source.landmark(withIdentifier: "missing"))
        XCTAssertNil(source.landmark(withIdentifier: "Q11111' OR 1=1 --"))
        XCTAssertNil(source.landmark(withIdentifier: "Q22222")?.imageURL)
    }

    // MARK: - Basic query

    func testLandmarkInRegionIsReturned() throws {
        let url = try makeTestDatabase(landmarks: [nyMuseum])
        let source = try BundledLandmarkSource(databaseURL: url)

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.7794, longitude: -73.9632),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        let results = source.landmarks(in: region)
        XCTAssertEqual(results.count, 1)
    }

    func testLandmarkOutsideRegionNotReturned() throws {
        let url = try makeTestDatabase(landmarks: [nyMuseum])
        let source = try BundledLandmarkSource(databaseURL: url)

        // Region centred on London — should not include NYC
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1),
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        )
        let results = source.landmarks(in: region)
        XCTAssertEqual(results.count, 0)
    }

    func testOnlyLandmarksInRegionReturned() throws {
        let url = try makeTestDatabase(landmarks: [nyMuseum, sfAirport, londonPark])
        let source = try BundledLandmarkSource(databaseURL: url)

        // Wide region that covers NYC and SFO but not London
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.0, longitude: -98.0),
            span: MKCoordinateSpan(latitudeDelta: 20.0, longitudeDelta: 60.0)
        )
        let results = source.landmarks(in: region)
        let ids = Set(results.map { $0.id })
        XCTAssertTrue(ids.contains("Q11111"))
        XCTAssertTrue(ids.contains("Q22222"))
        XCTAssertFalse(ids.contains("Q33333"))
    }

    // MARK: - Field mapping

    func testAllFieldsPopulated() throws {
        let url = try makeTestDatabase(landmarks: [nyMuseum])
        let source = try BundledLandmarkSource(databaseURL: url)

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.7794, longitude: -73.9632),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        let lm = try XCTUnwrap(source.landmarks(in: region).first)

        XCTAssertEqual(lm.id,          "Q11111")
        XCTAssertEqual(lm.name,        "NY Museum")
        XCTAssertEqual(lm.description, "art museum")
        XCTAssertEqual(lm.lat,         40.7794, accuracy: 0.0001)
        XCTAssertEqual(lm.lon,         -73.9632, accuracy: 0.0001)
        XCTAssertEqual(lm.category,    "museum")
        XCTAssertEqual(lm.imageURL,    "https://example.com/img.jpg")
    }

    func testNullDescriptionAndImageReturnNil() throws {
        let url = try makeTestDatabase(landmarks: [sfAirport])
        let source = try BundledLandmarkSource(databaseURL: url)

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.6213, longitude: -122.3790),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        let lm = try XCTUnwrap(source.landmarks(in: region).first)
        XCTAssertNil(lm.imageURL)
    }

    // MARK: - Edge cases

    func testEmptyDatabaseReturnsEmpty() throws {
        let url = try makeTestDatabase(landmarks: [])
        let source = try BundledLandmarkSource(databaseURL: url)

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0),
            span: MKCoordinateSpan(latitudeDelta: 10.0, longitudeDelta: 10.0)
        )
        XCTAssertEqual(source.landmarks(in: region).count, 0)
    }

    func testBoundaryLandmarkIncluded() throws {
        // Landmark exactly on the bounding-box edge should be included.
        let edge = (id: "Q99", name: "Edge", description: nil as String?,
                    lat: 41.0, lon: -73.5, category: "landmark", image: nil as String?)
        let url = try makeTestDatabase(landmarks: [edge])
        let source = try BundledLandmarkSource(databaseURL: url)

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.5, longitude: -74.0),
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
            // covers 40.0–41.0 lat, -74.5– -73.5 lon → edge is at the corner
        )
        let results = source.landmarks(in: region)
        XCTAssertEqual(results.count, 1)
    }

    func testMultipleLandmarksSameLocation() throws {
        // Two different landmarks at the same coordinates (e.g. museum in a park).
        let a = (id: "Q1", name: "A", description: nil as String?, lat: 40.0, lon: -74.0, category: "museum",   image: nil as String?)
        let b = (id: "Q2", name: "B", description: nil as String?, lat: 40.0, lon: -74.0, category: "landmark", image: nil as String?)
        let url = try makeTestDatabase(landmarks: [a, b])
        let source = try BundledLandmarkSource(databaseURL: url)

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        XCTAssertEqual(source.landmarks(in: region).count, 2)
    }

    // MARK: - Antimeridian

    private func landmarkAt(_ id: String, lat: Double = -17.0, lon: Double)
        -> (id: String, name: String, description: String?, lat: Double, lon: Double,
            category: String, image: String?) {
        (id: id, name: id, description: nil, lat: lat, lon: lon, category: "landmark", image: nil)
    }

    func testEastwardAntimeridianCrossingIncludesWrappedSide() throws {
        let url = try makeTestDatabase(landmarks: [
            landmarkAt("west", lon: 179.8), landmarkAt("east", lon: -179.7),
            landmarkAt("farEast", lon: -179.0), landmarkAt("farWest", lon: 179.0),
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try BundledLandmarkSource(databaseURL: url)

        // Centre 180, span 1° → 179.5...180 and -180...-179.5.
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -17.0, longitude: 180.0),
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        )
        XCTAssertEqual(Set(source.landmarks(in: region).map(\.id)), ["west", "east"])
    }

    func testWestwardAntimeridianCrossingIncludesWrappedSide() throws {
        let url = try makeTestDatabase(landmarks: [
            landmarkAt("west", lon: 179.9), landmarkAt("east", lon: -179.6),
            landmarkAt("farEast", lon: -179.0), landmarkAt("farWest", lon: 179.5),
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try BundledLandmarkSource(databaseURL: url)

        // Centre -179.8, span 1° → -180...-179.3 and 179.7...180.
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -17.0, longitude: -179.8),
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        )
        XCTAssertEqual(Set(source.landmarks(in: region).map(\.id)), ["west", "east"])
    }

    func testAntimeridianCrossingKeepsCapWithoutDuplicates() throws {
        // 300 landmarks on each side of ±180°: 600 matches, above the LIMIT.
        var landmarks: [(id: String, name: String, description: String?,
                         lat: Double, lon: Double, category: String, image: String?)] = []
        for i in 0..<300 {
            let offset = Double(i) * 0.0001
            landmarks.append(landmarkAt("W\(i)", lon: 179.9 + offset))
            landmarks.append(landmarkAt("E\(i)", lon: -179.9 - offset))
        }
        // A landmark exactly on the shared boundary must appear once.
        landmarks.insert(landmarkAt("edge", lon: 180.0), at: 0)
        let url = try makeTestDatabase(landmarks: landmarks)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try BundledLandmarkSource(databaseURL: url)

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -17.0, longitude: 180.0),
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        )
        let ids = source.landmarks(in: region).map(\.id)
        XCTAssertEqual(ids.count, 500)
        XCTAssertEqual(Set(ids).count, ids.count, "Merged ranges must not duplicate landmarks")
        XCTAssertEqual(ids.filter { $0 == "edge" }.count, 1)
        XCTAssertTrue(ids.contains { $0.hasPrefix("E") }, "Wrapped side must contribute rows")
    }

    // MARK: - longitudeRanges

    private func ranges(center: Double, span: Double) -> [ClosedRange<Double>] {
        BundledLandmarkSource.longitudeRanges(in: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: center),
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: span)
        ))
    }

    func testLongitudeRangesNormalizesCentreOutsideStoredRange() {
        // 540 is the antimeridian; -181 is 179.
        XCTAssertEqual(ranges(center: 540, span: 1), [179.5...180.0, -180.0...(-179.5)])
        XCTAssertEqual(ranges(center: -181, span: 1), [178.5...179.5])
    }

    func testLongitudeRangesWholeWorldForHalfSpanOf180OrMore() {
        XCTAssertEqual(ranges(center: 10, span: 360), [-180.0...180.0])
        XCTAssertEqual(ranges(center: 10, span: 400), [-180.0...180.0])
    }

    func testLongitudeRangesSpanExactlyReachingAntimeridianIsOneRange() {
        XCTAssertEqual(ranges(center: 179.5, span: 1), [179.0...180.0])
        XCTAssertEqual(ranges(center: -179.5, span: 1), [-180.0...(-179.0)])
    }

    func testLongitudeRangesZeroSpan() {
        XCTAssertEqual(ranges(center: 12.5, span: 0), [12.5...12.5])
    }

    func testLongitudeRangesInvalidInputYieldsNoRanges() {
        XCTAssertEqual(ranges(center: 10, span: -1), [])
        XCTAssertEqual(ranges(center: 10, span: .nan), [])
        XCTAssertEqual(ranges(center: 10, span: .infinity), [])
        XCTAssertEqual(ranges(center: .nan, span: 1), [])
        XCTAssertEqual(ranges(center: .infinity, span: 1), [])
    }

    func testInvalidRegionReturnsNoLandmarks() throws {
        let url = try makeTestDatabase(landmarks: [landmarkAt("a", lat: 0, lon: 10)])
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try BundledLandmarkSource(databaseURL: url)
        for (center, span) in [(10.0, -1.0), (10.0, Double.nan), (Double.nan, 1.0)] {
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: center),
                span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: span)
            )
            XCTAssertTrue(source.landmarks(in: region).isEmpty)
        }
    }

    // MARK: - Result cap

    func testBundledSourceRespectsLimit() throws {
        // 600 landmarks packed into one small box — more than the SQL LIMIT.
        var landmarks: [(id: String, name: String, description: String?,
                         lat: Double, lon: Double,
                         category: String, image: String?)] = []
        for i in 0..<600 {
            let offset = Double(i) * 0.00001
            landmarks.append((id: "Q\(i)", name: "Landmark \(i)", description: nil,
                              lat: 40.0 + offset, lon: -74.0 + offset,
                              category: "landmark", image: nil))
        }
        let url = try makeTestDatabase(landmarks: landmarks)
        let source = try BundledLandmarkSource(databaseURL: url)

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        XCTAssertEqual(source.landmarks(in: region).count, 500,
                       "Query must never return more than the LIMIT, however dense the region")
    }
}
