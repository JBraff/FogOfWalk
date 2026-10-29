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
        let longCenter = try drawnPillCenter(in: long)
        XCTAssertEqual(long.iconCenter.x, longCenter.x, accuracy: 0.5)
        XCTAssertEqual(long.iconCenter.y, longCenter.y, accuracy: 0.5)
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
        XCTAssertFalse(view.isEnabled)
        XCTAssertFalse(view.isAccessibilityElement)
        XCTAssertNil(view.accessibilityLabel)
        XCTAssertNil(view.accessibilityIdentifier)
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

    /// A hidden window on the host scene; its Dark Mode override resolves attached views'
    /// traits. It is never made key or visible.
    private func darkWindow() async throws -> UIWindow {
        try await waitForLandmarkUI("SwiftUI connects a scene") { !UIApplication.shared.connectedScenes.isEmpty }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        window.overrideUserInterfaceStyle = .dark
        return window
    }

    func testReusedViewStaysZeroSizeUntilAttachmentResolvesItsAppearance() async throws {
        let view = makeView(annotation: annotation(discovered: true))
        XCTAssertGreaterThan(view.bounds.width, 0)
        view.prepareForReuse()
        view.annotation = annotation(discovered: true, name: "Reused")
        view.configure(traits: UITraitCollection(userInterfaceStyle: .unspecified))
        XCTAssertNil(view.image)
        XCTAssertEqual(view.bounds, .zero, "A deferred view must not keep its previous pin's size")
        XCTAssertEqual(view.centerOffset, .zero)
        XCTAssertFalse(view.isEnabled)
        let window = try await darkWindow()
        window.addSubview(view)
        let image = try XCTUnwrap(view.image, "Attachment draws a deferred view")
        XCTAssertEqual(view.bounds.size, image.size)
        XCTAssertTrue(view.isEnabled)
        XCTAssertEqual(view.accessibilityLabel, "Reused")
    }

    func testAttachmentRedrawsOnlyPinsThatChangedWhileDetached() async throws {
        // The container fixes the appearance, so moving it in and out of the window
        // fires no trait change and only the attachment hook can redraw.
        let container = UIView()
        container.overrideUserInterfaceStyle = .dark
        let model = annotation(discovered: false)
        let view = LandmarkAnnotationView(annotation: model, reuseIdentifier: "test")
        container.addSubview(view)
        view.configure(traits: UITraitCollection(userInterfaceStyle: .dark))
        let window = try await darkWindow()
        window.addSubview(container)
        let drawn = try XCTUnwrap(view.image)
        container.removeFromSuperview()
        window.addSubview(container)
        XCTAssertTrue(view.image === drawn, "Reattaching an unchanged view keeps its bitmap")
        container.removeFromSuperview()
        XCTAssertTrue(model.update(pin: annotation(discovered: true).pin))
        window.addSubview(container)
        XCTAssertFalse(view.image === drawn, "A pin changed while detached is redrawn on attachment")
        XCTAssertTrue(view.isEnabled)
        XCTAssertEqual(view.accessibilityLabel, "Test Museum")
    }

    func testAttachedViewFallsBackToItsOwnAppearanceWhenSuppliedTraitsAreUnresolved() async throws {
        let view = makeView(annotation: annotation(discovered: true))
        let window = try await darkWindow()
        window.addSubview(view)
        view.prepareForReuse()
        view.annotation = annotation(discovered: true, name: "Still attached")
        view.configure(traits: UITraitCollection(userInterfaceStyle: .unspecified))
        XCTAssertNotNil(view.image, "An attached view must not wait for an attachment that already happened")
        XCTAssertTrue(view.isEnabled)
        XCTAssertEqual(view.accessibilityLabel, "Still attached")
    }

    func testUnchangedBitmapStillRestoresInteractionState() {
        let view = makeView(annotation: annotation(discovered: true))
        let drawn = view.image
        view.isEnabled = false
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.accessibilityLabel = nil
        view.configure()
        XCTAssertTrue(view.image === drawn, "Restoring interaction must not rerasterize")
        XCTAssertTrue(view.isEnabled)
        XCTAssertTrue(view.isUserInteractionEnabled)
        XCTAssertTrue(view.isAccessibilityElement)
        XCTAssertEqual(view.accessibilityLabel, "Test Museum")
    }

    /// Measure the rendered pill using the shared top-left pixel accessor.
    private func drawnPillCenter(in view: LandmarkAnnotationView) throws -> CGPoint {
        let image = try XCTUnwrap(view.image)
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        let pixels = pixelBuffer(for: cgImage)
        func opaque(_ x: Int, _ y: Int) -> Bool {
            pixelColor(at: CGPoint(x: x, y: y), in: pixels, width: width, height: height).a > 0
        }
        // Scan the top connected band (the pill), stopping at the transparent
        // gap above the label. Measure both axes without any view-layout formula.
        let rows = (0..<height).prefix { y in (0..<width).contains { opaque($0, y) } }
        let columns = (0..<width).filter { x in rows.contains { opaque(x, $0) } }
        let minX = try XCTUnwrap(columns.first), maxX = try XCTUnwrap(columns.last)
        XCTAssertFalse(rows.isEmpty)
        return CGPoint(x: CGFloat(minX + maxX + 1) / image.scale / 2,
                       y: CGFloat(rows.count) / image.scale / 2)
    }

    func testEveryCategoryHasAnIconIncludingUnavailableSymbolFallback() {
        XCTAssertEqual(Set(LandmarkAnnotationView.categoryIcon.keys), Set(LandmarkStore.categoryRadius.keys))
        for category in LandmarkAnnotationView.categoryIcon.keys {
            let view = makeView(annotation: annotation(discovered: true, category: category))
            XCTAssertNotNil(view.image, category)
        }
    }
}
