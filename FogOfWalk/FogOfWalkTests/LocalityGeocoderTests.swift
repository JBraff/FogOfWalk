import XCTest
import CoreData
import CoreLocation
import MapKit
@testable import FogOfWalk

// MARK: - Mock geocoder

final class MockGeocoder: GeocoderProtocol, @unchecked Sendable {
    let localityToReturn: String
    private(set) var callCount = 0
    var onCall: (() -> Void)?

    init(locality: String = "MockCity", onCall: (() -> Void)? = nil) {
        self.localityToReturn = locality
        self.onCall           = onCall
    }

    func reverseGeocodeLocation(_ location: CLLocation) async throws -> [CLPlacemark] {
        callCount += 1
        onCall?()
        let placemark = MockPlacemark(locality: localityToReturn)
        return [placemark]
    }
}

/// Minimal CLPlacemark subclass that overrides `locality`.
private final class MockPlacemark: CLPlacemark, @unchecked Sendable {
    private let localityValue: String?

    init(locality: String?) {
        self.localityValue = locality
        // init(placemark:) is the designated iOS initializer for CLPlacemark.
        super.init(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D()))
    }

    required init?(coder: NSCoder) { nil }

    override var locality: String? { localityValue }
}

// MARK: - Tests

final class LocalityGeocoderTests: XCTestCase {

    func makeInMemoryContainer() -> NSPersistentContainer {
        let container   = NSPersistentContainer(name: "FogOfWalk")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error { XCTFail("In-memory store failed to load: \(error)") }
        }
        return container
    }

    @discardableResult
    func insertCell(
        in ctx: NSManagedObjectContext,
        x: Int32 = 0, y: Int32 = 0,
        cellSizeMeters: Double = 50,
        locality: String? = nil
    ) -> VisitedCell {
        let cell = VisitedCell(context: ctx)
        cell.cellX          = x
        cell.cellY          = y
        cell.cellSizeMeters = cellSizeMeters
        cell.firstVisited   = Date()
        cell.locality       = locality
        try! ctx.save()
        return cell
    }

    // MARK: - enqueue

    func testEnqueueSkipsCellWithExistingLocality() async {
        let expectation = XCTestExpectation(description: "geocoder should NOT be called")
        expectation.isInverted = true

        let mock = MockGeocoder(onCall: { expectation.fulfill() })

        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let cell      = insertCell(in: ctx, locality: "AlreadySet")
            let geocoder  = LocalityGeocoder(geocoder: mock, requestDelay: .zero)
            geocoder.enqueue(cell)
        }

        await fulfillment(of: [expectation], timeout: 1)
    }

    func testEnqueueGeocodesNewCell() async {
        let expectation = XCTestExpectation(description: "geocoder called")
        let mock = MockGeocoder(locality: "TestCity", onCall: { expectation.fulfill() })

        var cellObjectID: NSManagedObjectID?
        var ctx: NSManagedObjectContext?

        await MainActor.run {
            let container = makeInMemoryContainer()
            ctx           = container.viewContext
            let cell      = insertCell(in: ctx!, locality: nil)
            cellObjectID  = cell.objectID
            let geocoder  = LocalityGeocoder(geocoder: mock, requestDelay: .zero)
            geocoder.enqueue(cell)
        }

        await fulfillment(of: [expectation], timeout: 5)

        // Allow the save to propagate
        try? await Task.sleep(for: .milliseconds(100))

        await MainActor.run {
            guard let id = cellObjectID, let context = ctx,
                  let cell = try? context.existingObject(with: id) as? VisitedCell else {
                XCTFail("Could not fetch cell")
                return
            }
            XCTAssertEqual(cell.locality, "TestCity")
        }
    }

    // MARK: - geocodeUntaggedCells

    func testGeocodesUntaggedCells() async {
        let expectation = XCTestExpectation(description: "geocoded untagged")
        let mock = MockGeocoder(locality: "BackfillCity", onCall: { expectation.fulfill() })

        var cellID: NSManagedObjectID?
        var context: NSManagedObjectContext?

        await MainActor.run {
            let container = makeInMemoryContainer()
            context       = container.viewContext
            let cell      = insertCell(in: context!, locality: nil)
            cellID        = cell.objectID
            let geocoder  = LocalityGeocoder(geocoder: mock, requestDelay: .zero)
            geocoder.geocodeUntaggedCells(context: context!, cellSizeMeters: 50)
        }

        await fulfillment(of: [expectation], timeout: 5)
        try? await Task.sleep(for: .milliseconds(100))

        await MainActor.run {
            guard let id = cellID, let ctx = context,
                  let cell = try? ctx.existingObject(with: id) as? VisitedCell else {
                XCTFail("Could not fetch cell")
                return
            }
            XCTAssertEqual(cell.locality, "BackfillCity")
        }
    }

    func testSkipsAlreadyTaggedCellsDuringBackfill() async {
        let mock = MockGeocoder(locality: "ShouldNotOverwrite")

        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            insertCell(in: ctx, x: 0, locality: "ExistingLocality")
            let geocoder = LocalityGeocoder(geocoder: mock, requestDelay: .zero)
            geocoder.geocodeUntaggedCells(context: ctx, cellSizeMeters: 50)
        }

        // Give tasks time to run
        try? await Task.sleep(for: .milliseconds(200))

        await MainActor.run {
            XCTAssertEqual(mock.callCount, 0, "No geocode call should be made for already-tagged cells")
        }
    }

    func testClusteringReducesGeocoderCalls() async {
        // Two cells in the same 0.5° bucket should produce only one geocoder call.
        // At 50m cell size, cells (0,0) and (1,1) map to ~0.00045°, same 0.5° bucket.
        let geocodeExpectation = XCTestExpectation(description: "geocoder called")
        geocodeExpectation.expectedFulfillmentCount = 1

        let mock = MockGeocoder(locality: "ClusterCity", onCall: {
            geocodeExpectation.fulfill()
        })

        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            insertCell(in: ctx, x: 0, y: 0, locality: nil)
            insertCell(in: ctx, x: 1, y: 1, locality: nil)
            let geocoder = LocalityGeocoder(geocoder: mock, requestDelay: .zero)
            geocoder.geocodeUntaggedCells(context: ctx, cellSizeMeters: 50)
        }

        await fulfillment(of: [geocodeExpectation], timeout: 5)

        await MainActor.run {
            XCTAssertEqual(mock.callCount, 1, "Adjacent cells should be clustered into a single geocoder call")
        }
    }

    func testGeocoderErrorIsSwallowed() async {
        final class ErrorGeocoder: GeocoderProtocol, @unchecked Sendable {
            func reverseGeocodeLocation(_ location: CLLocation) async throws -> [CLPlacemark] {
                throw NSError(domain: "test", code: -1)
            }
        }

        var cellID: NSManagedObjectID?
        var context: NSManagedObjectContext?

        await MainActor.run {
            let container = makeInMemoryContainer()
            context       = container.viewContext
            let cell      = insertCell(in: context!, locality: nil)
            cellID        = cell.objectID
            let geocoder  = LocalityGeocoder(geocoder: ErrorGeocoder(), requestDelay: .zero)
            geocoder.enqueue(cell)
        }

        try? await Task.sleep(for: .milliseconds(300))

        await MainActor.run {
            guard let id = cellID, let ctx = context,
                  let cell = try? ctx.existingObject(with: id) as? VisitedCell else {
                XCTFail("Could not fetch cell")
                return
            }
            // locality stays nil — no crash
            XCTAssertNil(cell.locality, "Locality should remain nil when geocoding fails")
        }
    }
}
