import XCTest
import CoreData
import CoreLocation
import MapKit
@testable import FogOfWalk

// MARK: - Mock geocoder

final class MockGeocoder: GeocoderProtocol, @unchecked Sendable {
    let localityToReturn: String
    let stateToReturn: String?
    let countryToReturn: String?
    private(set) var callCount = 0
    var onCall: (() -> Void)?

    init(locality: String = "MockCity", state: String? = nil, country: String? = nil,
         onCall: (() -> Void)? = nil) {
        self.localityToReturn = locality
        self.stateToReturn    = state
        self.countryToReturn  = country
        self.onCall           = onCall
    }

    func reverseGeocodeLocation(_ location: CLLocation) async throws -> [CLPlacemark] {
        callCount += 1
        onCall?()
        let placemark = MockPlacemark(locality: localityToReturn,
                                       administrativeArea: stateToReturn,
                                       country: countryToReturn)
        return [placemark]
    }
}

/// Minimal CLPlacemark subclass that overrides locality/administrativeArea/country.
private final class MockPlacemark: CLPlacemark, @unchecked Sendable {
    private let localityValue: String?
    private let administrativeAreaValue: String?
    private let countryValue: String?

    init(locality: String?, administrativeArea: String? = nil, country: String? = nil) {
        self.localityValue = locality
        self.administrativeAreaValue = administrativeArea
        self.countryValue = country
        // init(placemark:) is the designated iOS initializer for CLPlacemark.
        super.init(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D()))
    }

    required init?(coder: NSCoder) { nil }

    override var locality: String? { localityValue }
    override var administrativeArea: String? { administrativeAreaValue }
    override var country: String? { countryValue }
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
        locality: String? = nil,
        state: String? = nil,
        country: String? = nil
    ) -> VisitedCell {
        let cell = VisitedCell(context: ctx)
        cell.cellX          = x
        cell.cellY          = y
        cell.cellSizeMeters = cellSizeMeters
        cell.firstVisited   = Date()
        cell.locality       = locality
        cell.state          = state
        cell.country        = country
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

    func testBackfillRunsOnlyOnce() async {
        // geocodeUntaggedCells should be idempotent — calling it twice (e.g. on foreground)
        // must not double the queue or trigger duplicate geocoding.
        let mock = MockGeocoder(locality: "OnceCity")

        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            insertCell(in: ctx, x: 0, locality: nil)
            let geocoder = LocalityGeocoder(geocoder: mock, requestDelay: .zero)
            geocoder.geocodeUntaggedCells(context: ctx)
            geocoder.geocodeUntaggedCells(context: ctx) // second call — should be ignored
        }

        try? await Task.sleep(for: .milliseconds(200))

        await MainActor.run {
            XCTAssertEqual(mock.callCount, 1,
                "geocodeUntaggedCells called twice must only trigger one geocode request")
        }
    }

    func testQueueCapPreventUnboundedGrowth() async {
        // Enqueue more cells than the cap; only maxQueueSize should be processed.
        let mock = MockGeocoder()

        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx       = container.viewContext
            let geocoder  = LocalityGeocoder(geocoder: mock, requestDelay: .zero)

            // Enqueue maxQueueSize + 50 cells — the excess should be silently dropped.
            for i in Int32(0)..<Int32(LocalityGeocoder.maxQueueSize + 50) {
                let cell = insertCell(in: ctx, x: i, y: i, locality: nil)
                geocoder.enqueue(cell)
            }
            // At the cap, new enqueues return early — the queue must not exceed the cap.
            // We can't easily inspect the internal queue, but we can assert callCount
            // stays at or below the cap after a short wait.
        }
        // Processing speed with .zero delay makes it hard to catch the queue mid-drain,
        // so this test primarily validates there is no crash or hang.
    }

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
            geocoder.geocodeUntaggedCells(context: context!)
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
            insertCell(in: ctx, x: 0, locality: "ExistingLocality",
                       state: "ExistingState", country: "ExistingCountry")
            let geocoder = LocalityGeocoder(geocoder: mock, requestDelay: .zero)
            geocoder.geocodeUntaggedCells(context: ctx)
        }

        // Give tasks time to run
        try? await Task.sleep(for: .milliseconds(200))

        await MainActor.run {
            XCTAssertEqual(mock.callCount, 0, "No geocode call should be made for fully-tagged cells")
        }
    }

    func testEnqueueSetsStateAndCountry() async {
        let expectation = XCTestExpectation(description: "geocoder called")
        let mock = MockGeocoder(locality: "TestCity", state: "TestState", country: "TestCountry",
                                 onCall: { expectation.fulfill() })

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
        try? await Task.sleep(for: .milliseconds(100))

        await MainActor.run {
            guard let id = cellObjectID, let context = ctx,
                  let cell = try? context.existingObject(with: id) as? VisitedCell else {
                XCTFail("Could not fetch cell")
                return
            }
            XCTAssertEqual(cell.state, "TestState")
            XCTAssertEqual(cell.country, "TestCountry")
        }
    }

    func testBackfillRegeocodesCellsMissingStateOrCountry() async {
        // A cell already tagged with `locality` under the old scheme (state/country nil)
        // must be picked up by the backfill and re-geocoded to fill in state/country.
        let expectation = XCTestExpectation(description: "geocoded cell missing state/country")
        let mock = MockGeocoder(locality: "SameCity", state: "NewState", country: "NewCountry",
                                 onCall: { expectation.fulfill() })

        var cellID: NSManagedObjectID?
        var context: NSManagedObjectContext?

        await MainActor.run {
            let container = makeInMemoryContainer()
            context       = container.viewContext
            let cell      = insertCell(in: context!, locality: "SameCity", state: nil, country: nil)
            cellID        = cell.objectID
            let geocoder  = LocalityGeocoder(geocoder: mock, requestDelay: .zero)
            geocoder.geocodeUntaggedCells(context: context!)
        }

        await fulfillment(of: [expectation], timeout: 5)
        try? await Task.sleep(for: .milliseconds(100))

        await MainActor.run {
            guard let id = cellID, let ctx = context,
                  let cell = try? ctx.existingObject(with: id) as? VisitedCell else {
                XCTFail("Could not fetch cell")
                return
            }
            XCTAssertEqual(cell.state, "NewState")
            XCTAssertEqual(cell.country, "NewCountry")
        }
    }

    func testBackfillDoesNotOverwriteExistingLocality() async {
        // Regression test: a cell already tagged with a correct locality under the old scheme
        // must keep that locality when backfilled for state/country, even if clustered with
        // cells whose geocode result would produce a different locality name.
        let expectation = XCTestExpectation(description: "geocoder called")
        let mock = MockGeocoder(locality: "DifferentCity", state: "NewState", country: "NewCountry",
                                 onCall: { expectation.fulfill() })

        var cellID: NSManagedObjectID?
        var context: NSManagedObjectContext?

        await MainActor.run {
            let container = makeInMemoryContainer()
            context       = container.viewContext
            let cell      = insertCell(in: context!, locality: "OriginalCity", state: nil, country: nil)
            cellID        = cell.objectID
            let geocoder  = LocalityGeocoder(geocoder: mock, requestDelay: .zero)
            geocoder.geocodeUntaggedCells(context: context!)
        }

        await fulfillment(of: [expectation], timeout: 5)
        try? await Task.sleep(for: .milliseconds(100))

        await MainActor.run {
            guard let id = cellID, let ctx = context,
                  let cell = try? ctx.existingObject(with: id) as? VisitedCell else {
                XCTFail("Could not fetch cell")
                return
            }
            XCTAssertEqual(cell.locality, "OriginalCity", "Backfill must not overwrite an already-set locality")
            XCTAssertEqual(cell.state, "NewState")
            XCTAssertEqual(cell.country, "NewCountry")
        }
    }

    func testBackfillFillsUnknownAndTerminatesRegeocodeLoop() async {
        // Regression test: when the placemark lacks administrativeArea/country, the backfill
        // must still write "Unknown" (not nil) so the predicate stops matching the cell —
        // otherwise the cell would be re-geocoded forever on every launch.
        let expectation = XCTestExpectation(description: "geocoder called")
        let mock = MockGeocoder(locality: "SomeCity", onCall: { expectation.fulfill() }) // state/country default to nil

        var cellID: NSManagedObjectID?
        var context: NSManagedObjectContext?

        await MainActor.run {
            let container = makeInMemoryContainer()
            context       = container.viewContext
            let cell      = insertCell(in: context!, locality: nil, state: nil, country: nil)
            cellID        = cell.objectID
            let geocoder  = LocalityGeocoder(geocoder: mock, requestDelay: .zero)
            geocoder.geocodeUntaggedCells(context: context!)
        }

        await fulfillment(of: [expectation], timeout: 5)
        try? await Task.sleep(for: .milliseconds(100))

        await MainActor.run {
            guard let id = cellID, let ctx = context,
                  let cell = try? ctx.existingObject(with: id) as? VisitedCell else {
                XCTFail("Could not fetch cell")
                return
            }
            XCTAssertEqual(cell.state, "Unknown")
            XCTAssertEqual(cell.country, "Unknown")
        }

        // A second, fresh backfill pass must find nothing left to geocode.
        await MainActor.run {
            guard let ctx = context else { return }
            let geocoder2 = LocalityGeocoder(geocoder: mock, requestDelay: .zero)
            geocoder2.geocodeUntaggedCells(context: ctx)
        }

        try? await Task.sleep(for: .milliseconds(200))

        await MainActor.run {
            XCTAssertEqual(mock.callCount, 1,
                "Cell with 'Unknown' state/country must no longer match the backfill predicate")
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
            geocoder.geocodeUntaggedCells(context: ctx)
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
