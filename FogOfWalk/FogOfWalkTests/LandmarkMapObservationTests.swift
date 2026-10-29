import XCTest
import SwiftUI
import MapKit
import CoreData
@testable import FogOfWalk

final class LandmarkMapObservationTests: XCTestCase {
    func testCountNeutralEditUpdatesHostedMapWithoutRebuildingParentOrMovingRegion() async throws {
        try await waitForLandmarkUI("SwiftUI connects a scene") {
            !UIApplication.shared.connectedScenes.isEmpty
        }
        let fixture = try await MainActor.run { try MapObservationFixture() }
        addTeardownBlock { await MainActor.run { fixture.close() } }
        try await waitForLandmarkUI("The hosted map displays its initial annotation") { fixture.readyForEdit }
        let parentCount = await MainActor.run { fixture.counter.bodies }
        // A parent that observed landmarks would rebuild at least once per separately
        // displayed edit. Tolerating fewer rebuilds than edits keeps an unrelated late
        // SwiftUI pass from failing the test, so the readiness quiet window only reduces noise.
        let edits = 3
        for edit in 1...edits {
            let name = "After \(edit)"
            try await MainActor.run {
                fixture.landmarks.allLandmarks.first!.name = name
                try fixture.landmarks.allLandmarks.first!.managedObjectContext!.save()
            }
            try await waitForLandmarkUI("A count-neutral edit refreshes without a region change") {
                fixture.displayedName == name
            }
        }
        await MainActor.run {
            XCTAssertLessThan(fixture.counter.bodies - parentCount, edits,
                              "Landmark observation belongs to the map child")
        }
    }

    func testUnresolvedDelegateViewsAnchorOnRealMapAfterDarkAttachmentAndReuse() async throws {
        try await waitForLandmarkUI("SwiftUI connects a scene") { !UIApplication.shared.connectedScenes.isEmpty }
        for reused in [false, true] {
            let fixture = try await MainActor.run { try DeferredMapFixture(reused: reused) }
            addTeardownBlock { await MainActor.run { fixture.close() } }
            try await waitForLandmarkUI("MapKit displays and anchors the deferred annotation") { fixture.isReady }
            await MainActor.run { fixture.checkAndClose() }
        }
    }

}

@MainActor
private final class MapObservationFixture {
    let landmarks: LandmarkStore
    let window: UIWindow
    let counter = BodyCounter()
    private let previousKeyWindow: UIWindow?
    private var lastBodyCount = 0
    private var quietSince = ContinuousClock.now
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
        guard let view = map.view(for: annotation), view.image != nil else { return nil }
        return view.accessibilityLabel
    }

    var readyForEdit: Bool {
        guard displayedName == "Before" else { return false }
        if counter.bodies != lastBodyCount {
            lastBodyCount = counter.bodies
            quietSince = .now
            return false
        }
        return quietSince.duration(to: .now) >= .milliseconds(250)
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

/// The production delegate configures a fresh or hand-recycled view while its map has
/// unresolved traits. MapKit then requests that exact view during real placement. This
/// covers MapKit sizing and anchoring a late-drawn view, not MapKit's own reuse queue.
@MainActor
private final class DeferredMapFixture: NSObject, MKMapViewDelegate {
    let coordinator = makeLandmarkCoordinator()
    let map = UnresolvedAppearanceMap(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
    let annotation = LandmarkAnnotation(pin: LandmarkPin(identifier: "Q1", name: "Zoo", category: "zoo",
        coordinate: CLLocationCoordinate2D(latitude: 40, longitude: -74), isDiscovered: true))
    let marker: LandmarkAnnotationView
    let window: UIWindow
    private var delegateRequests = 0
    private var closed = false

    init(reused: Bool) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = map.frame
        window.overrideUserInterfaceStyle = .dark
        if reused {
            let old = LandmarkAnnotation(pin: LandmarkPin(identifier: "Q2", name: "Old label", category: "museum",
                coordinate: annotation.coordinate, isDiscovered: true))
            let recycled = LandmarkAnnotationView(annotation: old, reuseIdentifier: LandmarkAnnotationView.reuseID)
            recycled.configure(traits: UITraitCollection(userInterfaceStyle: .light))
            XCTAssertNotEqual(recycled.centerOffset, .zero)
            recycled.prepareForReuse()
            XCTAssertEqual(recycled.centerOffset, .zero)
            map.recycled = recycled
        }
        marker = try XCTUnwrap(coordinator.mapView(map, viewFor: annotation) as? LandmarkAnnotationView)
        XCTAssertNil(marker.image)
        XCTAssertFalse(marker.isAccessibilityElement)
        XCTAssertFalse(marker.isEnabled)
        super.init()
        map.setRegion(MKCoordinateRegion(center: annotation.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)), animated: false)
        map.delegate = self
        map.addAnnotation(annotation)
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(map)
        map.unresolved = false
        window.isHidden = false
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation === self.annotation else { return nil }
        delegateRequests += 1
        return marker
    }

    var isReady: Bool {
        guard delegateRequests > 0, map.view(for: annotation) === marker,
              marker.image != nil, marker.window === window, marker.isAccessibilityElement,
              marker.traitCollection.userInterfaceStyle == .dark else { return false }
        let error = anchorError(of: marker, for: annotation, in: map)
        return hypot(error.dx, error.dy) <= 1
    }

    func checkAndClose() {
        XCTAssertTrue(isReady)
        XCTAssertGreaterThan(marker.bounds.width, 0)
        XCTAssertEqual(marker.bounds.size, marker.image?.size)
        let first = marker.image
        marker.prepareForDisplay()
        marker.configure(traits: map.traitCollection)
        XCTAssertTrue(marker.image === first)
        close()
    }

    func close() {
        guard !closed else { return }
        closed = true
        map.delegate = nil
        map.removeFromSuperview()
        window.isHidden = true
        window.rootViewController = nil
    }
}

@MainActor
private final class UnresolvedAppearanceMap: MKMapView {
    var unresolved = true
    var recycled: LandmarkAnnotationView?
    override var traitCollection: UITraitCollection {
        unresolved ? super.traitCollection.modifyingTraits { $0.userInterfaceStyle = .unspecified }
            : super.traitCollection
    }
    override func dequeueReusableAnnotationView(withIdentifier identifier: String) -> MKAnnotationView? {
        if let recycled {
            self.recycled = nil
            return recycled
        }
        return super.dequeueReusableAnnotationView(withIdentifier: identifier)
    }
}
