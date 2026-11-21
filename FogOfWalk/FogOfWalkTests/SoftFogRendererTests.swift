import XCTest
import UIKit
import MapKit
import CoreLocation
@testable import FogOfWalk

/// Trail and Spotlight drawing. Follows `FogOverlayRendererTests`: a linear projection of a
/// 300 m region onto a 400 pt view, where one cell is about 67 pt.
@MainActor
final class SoftFogRendererTests: XCTestCase {

    let viewSize   = CGSize(width: 400, height: 400)
    let testCenter = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)

    func converter(span meters: Double = 300) -> (CLLocationCoordinate2D) -> CGPoint {
        let r = MKCoordinateRegion(center: testCenter, latitudinalMeters: meters, longitudinalMeters: meters)
        let latMin = r.center.latitude  - r.span.latitudeDelta  / 2
        let lonMin = r.center.longitude - r.span.longitudeDelta / 2
        let size = viewSize
        return { coord in
            CGPoint(x: (coord.longitude - lonMin) / r.span.longitudeDelta * size.width,
                    y: (1 - (coord.latitude - latMin) / r.span.latitudeDelta) * size.height)
        }
    }

    func render(_ style: FogStyle, cells: [CellID], today: [CellID] = [],
                highlightActive: Bool = true, isDark: Bool = false,
                span: Double = 300) -> CGImage {
        let renderer = SoftFogRenderer()
        let convert = converter(span: span)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rect = CGRect(origin: .zero, size: viewSize)
        return UIGraphicsImageRenderer(size: viewSize, format: format).image { context in
            renderer.render(cells: cells, todayCells: today,
                            appearance: FogAppearance(style: style, highlightActive: highlightActive,
                                                      isDark: isDark),
                            drawRect: rect, coordinateConverter: convert, pointsPerUnit: 1,
                            in: context.cgContext)
        }.cgImage!
    }

    var center: CellID { GridMath.cellID(for: testCenter) }

    func point(_ cell: CellID, span: Double = 300) -> CGPoint {
        converter(span: span)(GridMath.center(for: cell))
    }

    // MARK: - Fog

    func testFogCoversTheViewWithoutCells() {
        for style in [FogStyle.trail, .spotlight] {
            let image = render(style, cells: [])
            for pt in [CGPoint(x: 10, y: 10), CGPoint(x: 200, y: 200), CGPoint(x: 390, y: 390)] {
                XCTAssertGreaterThan(Int(pixelColor(at: pt, in: image).a), 200, "\(style) at \(pt)")
            }
        }
    }

    /// The mask is drawn upside down if its rows are flipped the wrong way. A cell north-east
    /// of the centre must clear there and not at its mirror image to the south-east.
    func testOffCentreCellClearsInPlace() {
        let cell = CellID(x: center.x + 1, y: center.y + 1)
        let image = render(.trail, cells: [cell], today: [])
        let pt = point(cell)
        XCTAssertLessThan(pt.y, viewSize.height / 2 - 20, "Sanity check: the cell sits above the centre")
        XCTAssertLessThan(Int(pixelColor(at: pt, in: image).a), 30)
        XCTAssertGreaterThan(Int(pixelColor(at: CGPoint(x: pt.x, y: viewSize.height - pt.y), in: image).a), 200)
        XCTAssertGreaterThan(Int(pixelColor(at: CGPoint(x: viewSize.width - pt.x, y: pt.y), in: image).a), 200)
    }

    func testAdjacentCellsMergeAndFogStaysFarAway() {
        let a = center, b = CellID(x: center.x + 1, y: center.y)
        let image = render(.trail, cells: [a, b])
        let mid = CGPoint(x: (point(a).x + point(b).x) / 2, y: point(a).y)
        XCTAssertLessThan(Int(pixelColor(at: mid, in: image).a), 30)
        XCTAssertGreaterThan(Int(pixelColor(at: CGPoint(x: 10, y: 10), in: image).a), 200)
    }

    func testCellsStayVisibleWhenZoomedOut() {
        let span = 300_000.0
        let image = render(.trail, cells: [center], span: span)
        XCTAssertLessThan(Int(pixelColor(at: point(center, span: span), in: image).a), 80,
                          "The 3 pt minimum must keep a lone cell visible at country zoom")
    }

    func testDarkModeUsesADarkerFog() {
        let light = pixelColor(at: CGPoint(x: 10, y: 10), in: render(.trail, cells: []))
        let dark  = pixelColor(at: CGPoint(x: 10, y: 10), in: render(.trail, cells: [], isDark: true))
        XCTAssertLessThan(Int(dark.r) + Int(dark.g) + Int(dark.b), Int(light.r) + Int(light.g) + Int(light.b))
    }

    // MARK: - Spotlight

    func testSpotlightVeilsEarlierWalksWhileTheHighlightIsOn() {
        let earlier = center, today = CellID(x: center.x + 1, y: center.y + 1)
        let image = render(.spotlight, cells: [earlier, today], today: [today])
        let veil = Int(pixelColor(at: point(earlier), in: image).a)
        XCTAssertGreaterThan(veil, 40, "Earlier walks keep a light veil")
        XCTAssertLessThan(veil, 160, "The veil is lighter than the fog")
        XCTAssertLessThan(Int(pixelColor(at: point(today), in: image).a), 30)

        let off = render(.spotlight, cells: [earlier, today], today: [], highlightActive: false)
        XCTAssertLessThan(Int(pixelColor(at: point(earlier), in: off).a), 30,
                          "With the highlight off, every visited cell is clear")
    }

    // MARK: - Trail

    func isTrail(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
        p.a > 200 && p.r > 200 && p.g < 150 && p.b < 120
    }

    func testTrailRunsThroughTodaysCells() {
        let a = center, b = CellID(x: center.x + 1, y: center.y)
        let image = render(.trail, cells: [a, b], today: [a, b])
        let mid = CGPoint(x: (point(a).x + point(b).x) / 2, y: point(a).y)
        XCTAssertTrue(isTrail(pixelColor(at: point(a), in: image)))
        XCTAssertTrue(isTrail(pixelColor(at: mid, in: image)), "Neighbours are joined by a line")
        // Off the line, the cell is clear map.
        let beside = CGPoint(x: point(a).x, y: point(a).y + 15)
        XCTAssertLessThan(Int(pixelColor(at: beside, in: image).a), 30)
    }

    func testLoneTodayCellShowsADot() {
        let image = render(.trail, cells: [center], today: [center])
        XCTAssertTrue(isTrail(pixelColor(at: point(center), in: image)))
    }

    func testNoTrailWithoutTodayCells() {
        let image = render(.trail, cells: [center], today: [])
        XCTAssertLessThan(Int(pixelColor(at: point(center), in: image).a), 30)
    }

    // MARK: - Tile seams

    /// MapKit draws fog tile by tile. A blurred edge must come out the same whether a cell is
    /// drawn into one wide rectangle or into two adjacent tiles. Zoomed in, the blur reaches
    /// well past a fixed 24 pt, so the mask must be padded by the blur's real reach.
    func testTiledRenderingMatchesOneRectangleAcrossASeam() {
        let cellPoints: CGFloat = 100
        let tileWidth: CGFloat = 256
        let size = CGSize(width: tileWidth * 2, height: 256)
        let step = kCellSizeMeters / GridMath.metersPerDegree
        let origin = CellID(x: Int32(testCenter.longitude / step), y: Int32(testCenter.latitude / step))
        let convert: (CLLocationCoordinate2D) -> CGPoint = { coord in
            CGPoint(x: (coord.longitude / step - Double(origin.x)) * cellPoints,
                    y: (Double(origin.y) + 2 - coord.latitude / step) * cellPoints)
        }
        // Centre about 100 pt left of the seam at x = 256, as in the review case.
        let cell = CellID(x: origin.x + 1, y: origin.y)
        XCTAssertEqual(convert(GridMath.center(for: cell)).x, tileWidth - 106, accuracy: 1)

        func image(tiles: [CGRect]) -> CGImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                for tile in tiles {
                    SoftFogRenderer().render(cells: [cell], todayCells: [],
                                             appearance: FogAppearance(style: .trail),
                                             drawRect: tile, coordinateConverter: convert,
                                             pointsPerUnit: 1, in: context.cgContext)
                }
            }.cgImage!
        }
        let whole = image(tiles: [CGRect(origin: .zero, size: size)])
        let tiled = image(tiles: [CGRect(x: 0, y: 0, width: tileWidth, height: size.height),
                                  CGRect(x: tileWidth, y: 0, width: tileWidth, height: size.height)])
        let wholeBuffer = pixelBuffer(for: whole), tiledBuffer = pixelBuffer(for: tiled)
        let y = convert(GridMath.center(for: cell)).y
        for x in stride(from: tileWidth - 8, through: tileWidth + 8, by: 1) {
            let a = pixelColor(at: CGPoint(x: x, y: y), in: wholeBuffer, width: whole.width, height: whole.height).a
            let b = pixelColor(at: CGPoint(x: x, y: y), in: tiledBuffer, width: tiled.width, height: tiled.height).a
            XCTAssertLessThanOrEqual(abs(Int(a) - Int(b)), 3, "Fog differs across the seam at x = \(x)")
        }
    }

    func testReachCoversTheBlurAtEveryZoom() {
        for cellPoints: CGFloat in [0.5, 5, 20, 60, 100, 400] {
            let reach = SoftFogRenderer.reachPoints(cellPoints: cellPoints)
            XCTAssertGreaterThanOrEqual(reach, SoftFogRenderer.blurReachPoints(cellPoints: cellPoints)
                                        + max(cellPoints * SoftFogRenderer.holeRadiusFactor, 3))
        }
        XCTAssertGreaterThanOrEqual(SoftFogRenderer.blurReachPoints(cellPoints: 100), 56,
                                    "Four passes of the 15-pixel kernel spread 28 mask pixels")
    }

    // MARK: - Performance

    /// Zoomed out, the original style draws a gradient per cell while the soft styles fill one
    /// mask, so a dense tile must render no slower in Trail or Spotlight than in Original.
    func testDenseCityTileRendersNoSlowerThanOriginal() {
        let tile = CGRect(x: 0, y: 0, width: 256, height: 256)
        let cellsAcross = 512
        let cellPoints = tile.width / CGFloat(cellsAcross)
        let step = kCellSizeMeters / GridMath.metersPerDegree
        let origin = CellID(x: Int32(testCenter.longitude / step), y: Int32(testCenter.latitude / step))
        let convert: (CLLocationCoordinate2D) -> CGPoint = { coord in
            CGPoint(x: (coord.longitude / step - Double(origin.x)) * cellPoints,
                    y: (Double(origin.y) + Double(cellsAcross) - coord.latitude / step) * cellPoints)
        }
        // A deterministic random walk of 20,000 cells, 300 of them walked today.
        var seed: UInt64 = 7
        var visited = Set<CellID>()
        var x: Int32 = 256, y: Int32 = 256
        while visited.count < 20_000 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            switch seed >> 62 {
            case 0: x = min(x + 1, 511)
            case 1: x = max(x - 1, 0)
            case 2: y = min(y + 1, 511)
            default: y = max(y - 1, 0)
            }
            visited.insert(CellID(x: origin.x + x, y: origin.y + y))
        }
        let cells = Array(visited)
        let today = Array(cells.prefix(300))

        func median(_ draw: (CGContext) -> Void) -> Double {
            var times: [Double] = []
            for _ in 0..<5 {
                let ctx = CGContext(data: nil, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.scaleBy(x: 2, y: 2)
                let start = CFAbsoluteTimeGetCurrent()
                draw(ctx)
                times.append(CFAbsoluteTimeGetCurrent() - start)
            }
            return times.sorted()[2]
        }
        let original = FogRenderer(), soft = SoftFogRenderer()
        let originalTime = median {
            original.render(cells: cells, recentCells: today, drawRect: tile,
                            coordinateConverter: convert, minRadius: 3, in: $0)
        }
        for style in [FogStyle.trail, .spotlight] {
            let softTime = median {
                soft.render(cells: cells, todayCells: today,
                            appearance: FogAppearance(style: style, highlightActive: true),
                            drawRect: tile, coordinateConverter: convert, pointsPerUnit: 1, in: $0)
            }
            XCTContext.runActivity(named: String(format: "%@: %.1f ms, original %.1f ms",
                                                 style.title, softTime * 1000, originalTime * 1000)) { _ in }
            XCTAssertLessThanOrEqual(softTime, originalTime,
                "\(style): \(softTime * 1000) ms vs original \(originalTime * 1000) ms")
        }
    }
}
