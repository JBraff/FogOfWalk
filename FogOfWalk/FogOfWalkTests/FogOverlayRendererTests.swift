import XCTest
import UIKit
import MapKit
import CoreLocation
@testable import FogOfWalk

@MainActor
final class FogOverlayRendererTests: XCTestCase {

    let viewSize   = CGSize(width: 400, height: 400)
    let testCenter = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
    let cellSize   = 50.0

    // Region used for the deterministic coordinate mock (300 m × 300 m)
    var region: MKCoordinateRegion {
        MKCoordinateRegion(center: testCenter, latitudinalMeters: 300, longitudinalMeters: 300)
    }

    var drawRect: CGRect { CGRect(origin: .zero, size: viewSize) }

    // MARK: - Helpers

    /// Linear lat/lon → CGPoint projection that maps `region` onto `viewSize`.
    func makeCoordinateConverter() -> (CLLocationCoordinate2D) -> CGPoint {
        makeCoordinateConverter(forRegion: region)
    }

    /// Same projection as `makeCoordinateConverter()` but over an arbitrary region, so tests
    /// can simulate a zoomed-out view (a much wider span mapped onto the same view size,
    /// shrinking the projected radius of a fixed-size cell) without touching real MapKit/zoomScale.
    func makeCoordinateConverter(forRegion r: MKCoordinateRegion) -> (CLLocationCoordinate2D) -> CGPoint {
        let latMin  = r.center.latitude  - r.span.latitudeDelta  / 2
        let lonMin  = r.center.longitude - r.span.longitudeDelta / 2
        let latSpan = r.span.latitudeDelta
        let lonSpan = r.span.longitudeDelta
        let w = viewSize.width
        let h = viewSize.height
        return { coord in
            let xFrac = (coord.longitude - lonMin) / lonSpan
            let yFrac = (coord.latitude  - latMin) / latSpan
            // UIKit y-axis: latitude increases upward → invert yFrac
            return CGPoint(x: xFrac * w, y: (1 - yFrac) * h)
        }
    }

    /// Renders fog using FogRenderer directly into a CGImage.
    func renderFog(cells: [CellID],
                   recentCells: [CellID] = [],
                   coordinateConverter: ((CLLocationCoordinate2D) -> CGPoint)? = nil,
                   minRadius: CGFloat = 0) -> CGImage {
        let converter = coordinateConverter ?? makeCoordinateConverter()
        let fogRenderer = FogRenderer()
        let format      = UIGraphicsImageRendererFormat()
        format.scale    = 1
        let imgRenderer = UIGraphicsImageRenderer(size: viewSize, format: format)
        let uiImage = imgRenderer.image { _ in
            guard let ctx = UIGraphicsGetCurrentContext() else { return }
            fogRenderer.render(cells: cells, recentCells: recentCells,
                               drawRect: drawRect, coordinateConverter: converter,
                               minRadius: minRadius, in: ctx)
        }
        return uiImage.cgImage!
    }

    /// Allocates an RGBA buffer and draws `image` into it once, for scanning multiple pixels
    /// without re-drawing the whole image per lookup.
    func pixelBuffer(for image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        let bpp = 4, bpr = w * bpp
        var data = [UInt8](repeating: 0, count: h * bpr)

        guard let ctx = CGContext(
            data: &data, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return data }

        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// Reads the RGBA of a single pixel from a pre-drawn buffer.
    func pixelColor(at point: CGPoint, in buffer: [UInt8], width: Int, height: Int)
        -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)
    {
        let x = Int(point.x.rounded()), y = Int(point.y.rounded())
        guard x >= 0, x < width, y >= 0, y < height else { return (0, 0, 0, 0) }

        let bpp = 4, bpr = width * bpp
        let offset = (height - 1 - y) * bpr + x * bpp
        return (buffer[offset], buffer[offset+1], buffer[offset+2], buffer[offset+3])
    }

    /// Reads the RGBA of a single pixel from a CGImage.
    func pixelColor(at point: CGPoint, in image: CGImage)
        -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)
    {
        let w = image.width, h = image.height
        let x = Int(point.x.rounded()), y = Int(point.y.rounded())
        guard x >= 0, x < w, y >= 0, y < h else { return (0, 0, 0, 0) }

        let buffer = pixelBuffer(for: image)
        return pixelColor(at: point, in: buffer, width: w, height: h)
    }

    func cellForTestCenter() -> CellID {
        GridMath.cellID(for: testCenter)
    }

    func viewPoint(for coord: CLLocationCoordinate2D) -> CGPoint {
        makeCoordinateConverter()(coord)
    }

    func holeRadius(for cell: CellID, minRadius: CGFloat = 0) -> CGFloat {
        let b     = GridMath.bounds(for: cell)
        let converter = makeCoordinateConverter()
        let minPt = converter(b.min)
        let maxPt = converter(b.max)
        let rawRadius = max(abs(maxPt.x - minPt.x), abs(maxPt.y - minPt.y)) * 0.9
        return max(rawRadius, minRadius)
    }

    // MARK: - FogOverlay tests

    func testFogOverlayBoundingRectIsWorld() {
        let overlay = FogOverlay()
        let rect    = overlay.boundingMapRect
        XCTAssertEqual(rect.origin.x,    MKMapRect.world.origin.x,    accuracy: 0.001)
        XCTAssertEqual(rect.origin.y,    MKMapRect.world.origin.y,    accuracy: 0.001)
        XCTAssertEqual(rect.size.width,  MKMapRect.world.size.width,  accuracy: 0.001)
        XCTAssertEqual(rect.size.height, MKMapRect.world.size.height, accuracy: 0.001)
    }

    // MARK: - Rendering tests

    func testFogCoversEntireViewWhenNoCellsVisited() {
        let image = renderFog(cells: [])

        for pt in [CGPoint(x: 200, y: 200), CGPoint(x: 50, y: 50), CGPoint(x: 350, y: 350)] {
            let pixel = pixelColor(at: pt, in: image)
            XCTAssertGreaterThan(Int(pixel.a), 200,
                "No visited cells — fog should be opaque at \(pt), got alpha=\(pixel.a)")
        }
    }

    func testHoleAppearsAtVisitedCellCenter() {
        let cell  = cellForTestCenter()
        let image = renderFog(cells: [cell])

        let coord = GridMath.center(for: cell)
        let pt    = viewPoint(for: coord)

        guard pt.x >= 0, pt.x < CGFloat(viewSize.width),
              pt.y >= 0, pt.y < CGFloat(viewSize.height) else {
            XCTFail("Cell center is outside view: \(pt)"); return
        }

        let pixel = pixelColor(at: pt, in: image)
        XCTAssertLessThan(Int(pixel.a), 30,
            "Visited cell center should be nearly transparent, got alpha=\(pixel.a)")
    }

    func testHoleCenterIsFullyTransparent() {
        let cell  = cellForTestCenter()
        let image = renderFog(cells: [cell])

        let coord = GridMath.center(for: cell)
        let pt    = viewPoint(for: coord)
        let pixel = pixelColor(at: pt, in: image)

        XCTAssertLessThan(Int(pixel.a), 10,
            "Hole center must be fully transparent, got alpha=\(pixel.a)")
    }

    func testHoleEdgeHasGradientFalloff() {
        let cell   = cellForTestCenter()
        let image  = renderFog(cells: [cell])

        let coord  = GridMath.center(for: cell)
        let center = viewPoint(for: coord)
        let radius = holeRadius(for: cell)

        // Sample at 85% of radius — inside the 70–100% gradient fade zone.
        let edgePt = CGPoint(x: center.x + radius * 0.85, y: center.y)
        guard edgePt.x >= 0, edgePt.x < CGFloat(viewSize.width),
              edgePt.y >= 0, edgePt.y < CGFloat(viewSize.height) else { return }

        let pixel = pixelColor(at: edgePt, in: image)
        XCTAssertGreaterThan(Int(pixel.a), 50,
            "Edge should still carry some fog, got alpha=\(pixel.a)")
        XCTAssertLessThan(Int(pixel.a), 220,
            "Edge should not be fully opaque (gradient fade), got alpha=\(pixel.a)")
    }

    func testFogRemainsOutsideHoleRadius() {
        let cell  = cellForTestCenter()
        let image = renderFog(cells: [cell])

        let pixel = pixelColor(at: CGPoint(x: 10, y: 10), in: image)
        XCTAssertGreaterThan(Int(pixel.a), 200,
            "Fog must remain fully opaque far from any visited cell, got alpha=\(pixel.a)")
    }

    func testMultipleAdjacentHolesMerge() {
        let cell1 = cellForTestCenter()
        let cell2 = CellID(x: cell1.x + 1, y: cell1.y)
        let image = renderFog(cells: [cell1, cell2])

        let converter = makeCoordinateConverter()
        let c1 = GridMath.center(for: cell1)
        let c2 = GridMath.center(for: cell2)
        let midCoord = CLLocationCoordinate2D(
            latitude:  (c1.latitude  + c2.latitude)  / 2,
            longitude: (c1.longitude + c2.longitude) / 2
        )
        let midPt = converter(midCoord)

        guard midPt.x >= 0, midPt.x < CGFloat(viewSize.width),
              midPt.y >= 0, midPt.y < CGFloat(viewSize.height) else {
            XCTFail("Midpoint is outside view: \(midPt)"); return
        }

        let pixel = pixelColor(at: midPt, in: image)
        XCTAssertLessThan(Int(pixel.a), 30,
            "Midpoint between adjacent cells should be transparent, got alpha=\(pixel.a)")
    }

    func testBlendModeIsDestinationOut() {
        let cell  = cellForTestCenter()
        let image = renderFog(cells: [cell])

        // Far corner must still be fully foggy.
        let corner = pixelColor(at: CGPoint(x: 5, y: 5), in: image)
        XCTAssertGreaterThan(Int(corner.a), 200,
            ".destinationOut: far fog must stay opaque, got alpha=\(corner.a)")

        // Cell center must be transparent.
        let coord    = GridMath.center(for: cell)
        let centerPt = viewPoint(for: coord)
        let center   = pixelColor(at: centerPt, in: image)
        XCTAssertLessThan(Int(center.a), 30,
            ".destinationOut: hole center must be transparent, got alpha=\(center.a)")
    }

    func testRenderWithNoCellsProducesFullFog() {
        let image       = renderFog(cells: [])
        let centerPixel = pixelColor(at: CGPoint(x: 200, y: 200), in: image)
        XCTAssertGreaterThan(Int(centerPixel.a), 200,
            "No cells: center should be fully fogged, got alpha=\(centerPixel.a)")
    }

    /// At a "zoomed out" projection (wide region over the same view size), the raw
    /// projected radius of a single 50m cell shrinks toward zero and the hole would
    /// otherwise vanish. Passing a minRadius floor should keep it visibly punched.
    func testHoleRadiusHasMinimumFloorAtLowZoom() {
        let cell = cellForTestCenter()
        let zoomedOutRegion = MKCoordinateRegion(
            center: testCenter, latitudinalMeters: 300_000, longitudinalMeters: 300_000)
        let converter = makeCoordinateConverter(forRegion: zoomedOutRegion)

        let floor: CGFloat = 5.0
        let unfloored = renderFog(cells: [cell], coordinateConverter: converter, minRadius: 0)
        let floored   = renderFog(cells: [cell], coordinateConverter: converter, minRadius: floor)

        let coord = GridMath.center(for: cell)
        let pt    = converter(coord)

        let unflooredPixel = pixelColor(at: pt, in: unfloored)
        XCTAssertGreaterThan(Int(unflooredPixel.a), 200,
            "Sanity check: without a floor, a cell at 30km span should be effectively invisible, got alpha=\(unflooredPixel.a)")

        let flooredPixel = pixelColor(at: pt, in: floored)
        XCTAssertLessThan(Int(flooredPixel.a), 30,
            "With a minRadius floor, the cell center should still be punched transparent, got alpha=\(flooredPixel.a)")
    }

    // MARK: - Highlight tests

    func testHighlightTintAppearsAtRecentCellCenter() {
        let cell  = cellForTestCenter()
        let image = renderFog(cells: [cell], recentCells: [cell])

        let coord = GridMath.center(for: cell)
        let pt    = viewPoint(for: coord)

        guard pt.x >= 0, pt.x < CGFloat(viewSize.width),
              pt.y >= 0, pt.y < CGFloat(viewSize.height) else {
            XCTFail("Cell center is outside view: \(pt)"); return
        }

        // The gold gradient is drawn on top of the transparent hole.
        // The center should have low alpha (hole is punched) but a warm color (gold tint).
        let pixel = pixelColor(at: pt, in: image)
        // Red channel should be higher than blue (gold tint).
        XCTAssertGreaterThan(Int(pixel.r), Int(pixel.b),
            "Recent cell center should have warm tint (r>\(pixel.b)), got r=\(pixel.r) b=\(pixel.b)")
        // Should have some alpha from the gold gradient.
        XCTAssertGreaterThan(Int(pixel.a), 5,
            "Recent cell center should have some alpha from gold tint, got alpha=\(pixel.a)")
    }

    func testNoHighlightTintOnNonRecentVisitedCell() {
        let cell  = cellForTestCenter()
        // Visited but NOT recent — no highlight.
        let image = renderFog(cells: [cell], recentCells: [])

        let coord = GridMath.center(for: cell)
        let pt    = viewPoint(for: coord)

        guard pt.x >= 0, pt.x < CGFloat(viewSize.width),
              pt.y >= 0, pt.y < CGFloat(viewSize.height) else {
            XCTFail("Cell center is outside view: \(pt)"); return
        }

        let pixel = pixelColor(at: pt, in: image)
        // Hole is punched — should be nearly transparent with no strong color bias.
        XCTAssertLessThan(Int(pixel.a), 30,
            "Non-recent visited cell center should be transparent, got alpha=\(pixel.a)")
    }

    // MARK: - Reinstatement guards (Plan C)

    /// Guards against `.drawsAfterEndLocation` being reinstated on a gradient with a
    /// non-zero end alpha, which would fill the entire clip region rather than just the
    /// cell's disk. Scans every pixel rather than a couple of hand-picked corners.
    func testFogOpaqueEverywhereBeyondHoleRadius() {
        let cell   = cellForTestCenter()
        let image  = renderFog(cells: [cell])
        let buffer = pixelBuffer(for: image)

        let coord  = GridMath.center(for: cell)
        let center = viewPoint(for: coord)
        let radius = holeRadius(for: cell)
        let slack: CGFloat = 2

        for y in 0..<image.height {
            for x in 0..<image.width {
                let pt = CGPoint(x: x, y: y)
                let dist = hypot(pt.x - center.x, pt.y - center.y)
                guard dist > radius + slack else { continue }
                let pixel = pixelColor(at: pt, in: buffer, width: image.width, height: image.height)
                XCTAssertGreaterThan(Int(pixel.a), 200,
                    "Fog must be opaque beyond hole radius at \(pt), got alpha=\(pixel.a)")
            }
        }
    }

    /// Guards the highlight gradient against the same reinstatement risk as above —
    /// far from the recent cell, fog should match plain (untinted) fog exactly.
    func testHighlightDoesNotTintFarOutsideRadius() {
        let cell     = cellForTestCenter()
        let baseline = renderFog(cells: [cell], recentCells: [])
        let tinted   = renderFog(cells: [cell], recentCells: [cell])

        let pt = CGPoint(x: 10, y: 10)
        let basePixel   = pixelColor(at: pt, in: baseline)
        let tintedPixel = pixelColor(at: pt, in: tinted)

        XCTAssertGreaterThan(Int(basePixel.a), 200,
            "Fog far from the recent cell should remain opaque, got alpha=\(basePixel.a)")
        XCTAssertEqual(basePixel.r, tintedPixel.r, "Far fog should be untinted by the highlight gradient")
        XCTAssertEqual(basePixel.g, tintedPixel.g, "Far fog should be untinted by the highlight gradient")
        XCTAssertEqual(basePixel.b, tintedPixel.b, "Far fog should be untinted by the highlight gradient")
        XCTAssertEqual(basePixel.a, tintedPixel.a, "Far fog should be untinted by the highlight gradient")
    }

    func testEmptyRecentCellsMatchesBaseRendering() {
        let cell     = cellForTestCenter()
        let baseline = renderFog(cells: [cell], recentCells: [])
        let withEmpty = renderFog(cells: [cell], recentCells: [])

        // Sample several pixels — both images should be identical.
        for pt in [CGPoint(x: 200, y: 200), CGPoint(x: 50, y: 50), CGPoint(x: 10, y: 10)] {
            let b = pixelColor(at: pt, in: baseline)
            let w = pixelColor(at: pt, in: withEmpty)
            XCTAssertEqual(b.a, w.a, "Alpha should match at \(pt) with empty recent cells")
        }
    }
}
