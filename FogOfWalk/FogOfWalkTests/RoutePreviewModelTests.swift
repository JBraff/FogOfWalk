import XCTest
import MapKit
@testable import FogOfWalk

@MainActor
private final class ControlledRouteClient: RoutePreviewClient {
    var searches: [CheckedContinuation<[RouteDestination], Error>] = []
    var requests: [CheckedContinuation<[DiscoveryRoute], Error>] = []
    var queries: [String] = []
    var finishedSearches = 0
    var finishedRoutes = 0
    func search(_ query: String, near: CLLocationCoordinate2D?) async throws -> [RouteDestination] {
        queries.append(query)
        defer { finishedSearches += 1 }
        return try await withCheckedThrowingContinuation { searches.append($0) }
    }
    func routes(from: CLLocationCoordinate2D, to: RouteDestination) async throws -> [DiscoveryRoute] {
        defer { finishedRoutes += 1 }
        return try await withCheckedThrowingContinuation { requests.append($0) }
    }
    func cancel() {} // Deliberately ignores cancellation to verify late-result protection.
}

final class RoutePreviewModelTests: XCTestCase {
    @MainActor private func destination(_ name: String) -> RouteDestination {
        let item = MKMapItem(location: CLLocation(latitude: 40, longitude: -74), address: nil)
        item.name = name
        return RouteDestination(item: item)
    }
    @MainActor private func route() -> DiscoveryRoute {
        let points = [CLLocationCoordinate2D(latitude: 40, longitude: -74), .init(latitude: 40.001, longitude: -74)]
        return DiscoveryRoute(name: "Walk", distance: 120, travelTime: 100,
            polyline: MKPolyline(coordinates: points, count: points.count))
    }
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if await MainActor.run(body: condition) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Route operation did not settle")
        throw URLError(.timedOut)
    }

    func testLateSearchCannotReplaceNewSearchAndWhitespaceDoesNotRequest() async throws {
        let (client, model) = await MainActor.run { let c = ControlledRouteClient(); return (c, RoutePreviewModel(client: c)) }
        await MainActor.run { model.search("  ", near: nil); XCTAssertTrue(client.queries.isEmpty); model.search(" old ", near: nil) }
        try await waitUntil { client.searches.count == 1 }
        await MainActor.run { model.search("new", near: nil) }
        try await waitUntil { client.searches.count == 2 }
        await MainActor.run {
            XCTAssertEqual(client.queries, ["old", "new"])
            client.searches[1].resume(returning: [destination("New")])
        }
        try await waitUntil { model.destinations.first?.name == "New" }
        await MainActor.run { client.searches[0].resume(returning: [destination("Old")]) }
        try await waitUntil { client.finishedSearches == 2 }
        await MainActor.run {
            XCTAssertEqual(model.destinations.map(\.name), ["New"])
            XCTAssertFalse(model.isLoading)
            model.clear()
        }
    }
    func testSingleRouteSelectionClearAndLateRoutingResponse() async throws {
        let (client, model) = await MainActor.run { let c = ControlledRouteClient(); return (c, RoutePreviewModel(client: c)) }
        await MainActor.run { model.loadRoutes(to: destination("Park"), from: .init(latitude: 40, longitude: -74)) }
        try await waitUntil { client.requests.count == 1 }
        await MainActor.run { client.requests[0].resume(returning: [route()]) }
        try await waitUntil { model.routes.count == 1 }
        await MainActor.run {
            XCTAssertEqual(model.routes.count, 1)
            XCTAssertEqual(model.selectedRouteID, model.routes.first?.id)
            model.select(route())
            XCTAssertEqual(model.selectedRouteID, model.routes.first?.id, "Unknown routes cannot be selected")
            model.loadRoutes(to: destination("Other"), from: .init(latitude: 40, longitude: -74))
        }
        try await waitUntil { client.requests.count == 2 }
        await MainActor.run { model.clear(); client.requests[1].resume(returning: [route()]) }
        try await waitUntil { client.finishedRoutes == 2 }
        await MainActor.run {
            XCTAssertTrue(model.routes.isEmpty)
            XCTAssertNil(model.destination)
            XCTAssertNil(model.selectedRouteID)
            XCTAssertFalse(model.isLoading)
        }
    }
    func testMissingOriginNoRoutesAndNetworkFailure() async throws {
        let (client, model) = await MainActor.run { let c = ControlledRouteClient(); return (c, RoutePreviewModel(client: c)) }
        await MainActor.run {
            model.loadRoutes(to: destination("Park"), from: nil)
            XCTAssertTrue(client.requests.isEmpty)
            XCTAssertNotNil(model.message)
            model.loadRoutes(to: destination("Park"), from: .init(latitude: 40, longitude: -74))
        }
        try await waitUntil { client.requests.count == 1 }
        await MainActor.run { client.requests[0].resume(returning: []) }
        try await waitUntil { model.message != nil }
        await MainActor.run {
            XCTAssertEqual(model.message, "No walking route found. Try another destination.")
            model.search("Park", near: nil)
        }
        try await waitUntil { client.searches.count == 1 }
        await MainActor.run { client.searches[0].resume(throwing: URLError(.notConnectedToInternet)) }
        try await waitUntil { model.message?.contains("connection") == true }
        await MainActor.run {
            XCTAssertTrue(model.message?.contains("connection") == true)
            XCTAssertFalse(model.isLoading)
            model.clear()
        }
    }
    func testCancellationBeforeTaskStartsDoesNotIssueRequests() async throws {
        let (client, model) = await MainActor.run {
            let client = ControlledRouteClient()
            let model = RoutePreviewModel(client: client)
            model.search("Park", near: nil)
            model.clear()
            model.loadRoutes(to: destination("Park"), from: .init(latitude: 40, longitude: -74))
            model.cancelPending()
            return (client, model)
        }
        // Give cancelled tasks an opportunity to start; the client deliberately ignores cancellation.
        try await Task.sleep(for: .milliseconds(50))
        await MainActor.run {
            XCTAssertTrue(client.queries.isEmpty)
            XCTAssertTrue(client.requests.isEmpty)
            XCTAssertFalse(model.isLoading)
            model.clear()
        }
    }

    func testOriginRequiresFreshValidAccurateSample() async throws {
        await MainActor.run {
            let now = Date()
            func location(age: Double, accuracy: Double = 10, latitude: Double = 40) -> CLLocation {
                CLLocation(coordinate: .init(latitude: latitude, longitude: -74), altitude: 0,
                    horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: now.addingTimeInterval(-age))
            }
            XCTAssertNil(RoutePreviewModel.usableOrigin(nil, now: now))
            XCTAssertNil(RoutePreviewModel.usableOrigin(location(age: 61), now: now))
            XCTAssertNil(RoutePreviewModel.usableOrigin(location(age: -1), now: now))
            XCTAssertNil(RoutePreviewModel.usableOrigin(location(age: 0, accuracy: -1), now: now))
            XCTAssertNil(RoutePreviewModel.usableOrigin(location(age: 0, accuracy: 101), now: now))
            XCTAssertNil(RoutePreviewModel.usableOrigin(location(age: 0, latitude: 91), now: now))
            XCTAssertNotNil(RoutePreviewModel.usableOrigin(location(age: 30), now: now))
        }
    }
}
