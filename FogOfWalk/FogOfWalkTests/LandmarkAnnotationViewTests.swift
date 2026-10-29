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

    func testShortNameKeepsSixtyPointIconHitAreaAndLongLabelPassesTouches() throws {
        let short = makeView(annotation: annotation(discovered: true, category: "zoo", name: "Zoo"))
        let center = try drawnPillCenter(in: short)
        XCTAssertEqual(short.iconCenter.x, center.x, accuracy: 0.5)
        XCTAssertEqual(short.iconCenter.y, center.y, accuracy: 0.5)
        let oldTarget = CGPoint(x: center.x + 20, y: center.y)
        XCTAssertGreaterThan(oldTarget.x, short.bounds.maxX)
        XCTAssertTrue(short.hitTest(oldTarget, with: nil) === short)
        XCTAssertTrue(short.point(inside: CGPoint(x: center.x + 29, y: center.y), with: nil))
        XCTAssertFalse(short.point(inside: CGPoint(x: center.x + 31, y: center.y), with: nil))
        for direction in [CGPoint(x: 0, y: -1), CGPoint(x: 0, y: 1), CGPoint(x: -1, y: 0)] {
            XCTAssertTrue(short.point(inside: CGPoint(x: center.x + direction.x * 29,
                y: center.y + direction.y * 29), with: nil))
            XCTAssertFalse(short.point(inside: CGPoint(x: center.x + direction.x * 31,
                y: center.y + direction.y * 31), with: nil))
        }
        let long = makeView(annotation: annotation(discovered: true, name: String(repeating: "Wide label ", count: 8)))
        XCTAssertNil(long.hitTest(CGPoint(x: long.bounds.maxX - 2, y: long.bounds.maxY - 2), with: nil))
        let hint = makeView(annotation: annotation(discovered: false))
        XCTAssertFalse(hint.isUserInteractionEnabled)
        XCTAssertNil(hint.hitTest(CGPoint(x: hint.bounds.midX, y: hint.bounds.midY), with: nil))
        let user = HeadingUserLocationView(annotation: MKMapView().userLocation, reuseIdentifier: nil)
        XCTAssertGreaterThan(user.zPriority.rawValue, short.zPriority.rawValue)
        XCTAssertGreaterThan(user.selectedZPriority.rawValue, short.selectedZPriority.rawValue)
        XCTAssertGreaterThan(short.zPriority.rawValue, hint.zPriority.rawValue)
        XCTAssertEqual(hint.zPriority, .min)
    }

    func testFirstDarkBitmapIsDeferredUntilMapTraitsAndReusedBeforeInsertion() {
        let view = LandmarkAnnotationView(annotation: annotation(discovered: true), reuseIdentifier: "test")
        XCTAssertNil(view.image, "Construction must not draw in an unspecified appearance")
        view.configure(traits: MKMapView().traitCollection.modifyingTraits { $0.userInterfaceStyle = .unspecified })
        view.prepareForDisplay()
        XCTAssertNil(view.image, "An unattached map's unspecified traits must not trigger a placeholder draw")
        view.configure(traits: UITraitCollection(userInterfaceStyle: .dark))
        let first = view.image
        XCTAssertNotNil(first)
        view.prepareForDisplay()
        XCTAssertTrue(view.image === first, "Pre-window display must reuse the map's Dark Mode image")
        view.configure(traits: UITraitCollection(userInterfaceStyle: .unspecified))
        XCTAssertTrue(view.image === first, "Unresolved traits must preserve an already resolved image")
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
        view.configure(traits: UITraitCollection(userInterfaceStyle: .light))
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

    /// Read the first opaque run through the rendered pill's centre column. This
    /// measures the image, independently of the hit-test and anchor arithmetic.
    private func drawnPillCenter(in view: LandmarkAnnotationView) throws -> CGPoint {
        let image = try XCTUnwrap(view.image)
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let opaqueRows = (0..<height).prefix { pixels[($0 * width + width / 2) * 4 + 3] > 0 }
        XCTAssertFalse(opaqueRows.isEmpty)
        return CGPoint(x: view.bounds.midX, y: CGFloat(opaqueRows.count) / image.scale / 2)
    }

    func testEveryCategoryHasAnIconIncludingUnavailableSymbolFallback() {
        XCTAssertEqual(Set(LandmarkAnnotationView.categoryIcon.keys), Set(LandmarkStore.categoryRadius.keys))
        for category in LandmarkAnnotationView.categoryIcon.keys {
            let view = makeView(annotation: annotation(discovered: true, category: category))
            XCTAssertNotNil(view.image, category)
        }
    }
}
