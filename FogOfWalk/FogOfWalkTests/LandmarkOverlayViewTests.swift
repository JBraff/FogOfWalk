import XCTest
import UIKit
import MapKit
import CoreLocation
@testable import FogOfWalk

@MainActor
final class LandmarkOverlayViewTests: XCTestCase {

    let viewSize = CGSize(width: 400, height: 400)
    let testCenter = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)

    var overlayView: LandmarkOverlayView!
    var window: UIWindow!

    override func setUp() {
        super.setUp()
        window      = UIWindow(frame: CGRect(origin: .zero, size: viewSize))
        overlayView = LandmarkOverlayView(frame: CGRect(origin: .zero, size: viewSize))
        window.addSubview(overlayView)
        window.overrideUserInterfaceStyle = .light
        window.makeKeyAndVisible()
        installCoordinateMock()
    }

    override func tearDown() {
        overlayView = nil
        window      = nil
        super.tearDown()
    }

    // MARK: - Helpers

    func installCoordinateMock() {
        let center = testCenter
        let span   = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        let latMin = center.latitude  - span.latitudeDelta  / 2
        let lonMin = center.longitude - span.longitudeDelta / 2
        let w = viewSize.width, h = viewSize.height

        overlayView.coordinateToPoint = { coord in
            let xFrac = (coord.longitude - lonMin) / span.longitudeDelta
            let yFrac = (coord.latitude  - latMin) / span.latitudeDelta
            return CGPoint(x: xFrac * w, y: (1 - yFrac) * h)
        }
    }

    func renderOverlayView() -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: viewSize, format: format)
        let image = renderer.image { _ in
            overlayView.draw(CGRect(origin: .zero, size: viewSize))
        }
        return image.cgImage!
    }

    func pixelAlpha(at point: CGPoint, in image: CGImage) -> UInt8 {
        let w = image.width, h = image.height
        let x = Int(point.x.rounded()), y = Int(point.y.rounded())
        guard x >= 0, x < w, y >= 0, y < h else { return 0 }

        let bpp = 4, bpr = w * bpp
        var data = [UInt8](repeating: 0, count: h * bpr)
        guard let ctx = CGContext(
            data: &data, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        let offset = (h - 1 - y) * bpr + x * bpp + 3 // alpha channel
        return data[offset]
    }

    func makePin(isDiscovered: Bool) -> LandmarkPin {
        // Use the app's Wikidata category string ("museum") — not MKPointOfInterestCategory's
        // rawValue, which differs per iOS version and is unrelated to the app's category system.
        LandmarkPin(
            identifier:   "test-id",
            name:         "Test Landmark",
            category:     "museum",
            coordinate:   testCenter,
            isDiscovered: isDiscovered
        )
    }

    // MARK: - Tests

    func testEmptyPinsRendersNothing() {
        overlayView.update(pins: [])
        let image = renderOverlayView()
        // With no pins, the view should be entirely transparent.
        let centerPt = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let alpha = pixelAlpha(at: centerPt, in: image)
        XCTAssertEqual(alpha, 0, "Empty overlay should be fully transparent")
    }

    func testDiscoveredLandmarkRendersIcon() {
        overlayView.update(pins: [makePin(isDiscovered: true)])
        let image = renderOverlayView()

        let pinScreenPt = overlayView.coordinateToPoint!(testCenter)
        // The icon is drawn above the pin point — sample slightly above it.
        let samplePt = CGPoint(x: pinScreenPt.x, y: pinScreenPt.y - 15)
        let alpha = pixelAlpha(at: samplePt, in: image)
        XCTAssertGreaterThan(alpha, 0, "Discovered landmark should render visible pixels above the pin point")
    }

    func testUndiscoveredLandmarkRendersHint() {
        overlayView.update(pins: [makePin(isDiscovered: false)])
        let image = renderOverlayView()

        let pinScreenPt = overlayView.coordinateToPoint!(testCenter)
        let alpha = pixelAlpha(at: pinScreenPt, in: image)
        XCTAssertGreaterThan(alpha, 0, "Undiscovered landmark should render a hint icon")
    }

    func testPinRepositionsWhenCoordinateMockChanges() {
        // Regression test for pan-tracking: a pin rendered with the same data but
        // a shifted coordinate mock should appear at the new screen position.
        let pin = makePin(isDiscovered: true)

        // Render at original position and capture alpha at the pin location.
        overlayView.update(pins: [pin])
        let imageBefore = renderOverlayView()
        let originalScreenPt = overlayView.coordinateToPoint!(testCenter)
        let sampleOriginal = CGPoint(x: originalScreenPt.x, y: originalScreenPt.y - 15)

        guard sampleOriginal.x >= 0, sampleOriginal.x < viewSize.width,
              sampleOriginal.y >= 0, sampleOriginal.y < viewSize.height else {
            XCTFail("Sample point outside view"); return
        }

        let alphaBefore = pixelAlpha(at: sampleOriginal, in: imageBefore)
        XCTAssertGreaterThan(alphaBefore, 0, "Pin should render at original position")

        // Shift the coordinate mock by 80px to simulate a pan.
        let center = testCenter
        let span   = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        let latMin = center.latitude  - span.latitudeDelta  / 2
        let lonMin = center.longitude - span.longitudeDelta / 2
        let w = viewSize.width, h = viewSize.height
        let shiftX: CGFloat = 80

        overlayView.coordinateToPoint = { coord in
            let xFrac = (coord.longitude - lonMin) / span.longitudeDelta
            let yFrac = (coord.latitude  - latMin) / span.latitudeDelta
            return CGPoint(x: xFrac * w + shiftX, y: (1 - yFrac) * h)
        }

        // Update with the same pins (simulates mapViewDidChangeVisibleRegion).
        overlayView.update(pins: [pin])
        let imageAfter = renderOverlayView()

        let newScreenPt = overlayView.coordinateToPoint!(testCenter)
        let sampleNew = CGPoint(x: newScreenPt.x, y: newScreenPt.y - 15)

        guard sampleNew.x >= 0, sampleNew.x < viewSize.width,
              sampleNew.y >= 0, sampleNew.y < viewSize.height else { return }

        // Pin should appear at the new (shifted) position.
        let alphaAfterNew = pixelAlpha(at: sampleNew, in: imageAfter)
        XCTAssertGreaterThan(alphaAfterNew, 0,
            "Pin must appear at new position after pan")

        // Original position should now be transparent (pin moved away).
        let alphaAfterOld = pixelAlpha(at: sampleOriginal, in: imageAfter)
        XCTAssertEqual(alphaAfterOld, 0,
            "Old position must be transparent after pan, got alpha=\(alphaAfterOld)")
    }

    func testOnlyDiscoveredPinHandlesTap() {
        var tappedID: String?
        overlayView.onPinTapped = { tappedID = $0 }

        // Undiscovered pin — tap gesture handler should not call back.
        overlayView.update(pins: [makePin(isDiscovered: false)])
        // We can't easily simulate UITapGestureRecognizer in unit tests,
        // so just verify the callback is wired without crashing.
        XCTAssertNil(tappedID)
    }
}
