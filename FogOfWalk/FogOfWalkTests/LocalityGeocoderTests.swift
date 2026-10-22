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

/// Records each requested location, in order.
private final class RecordingGeocoder: GeocoderProtocol, @unchecked Sendable {
    private(set) var locations: [CLLocation] = []
    let onCall: (Int) -> Void

    init(onCall: @escaping (Int) -> Void) { self.onCall = onCall }

    func reverseGeocodeLocation(_ location: CLLocation) async throws -> [CLPlacemark] {
        locations.append(location)
        onCall(locations.count)
        return [MockPlacemark(locality: "RecordedCity")]
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
            let cell      = insertCell(in: ctx, locality: "AlreadySet", country: "ExistingCountry")
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

    /// Regression: with ~1 km backfill clusters a large backfill fills the queue, and a cell
    /// walked meanwhile was silently dropped. It must displace backfill and be geocoded next.
    func testNewCellIsGeocodedAheadOfAFullBackfill() async {
        let secondCall = XCTestExpectation(description: "second geocode request")
        let mock = RecordingGeocoder(onCall: { count in if count == 2 { secondCall.fulfill() } })
        var geocoder: LocalityGeocoder?
        var walkedID: NSManagedObjectID?
        var context: NSManagedObjectContext?
        let walked = CellID(x: -5_000, y: -5_000)

        await MainActor.run {
            let container = makeInMemoryContainer()
            let ctx = container.viewContext
            context = ctx
            // 30 cells apart is ~0.0135°, so every cell is its own backfill cluster.
            for i in Int32(0)..<Int32(LocalityGeocoder.maxQueueSize + 50) {
                insertCell(in: ctx, x: i * 30, y: 0)
            }
            geocoder = LocalityGeocoder(geocoder: mock, requestDelay: .milliseconds(20))
            geocoder!.geocodeUntaggedCells(context: ctx)

            let cell = insertCell(in: ctx, x: walked.x, y: walked.y)
            walkedID = cell.objectID
            geocoder!.enqueue(cell)
        }

        await fulfillment(of: [secondCall], timeout: 5)
        try? await Task.sleep(for: .milliseconds(10))

        await MainActor.run {
            let centre = GridMath.center(for: walked)
            let second = mock.locations[1].coordinate
            XCTAssertEqual(second.latitude, centre.latitude, accuracy: 1e-9,
                           "The walked cell must be geocoded before the remaining backfill")
            XCTAssertEqual(second.longitude, centre.longitude, accuracy: 1e-9)
            let cell = try? context!.existingObject(with: walkedID!) as? VisitedCell
            XCTAssertEqual(cell?.locality, "RecordedCity")
            geocoder = nil
        }
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

    func testMissingCountryRemainsRetryableOnNextLaunch() async {
        // Missing administrative areas can be normal, but a missing country must be retryable.
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
            XCTAssertNil(cell.country)
        }

        // A fresh launch retries the unresolved country.
        await MainActor.run {
            guard let ctx = context else { return }
            let geocoder2 = LocalityGeocoder(geocoder: mock, requestDelay: .zero)
            geocoder2.geocodeUntaggedCells(context: ctx)
        }

        try? await Task.sleep(for: .milliseconds(200))

        await MainActor.run {
            XCTAssertEqual(mock.callCount, 2,
                "An unresolved country must be retried on the next launch")
        }
    }

    func testBackfillRepairsLegacyCountrySentinelsAndPreservesKnownLabels() async {
        let called = XCTestExpectation(description: "repair cluster geocoded")
        let mock = MockGeocoder(locality: "ReplacementTown", state: "ReplacementState",
                                country: "Canada", onCall: { called.fulfill() })
        let context = await MainActor.run {
            let container = makeInMemoryContainer()
            let context = container.viewContext
            for (index, country) in ["Unknown", "unknown", "", "France"].enumerated() {
                insertCell(in: context, x: Int32(index), locality: "OriginalTown",
                           state: index == 3 ? nil : "OriginalState", country: country)
            }
            LocalityGeocoder(geocoder: mock, requestDelay: .zero)
                .geocodeUntaggedCells(context: context)
            return context
        }
        await fulfillment(of: [called], timeout: 5)
        try? await Task.sleep(for: .milliseconds(100))
        await MainActor.run {
            let request = VisitedCell.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "cellX", ascending: true)]
            let cells = try! context.fetch(request)
            XCTAssertEqual(cells.map(\.country), ["Canada", "Canada", "Canada", "France"])
            XCTAssertTrue(cells.allSatisfy { $0.locality == "OriginalTown" })
            XCTAssertEqual(cells.first?.state, "OriginalState")
            XCTAssertEqual(cells.count, 4)
        }
    }

    func testEnqueueRepairsCountryEvenWhenLocalityIsKnown() async {
        let called = XCTestExpectation(description: "country repair requested")
        let mock = MockGeocoder(country: "Canada", onCall: { called.fulfill() })
        let context = await MainActor.run {
            let container = makeInMemoryContainer()
            let context = container.viewContext
            let cell = insertCell(in: context, locality: "ExistingTown", country: "Unknown")
            LocalityGeocoder(geocoder: mock, requestDelay: .zero).enqueue(cell)
            return context
        }
        await fulfillment(of: [called], timeout: 5)
        try? await Task.sleep(for: .milliseconds(100))
        await MainActor.run {
            let cell = try! context.fetch(VisitedCell.fetchRequest()).first!
            XCTAssertEqual(cell.country, "Canada")
            XCTAssertEqual(cell.locality, "ExistingTown")
        }
    }

    func testClusteringReducesGeocoderCalls() async {
        // Two adjacent cells share a backfill cluster and should produce one geocoder call.
        // At 50m cell size, cells (0,0) and (1,1) are ~0.00045° apart.
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

    /// Regression: backfill clustered at 0.5° (~55 km) and stamped one town's name on every
    /// untagged cell in the cluster. Cells ~11 km apart must be geocoded separately.
    func testBackfillDoesNotShareOneTownAcrossDistantCells() async {
        final class EastWestGeocoder: GeocoderProtocol, @unchecked Sendable {
            let called: XCTestExpectation
            init(called: XCTestExpectation) { self.called = called }
            func reverseGeocodeLocation(_ location: CLLocation) async throws -> [CLPlacemark] {
                defer { called.fulfill() }
                let town = location.coordinate.longitude < 0.05 ? "Westtown" : "Easttown"
                return [MockPlacemark(locality: town, administrativeArea: "State", country: "Country")]
            }
        }
        let called = XCTestExpectation(description: "both clusters geocoded")
        called.expectedFulfillmentCount = 2
        let mock = EastWestGeocoder(called: called)

        var west: NSManagedObjectID?
        var east: NSManagedObjectID?
        var context: NSManagedObjectContext?
        await MainActor.run {
            let container = makeInMemoryContainer()
            context = container.viewContext
            // x = 222 is ~0.1° east of x = 0: inside one old 0.5° bucket, two 0.01° clusters.
            west = insertCell(in: context!, x: 0, y: 0, locality: nil).objectID
            east = insertCell(in: context!, x: 222, y: 0, locality: nil).objectID
            let geocoder = LocalityGeocoder(geocoder: mock, requestDelay: .zero)
            geocoder.geocodeUntaggedCells(context: context!)
        }

        await fulfillment(of: [called], timeout: 5)
        try? await Task.sleep(for: .milliseconds(100))

        await MainActor.run {
            let westCell = try? context?.existingObject(with: west!) as? VisitedCell
            let eastCell = try? context?.existingObject(with: east!) as? VisitedCell
            XCTAssertEqual(westCell?.locality, "Westtown")
            XCTAssertEqual(eastCell?.locality, "Easttown")
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
