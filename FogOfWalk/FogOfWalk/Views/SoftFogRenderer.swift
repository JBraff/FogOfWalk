import Accelerate
import CoreGraphics
import CoreLocation
import UIKit

// MARK: - SoftFogRenderer

/// Draws the Trail and Spotlight styles. Pure Core Graphics, like `FogRenderer`, so tests can
/// render it without MapKit.
///
/// Visited cells are painted as discs into a small greyscale mask (half a pixel per screen
/// point), blurred, and stretched over the tile to cut the fog. Overlapping discs merge into
/// one smooth shape instead of stacking, and the cost follows the tile size and the number of
/// cells in it, not one gradient per cell, so zoomed-out tiles with thousands of cells stay cheap.
struct SoftFogRenderer {

    /// How far the blur spreads a disc's edge, in screen points, for a cell of `cellPoints`:
    /// four box passes, each reaching half a kernel.
    static func blurReachPoints(cellPoints: CGFloat) -> CGFloat {
        let kernel = MaskCanvas.blurKernel(cellPixels: cellPoints * maskPixelsPerPoint)
        return kernel == 0 ? 0 : CGFloat(2 * (kernel - 1)) / maskPixelsPerPoint
    }

    /// Farthest a cell's drawing reaches from its centre, in screen points: the disc, its
    /// blur and the trail casing, plus a pixel of slack. `FogOverlayRenderer` reads cells this
    /// far outside a tile, and the map redraws this far around a changed cell, so a tile
    /// edge never cuts a soft edge.
    static func reachPoints(cellPoints: CGFloat) -> CGFloat {
        max(max(cellPoints * holeRadiusFactor, FogOverlayRenderer.kMinCellScreenPoints)
            + blurReachPoints(cellPoints: cellPoints), 5) + 2 / maskPixelsPerPoint
    }

    /// Mask resolution. Edges are blurred anyway, so a coarse mask looks the same and is cheap.
    static let maskPixelsPerPoint: CGFloat = 0.5
    /// Largest mask side in pixels, a guard for unusually large tiles.
    static let maxMaskPixels: CGFloat = 1024

    /// Hole radius as a fraction of the projected cell size.
    static let holeRadiusFactor: CGFloat = 0.78

    /// How much of the fog Spotlight removes over earlier walks while the highlight is on.
    static let spotlightClearing: CGFloat = 0.62

    /// On-screen size of one repeat of the fog texture.
    static let texturePeriodPoints: CGFloat = 256

    static let trailColor = UIColor(red: 1.0, green: 0.353, blue: 0.212, alpha: 1)   // #FF5A36
    static let trailColorDark = UIColor(red: 1.0, green: 0.416, blue: 0.271, alpha: 1) // #FF6A45

    private let lightFog    = UIColor(red: 0.655, green: 0.686, blue: 0.737, alpha: 0.92).cgColor // #A7AFBC
    private let darkFog     = UIColor(red: 0.290, green: 0.322, blue: 0.388, alpha: 0.92).cgColor // #4A5263
    private let lightCasing = UIColor(white: 1, alpha: 0.9).cgColor
    private let darkCasing  = UIColor(white: 0, alpha: 0.6).cgColor
    private let texture: CGImage?

    init() {
        texture = Self.makeTexture(size: 256)
    }

    /// Renders fog into `context` within `drawRect`.
    ///
    /// - Parameters:
    ///   - todayCells: cells in the today highlight; empty while it is off.
    ///   - pointsPerUnit: screen points per unit of `drawRect` (MapKit's `zoomScale`).
    func render(
        cells: [CellID],
        todayCells: [CellID],
        appearance: FogAppearance,
        drawRect: CGRect,
        coordinateConverter convert: (CLLocationCoordinate2D) -> CGPoint,
        pointsPerUnit: CGFloat,
        in context: CGContext
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: drawRect)
        context.interpolationQuality = .high

        // 1. Fog with a faint cloud texture.
        context.setFillColor(appearance.isDark ? darkFog : lightFog)
        context.fill(drawRect)
        drawTexture(in: drawRect, pointsPerUnit: pointsPerUnit, context: context)

        guard !cells.isEmpty else { return }

        // 2. Clear visited cells. Spotlight keeps a light veil over earlier walks while the
        //    highlight is on, then clears today's cells fully.
        // Every cell in one tile projects to the same size, so it is measured once.
        let cellSize = Self.projectedSize(of: cells[0], convert: convert)
        let radius = max(cellSize * Self.holeRadiusFactor,
                         FogOverlayRenderer.kMinCellScreenPoints / pointsPerUnit)
        let canvas = MaskCanvas(drawRect: drawRect, pointsPerUnit: pointsPerUnit,
                                radius: radius, cellSize: cellSize)
        let spotlight = appearance.style == .spotlight && appearance.highlightActive
        if let mask = canvas.mask(cells.map { convert(GridMath.center(for: $0)) }) {
            clear(mask, rect: canvas.rect, alpha: spotlight ? Self.spotlightClearing : 1, in: context)
        }
        if spotlight, !todayCells.isEmpty,
           let mask = canvas.mask(todayCells.map { convert(GridMath.center(for: $0)) }) {
            clear(mask, rect: canvas.rect, alpha: 1, in: context)
        }

        // 3. Trail through today's cells.
        if appearance.style == .trail, !todayCells.isEmpty {
            drawTrail(todayCells, cellSize: cellSize, isDark: appearance.isDark, convert: convert,
                      pointsPerUnit: pointsPerUnit, in: context)
        }
    }

    // MARK: Geometry

    /// Projected side of a cell in `drawRect` units.
    private static func projectedSize(of cell: CellID,
                                      convert: (CLLocationCoordinate2D) -> CGPoint) -> CGFloat {
        let b = GridMath.bounds(for: cell)
        let minPt = convert(b.min)
        let maxPt = convert(b.max)
        return max(abs(maxPt.x - minPt.x), abs(maxPt.y - minPt.y))
    }

    private func clear(_ mask: CGImage, rect: CGRect, alpha: CGFloat, in context: CGContext) {
        context.saveGState()
        context.clip(to: rect, mask: mask)
        context.setBlendMode(.destinationOut)
        context.setFillColor(gray: 0, alpha: alpha)
        context.fill(rect)
        context.restoreGState()
    }

    // MARK: Trail

    /// Joins neighbouring cells with round-capped lines. Orthogonal neighbours always join;
    /// a diagonal joins only when no orthogonal cell links the pair, so a straight walk does
    /// not draw a ladder of triangles. Each cell also gets a dot, so a lone cell still shows.
    private func drawTrail(_ cells: [CellID], cellSize: CGFloat, isDark: Bool,
                           convert: (CLLocationCoordinate2D) -> CGPoint,
                           pointsPerUnit: CGFloat, in context: CGContext) {
        let set = Set(cells)
        let path = CGMutablePath()
        for cell in cells {
            let p = convert(GridMath.center(for: cell))
            path.move(to: p)
            path.addLine(to: p)
            func link(_ dx: Int32, _ dy: Int32) {
                path.move(to: p)
                path.addLine(to: convert(GridMath.center(for: CellID(x: cell.x &+ dx, y: cell.y &+ dy))))
            }
            if set.contains(CellID(x: cell.x &+ 1, y: cell.y)) { link(1, 0) }
            if set.contains(CellID(x: cell.x, y: cell.y &+ 1)) { link(0, 1) }
            for dy: Int32 in [1, -1] where set.contains(CellID(x: cell.x &+ 1, y: cell.y &+ dy))
                && !set.contains(CellID(x: cell.x &+ 1, y: cell.y))
                && !set.contains(CellID(x: cell.x, y: cell.y &+ dy)) {
                link(1, dy)
            }
        }
        let width = min(max(cellSize * pointsPerUnit * 0.26, 2.5), 7)
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path)
        context.setStrokeColor(isDark ? darkCasing : lightCasing)
        context.setLineWidth((width + 3) / pointsPerUnit)
        context.strokePath()
        context.addPath(path)
        context.setStrokeColor((isDark ? Self.trailColorDark : Self.trailColor).cgColor)
        context.setLineWidth(width / pointsPerUnit)
        context.strokePath()
        context.restoreGState()
    }

    // MARK: Texture

    /// Tiles the texture on a grid anchored to the map, not the tile, so it lines up across
    /// tile seams.
    private func drawTexture(in rect: CGRect, pointsPerUnit: CGFloat, context: CGContext) {
        guard let texture else { return }
        let period = Self.texturePeriodPoints / pointsPerUnit
        var y = (rect.minY / period).rounded(.down) * period
        while y < rect.maxY {
            var x = (rect.minX / period).rounded(.down) * period
            while x < rect.maxX {
                context.draw(texture, in: CGRect(x: x, y: y, width: period, height: period))
                x += period
            }
            y += period
        }
    }

    /// Seamless value noise: faint light and dark patches.
    private static func makeTexture(size n: Int) -> CGImage? {
        var seed: UInt64 = 0x5EED
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        var value = [Double](repeating: 0, count: n * n)
        for (octave, amplitude) in [(4, 0.5), (8, 0.3), (16, 0.2)] {
            let grid = (0..<(octave * octave)).map { _ in random() }
            for y in 0..<n {
                for x in 0..<n {
                    let fx = Double(x) / Double(n) * Double(octave)
                    let fy = Double(y) / Double(n) * Double(octave)
                    let x0 = Int(fx) % octave, y0 = Int(fy) % octave
                    let x1 = (x0 + 1) % octave, y1 = (y0 + 1) % octave
                    let tx = fx - fx.rounded(.down), ty = fy - fy.rounded(.down)
                    let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
                    let top    = grid[y0 * octave + x0] * (1 - sx) + grid[y0 * octave + x1] * sx
                    let bottom = grid[y1 * octave + x0] * (1 - sx) + grid[y1 * octave + x1] * sx
                    value[y * n + x] += (top * (1 - sy) + bottom * sy) * amplitude
                }
            }
        }
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<(n * n) {
            let alpha = abs(value[i] - 0.5) * 2 * 0.07
            let level = (value[i] > 0.5 ? 255 : 30) * alpha   // premultiplied
            pixels[i * 4]     = UInt8(level)
            pixels[i * 4 + 1] = UInt8(level)
            pixels[i * 4 + 2] = UInt8(level)
            pixels[i * 4 + 3] = UInt8(alpha * 255)
        }
        return pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8,
                      bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }
}

// MARK: - MaskCanvas

/// A greyscale mask covering a tile plus the blur's reach, where white clears the fog. The
/// padding keeps the blur near a tile edge reading real cells rather than repeated edge
/// pixels, so adjacent tiles match at their seam.
private struct MaskCanvas {
    let rect: CGRect
    let width: Int
    let height: Int
    let pixelsPerUnit: CGFloat
    /// Disc radius in mask pixels, the same for every cell in the tile.
    let radius: CGFloat
    let blurKernel: Int

    init(drawRect: CGRect, pointsPerUnit: CGFloat, radius: CGFloat, cellSize: CGFloat) {
        let slack = 2 / SoftFogRenderer.maskPixelsPerPoint
        let pad = (SoftFogRenderer.blurReachPoints(cellPoints: cellSize * pointsPerUnit) + slack)
            / pointsPerUnit
        rect = drawRect.insetBy(dx: -pad, dy: -pad)
        pixelsPerUnit = min(SoftFogRenderer.maskPixelsPerPoint * pointsPerUnit,
                            SoftFogRenderer.maxMaskPixels / max(rect.width, rect.height))
        width  = max(1, Int((rect.width  * pixelsPerUnit).rounded(.up)))
        height = max(1, Int((rect.height * pixelsPerUnit).rounded(.up)))
        self.radius = max(radius * pixelsPerUnit, 1)
        // A capped mask has fewer pixels per point; keep the blur within the padding anyway.
        // Four passes of kernel k spread 2(k - 1) pixels; use the largest odd k that fits.
        let largest = Int(pad * pixelsPerUnit) / 2 + 1
        let fitting = largest >= 3 ? (largest % 2 == 1 ? largest : largest - 1) : 0
        blurKernel = min(Self.blurKernel(cellPixels: cellSize * pixelsPerUnit), fitting)
    }

    func mask(_ centers: [CGPoint]) -> CGImage? {
        guard !centers.isEmpty,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        // Discs are painted straight into the pixels: filling thousands of overlapping
        // ellipses as one Core Graphics path takes seconds. `clip(to:mask:)` treats the
        // bitmap's last row as the top of `rect`, so rows are flipped here
        // (`testOffCentreCellClearsInPlace`).
        let rowBytes = ctx.bytesPerRow
        let r = radius
        let inner = r > 0.5 ? (r - 0.5) * (r - 0.5) : 0
        let outer = (r + 0.5) * (r + 0.5)
        for center in centers {
            let cx = (center.x - rect.minX) * pixelsPerUnit
            let cy = CGFloat(height) - (center.y - rect.minY) * pixelsPerUnit
            let x0 = Swift.max(0, Int((cx - r).rounded(.down)))
            let x1 = Swift.min(width - 1, Int((cx + r).rounded(.up)))
            let y0 = Swift.max(0, Int((cy - r).rounded(.down)))
            let y1 = Swift.min(height - 1, Int((cy + r).rounded(.up)))
            guard x0 <= x1, y0 <= y1 else { continue }
            var y = y0
            while y <= y1 {
                let row = data + y * rowBytes
                if r <= 2 {
                    // Zoomed-out cells are a few pixels wide: a solid block is enough, and
                    // the stretched mask rounds it.
                    memset(row + x0, 255, x1 - x0 + 1)
                } else {
                    paintRow(row, y: y, cx: cx, cy: cy, x0: x0, x1: x1, inner: inner, outer: outer)
                }
                y += 1
            }
        }
        blur(ctx, kernel: blurKernel)
        return ctx.makeImage()
    }

    /// Fills the solid middle of one disc row with `memset` and antialiases only the edge
    /// pixels, keeping the larger value where discs overlap. Plain `while` loops keep it fast
    /// in unoptimised builds too.
    private func paintRow(_ row: UnsafeMutablePointer<UInt8>, y: Int, cx: CGFloat, cy: CGFloat,
                          x0: Int, x1: Int, inner: CGFloat, outer: CGFloat) {
        let dy = CGFloat(y) + 0.5 - cy
        let dy2 = dy * dy
        guard dy2 < outer else { return }
        var solidStart = x1 + 1, solidEnd = x1
        if dy2 < inner {
            // Pixel centres within `half` of the centre are fully inside.
            let half = (inner - dy2).squareRoot()
            solidStart = Swift.max(x0, Int((cx - half - 0.5).rounded(.up)))
            solidEnd   = Swift.min(x1, Int((cx + half - 0.5).rounded(.down)))
            if solidStart <= solidEnd {
                memset(row + solidStart, 255, solidEnd - solidStart + 1)
            } else {
                solidStart = x1 + 1
                solidEnd = x1
            }
        }
        let edge = radius + 0.5
        var x = x0
        while x <= x1 {
            if x == solidStart { x = solidEnd + 1; continue }
            let dx = CGFloat(x) + 0.5 - cx
            let d2 = dx * dx + dy2
            if d2 < outer {
                let value = UInt8(Swift.min(edge - d2.squareRoot(), 1) * 255)
                if value > row[x] { row[x] = value }
            }
            x += 1
        }
    }

    /// Softness grows with the cell on screen, like the original gradient edge, and is
    /// capped so very close zooms stay cheap. Tiny zoomed-out cells are left sharp.
    static func blurKernel(cellPixels: CGFloat) -> Int {
        let k = min(Int(cellPixels * 0.3), 15)
        return k < 3 ? 0 : k | 1
    }

    private func blur(_ ctx: CGContext, kernel: Int) {
        guard kernel > 0, let data = ctx.data else { return }
        let rowBytes = ctx.bytesPerRow
        let scratch = UnsafeMutableRawPointer.allocate(byteCount: rowBytes * height, alignment: 16)
        defer { scratch.deallocate() }
        var image = vImage_Buffer(data: data, height: vImagePixelCount(height),
                                  width: vImagePixelCount(width), rowBytes: rowBytes)
        var temp  = vImage_Buffer(data: scratch, height: vImagePixelCount(height),
                                  width: vImagePixelCount(width), rowBytes: rowBytes)
        let k = UInt32(kernel)
        // Four box passes approximate a Gaussian.
        for _ in 0..<2 {
            vImageBoxConvolve_Planar8(&image, &temp, nil, 0, 0, k, k, 0, vImage_Flags(kvImageEdgeExtend))
            vImageBoxConvolve_Planar8(&temp, &image, nil, 0, 0, k, k, 0, vImage_Flags(kvImageEdgeExtend))
        }
    }
}
