import XCTest
import MapKit
@testable import FogOfWalk

@MainActor
final class LandmarkAnnotationViewTests: XCTestCase {
    func annotation(discovered: Bool, category: String = "museum", name: String = "Test Museum") -> LandmarkAnnotation {
        LandmarkAnnotation(pin: LandmarkPin(identifier: "Q1", name: name, category: category,
            coordinate: CLLocationCoordinate2D(latitude: 40, longitude: -74), isDiscovered: discovered))
    }

    func makeView(annotation: LandmarkAnnotation) -> LandmarkAnnotationView {
        let view = LandmarkAnnotationView(annotation: annotation, reuseIdentifier: "test")
        view.configure(traits: UITraitCollection(userInterfaceStyle: .light))
        return view
    }

    func testShortNameKeepsSixtyPointIconHitAreaAndLongLabelPassesTouches() {
        let short = makeView(annotation: annotation(discovered: true, category: "zoo", name: "Zoo"))
        let center = CGPoint(x: short.bounds.midX, y: short.bounds.midY - short.centerOffset.y - 15)
        let oldTarget = CGPoint(x: center.x + 20, y: center.y)
        XCTAssertGreaterThan(oldTarget.x, short.bounds.maxX)
        XCTAssertTrue(short.hitTest(oldTarget, with: nil) === short)
        XCTAssertTrue(short.point(inside: CGPoint(x: center.x + 29, y: center.y), with: nil))
        XCTAssertFalse(short.point(inside: CGPoint(x: center.x + 31, y: center.y), with: nil))
        let long = makeView(annotation: annotation(discovered: true, name: String(repeating: "Wide label ", count: 8)))
        XCTAssertNil(long.hitTest(CGPoint(x: long.bounds.maxX - 2, y: long.bounds.maxY - 2), with: nil))
        let hint = makeView(annotation: annotation(discovered: false))
        XCTAssertFalse(hint.isUserInteractionEnabled)
        XCTAssertNil(hint.hitTest(CGPoint(x: hint.bounds.midX, y: hint.bounds.midY), with: nil))
        XCTAssertEqual(short.zPriority, .max)
        XCTAssertEqual(hint.zPriority, .min)
    }

    func testFirstDarkBitmapIsDeferredUntilMapTraitsAndReusedBeforeInsertion() {
        let view = LandmarkAnnotationView(annotation: annotation(discovered: true), reuseIdentifier: "test")
        XCTAssertNil(view.image, "Construction must not draw in an unspecified appearance")
        view.configure(traits: UITraitCollection(userInterfaceStyle: .dark))
        let first = view.image
        XCTAssertNotNil(first)
        view.prepareForDisplay()
        XCTAssertTrue(view.image === first, "Pre-window display must reuse the map's Dark Mode image")
        view.configure(traits: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertTrue(view.image === first)
        view.configure(traits: UITraitCollection(userInterfaceStyle: .light))
        XCTAssertFalse(view.image === first)
    }

    func testDiscoveredPinKeepsStylingAndRequiredPriority() throws {
        let view = makeView(annotation: annotation(discovered: true))
        XCTAssertTrue(view.isEnabled)
        XCTAssertTrue(view.hitTest(CGPoint(x: view.bounds.midX, y: view.bounds.midY), with: nil) === view)
        XCTAssertTrue(view.isAccessibilityElement)
        XCTAssertEqual(view.accessibilityLabel, "Test Museum")
        XCTAssertEqual(view.displayPriority, .required)
        XCTAssertNil(view.clusteringIdentifier)
        XCTAssertFalse(view.canShowCallout)
        XCTAssertFalse(view.isDraggable)
        let image = try XCTUnwrap(view.image)
        XCTAssertEqual(view.bounds.size, image.size)
        let icon = try XCTUnwrap(UIImage(systemName: "building.columns.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)))
        // The original pill and name layout places the anchor four points below the pill.
        XCTAssertEqual(view.bounds.midY - view.centerOffset.y, icon.size.height + 14, accuracy: 0.01)
        let unchanged = view.image
        view.configure()
        XCTAssertTrue(view.image === unchanged, "Unchanged pins must not rerasterize")
    }

    func testHintIsInertAndCenteredOnCoordinate() throws {
        let view = makeView(annotation: annotation(discovered: false))
        XCTAssertFalse(view.isEnabled)
        XCTAssertFalse(view.isAccessibilityElement)
        XCTAssertNil(view.accessibilityLabel)
        XCTAssertEqual(view.centerOffset, .zero)
        let icon = try XCTUnwrap(UIImage(systemName: "questionmark.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)))
        XCTAssertEqual(view.image!.size.width, icon.size.width, accuracy: 0.01)
        XCTAssertEqual(view.image!.size.height, icon.size.height, accuracy: 0.01)
    }

    func testDiscoveryUpdatesExistingViewAndReuseResetsAllPresentation() {
        let model = annotation(discovered: false)
        let view = makeView(annotation: model)
        let hint = view.image
        XCTAssertTrue(model.update(pin: annotation(discovered: true).pin))
        view.configure()
        XCTAssertTrue(view.isEnabled)
        XCTAssertEqual(view.accessibilityLabel, "Test Museum")
        XCTAssertFalse(view.image === hint)
        XCTAssertFalse(model.update(pin: model.pin))
        view.prepareForReuse()
        view.annotation = annotation(discovered: false, name: "Hidden name")
        view.prepareForDisplay()
        XCTAssertFalse(view.isEnabled)
        XCTAssertNil(view.accessibilityLabel)
        XCTAssertEqual(view.centerOffset, .zero)
        XCTAssertEqual(view.displayPriority, .required)
        view.annotation = annotation(discovered: true, category: "unknown", name: "Another place")
        view.prepareForDisplay()
        XCTAssertTrue(view.isEnabled)
        XCTAssertEqual(view.accessibilityLabel, "Another place")
        XCTAssertNotNil(view.image)
    }

    func testEveryCategoryHasAnIconIncludingUnavailableSymbolFallback() {
        XCTAssertEqual(Set(LandmarkAnnotationView.categoryIcon.keys), Set(LandmarkStore.categoryRadius.keys))
        for category in LandmarkAnnotationView.categoryIcon.keys {
            let view = makeView(annotation: annotation(discovered: true, category: category))
            XCTAssertNotNil(view.image, category)
        }
    }
}
