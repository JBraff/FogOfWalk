import XCTest
import SwiftUI
import MapKit
import CoreData
@testable import FogOfWalk

final class LandmarkMapObservationTests: XCTestCase {
    func testCountNeutralEditUpdatesHostedMapWithoutRebuildingParentOrMovingRegion() async throws {
        for _ in 0..<50 {
            if await MainActor.run(body: { !UIApplication.shared.connectedScenes.isEmpty }) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let fixture = try await MainActor.run { try MapObservationFixture() }
        let installed = await waitUntil { fixture.displayedName == "Before" }
        XCTAssertTrue(installed, "The hosted SwiftUI map must display its initial annotation")
        try await Task.sleep(for: .milliseconds(400))
        let parentCount = try await MainActor.run { () -> Int in
            let count = fixture.counter.bodies
            fixture.landmarks.allLandmarks.first!.name = "After"
            try fixture.landmarks.allLandmarks.first!.managedObjectContext!.save()
            return count
        }
        let updated = await waitUntil { fixture.displayedName == "After" }
        XCTAssertTrue(updated, "A count-neutral edit must refresh through SwiftUI without a region change")
        await MainActor.run {
            XCTAssertEqual(fixture.counter.bodies, parentCount, "Landmark observation belongs to the map child")
            fixture.close()
        }
    }

    private func waitUntil(_ check: @escaping @MainActor () -> Bool) async -> Bool {
        for _ in 0..<50 {
            if await MainActor.run(body: check) { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}

@MainActor
private final class MapObservationFixture {
    let landmarks: LandmarkStore
    let window: UIWindow
    let counter = BodyCounter()
    private let suite: UserDefaults
    private let suiteName = "LandmarkMapObservationTests-\(UUID().uuidString)"

    init() throws {
        let container = NSPersistentContainer(name: "FogOfWalk")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        container.loadPersistentStores { _, error in XCTAssertNil(error) }
        landmarks = LandmarkStore(container: container, defaults: nil)
        let center = CLLocationCoordinate2D(latitude: 40, longitude: -74)
        landmarks.addLandmarks([WikidataLandmark(id: "Q1", name: "Before", description: nil,
            lat: 40, lon: -74, category: "museum", imageURL: nil)],
            visitedCells: [GridMath.cellID(for: center)])
        let settings = GridSettings(defaults: nil)
        settings.showLandmarks = true
        suite = UserDefaults(suiteName: suiteName)!
        suite.set(true, forKey: LocationService.studyTrackingDisabledKey)
        let location = LocationService(manager: MockLocationManager(), isStudyApp: true, defaults: suite)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 400, height: 700)
        let root = ParentProbe(counter: counter, target: MapNavigationTarget(center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
            .environment(landmarks).environment(settings).environment(location)
            .environment(ExplorationStore(container: container))
            .environment(LandmarkSearchService(source: EmptyLandmarkSource()))
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
    }

    var displayedName: String? {
        guard let map = findMap(in: window),
              let annotation = map.annotations.compactMap({ $0 as? LandmarkAnnotation }).first else { return nil }
        return map.view(for: annotation)?.accessibilityLabel
    }

    private func findMap(in view: UIView) -> MKMapView? {
        if let map = view as? MKMapView { return map }
        return view.subviews.lazy.compactMap { self.findMap(in: $0) }.first
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
        suite.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class BodyCounter { var bodies = 0 }

private struct ParentProbe: View {
    let counter: BodyCounter
    let target: MapNavigationTarget
    var body: some View {
        let _ = counter.bodies += 1
        LandmarkMapView(navigateTo: target, highlightGeneration: 0, visitedCellCount: 0)
    }
}
