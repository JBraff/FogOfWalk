import XCTest
import SwiftUI
import MapKit
import CoreData
@testable import FogOfWalk

final class LandmarkMapObservationTests: XCTestCase {
    func testCountNeutralEditUpdatesHostedMapWithoutRebuildingParentOrMovingRegion() async throws {
        await waitUntil("SwiftUI connects a scene") {
            !UIApplication.shared.connectedScenes.isEmpty
        }
        let fixture = try await MainActor.run { try MapObservationFixture() }
        addTeardownBlock { await MainActor.run { fixture.close() } }
        await waitUntil("The hosted map displays its initial annotation") { fixture.displayedName == "Before" }
        let parentCount = try await MainActor.run { () -> Int in
            let count = fixture.counter.bodies
            fixture.landmarks.allLandmarks.first!.name = "After"
            try fixture.landmarks.allLandmarks.first!.managedObjectContext!.save()
            return count
        }
        await waitUntil("A count-neutral edit refreshes without a region change") { fixture.displayedName == "After" }
        await MainActor.run {
            XCTAssertEqual(fixture.counter.bodies, parentCount, "Landmark observation belongs to the map child")
        }
    }

    func testUnresolvedMapRendersWhenAttachedToDarkWindow() async throws {
        await waitUntil("SwiftUI connects a scene") { !UIApplication.shared.connectedScenes.isEmpty }
        try await MainActor.run {
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.overrideUserInterfaceStyle = .dark
            let controller = UIViewController()
            window.rootViewController = controller
            let annotation = LandmarkAnnotation(pin: LandmarkPin(identifier: "Q1", name: "Zoo", category: "zoo",
                coordinate: CLLocationCoordinate2D(latitude: 40, longitude: -74), isDiscovered: true))
            let view = LandmarkAnnotationView(annotation: annotation, reuseIdentifier: "test")
            view.configure(traits: UITraitCollection(userInterfaceStyle: .unspecified))
            XCTAssertNil(view.image)
            controller.view.addSubview(view)
            window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }
            window.layoutIfNeeded()
            let first = view.image
            XCTAssertNotNil(first)
            XCTAssertEqual(view.traitCollection.userInterfaceStyle, .dark)
            view.prepareForDisplay()
            view.configure(traits: UITraitCollection(userInterfaceStyle: .dark))
            XCTAssertTrue(view.image === first)
        }
    }

    private func waitUntil(_ description: String, _ check: @escaping @MainActor () -> Bool) async {
        let ready = expectation(description: description)
        // Sample UIKit on its actor while yielding for scene and MapKit work. The
        // expectation bounds the wait, with no fixed settle delay or attempt count.
        let polling = Task { @MainActor in
            while !Task.isCancelled {
                if check() {
                    ready.fulfill()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        await fulfillment(of: [ready], timeout: 15)
        polling.cancel()
    }
}

@MainActor
private final class MapObservationFixture {
    let landmarks: LandmarkStore
    let window: UIWindow
    let counter = BodyCounter()
    private let previousKeyWindow: UIWindow?
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
        previousKeyWindow = scene.windows.first { $0.isKeyWindow }
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
        previousKeyWindow?.makeKey()
        if let previousKeyWindow { XCTAssertTrue(previousKeyWindow.isKeyWindow) }
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
