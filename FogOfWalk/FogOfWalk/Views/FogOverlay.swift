import MapKit
import UIKit
import CoreLocation

// MARK: - FogOverlay

/// A world-spanning MKOverlay that registers fog rendering with MapKit.
/// The actual drawing is performed by FogOverlayRenderer.
final class FogOverlay: NSObject, MKOverlay {
    var coordinate:       CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: 0, longitude: 0) }
    var boundingMapRect:  MKMapRect              { .world }
}

// MARK: - FogRenderer

/// Pure Core Graphics fog rendering — no MapKit dependency.
/// Fills a rect with semi-transparent grey fog, then punches soft-edged transparent
/// holes over explored cells using radial gradients in `.destinationOut` blend mode.
///
/// Separated from MKOverlayRenderer so unit tests can exercise the rendering logic
/// without needing a live MapKit context.
struct FogRenderer {

    private let fogColor:          CGColor
    private let holeGradient:      CGGradient
    private let highlightGradient: CGGradient

    init() {
        // Resolve at init time (always called on the main thread before use).
        fogColor = UIColor.systemGray.withAlphaComponent(0.92).cgColor

        let cs         = CGColorSpaceCreateDeviceRGB()
        let gradColors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        let gradLocs: [CGFloat] = [0.0, 0.7, 1.0]
        // Constants are compile-time; force-unwrap is safe.
        holeGradient = CGGradient(
            colorsSpace: cs, colors: gradColors as CFArray, locations: gradLocs)!

        // Warm golden tint for recently explored cells.
        let gold      = UIColor(red: 1.0, green: 0.78, blue: 0.2, alpha: 0.22).cgColor
        let goldClear = UIColor(red: 1.0, green: 0.78, blue: 0.2, alpha: 0.0).cgColor
        let highlightColors = [gold, gold, goldClear]
        let highlightLocs: [CGFloat] = [0.0, 0.65, 1.0]
        highlightGradient = CGGradient(
            colorsSpace: cs, colors: highlightColors as CFArray, locations: highlightLocs)!
    }

    /// Renders fog into `context` within `drawRect`, punching transparent holes
    /// at the screen positions returned by `coordinateConverter` for each cell,
    /// and overlaying a warm golden tint on `recentCells`.
    func render(
        cells: [CellID],
        recentCells: [CellID] = [],
        drawRect: CGRect,
        coordinateConverter: (CLLocationCoordinate2D) -> CGPoint,
        in context: CGContext
    ) {
        // 1. Flood-fill with fog.
        context.setFillColor(fogColor)
        context.fill(drawRect)

        guard !cells.isEmpty else { return }

        // 2. Punch holes for each visited cell.
        context.setBlendMode(.destinationOut)
        for cell in cells {
            drawHole(for: cell, drawRect: drawRect, coordinateConverter: coordinateConverter,
                     in: context)
        }
        context.setBlendMode(.normal)

        // 3. Overlay golden tint on recently visited cells.
        guard !recentCells.isEmpty else { return }
        for cell in recentCells {
            drawHighlight(for: cell, drawRect: drawRect, coordinateConverter: coordinateConverter,
                          in: context)
        }
    }

    private func cellGeometry(
        for cell: CellID,
        coordinateConverter: (CLLocationCoordinate2D) -> CGPoint
    ) -> (center: CGPoint, radius: CGFloat) {
        let b = GridMath.bounds(for: cell)
        let minPt = coordinateConverter(CLLocationCoordinate2D(latitude: b.min.latitude,
                                                                longitude: b.min.longitude))
        let maxPt = coordinateConverter(CLLocationCoordinate2D(latitude: b.max.latitude,
                                                                longitude: b.max.longitude))
        let center = CGPoint(x: (minPt.x + maxPt.x) / 2,
                             y: (minPt.y + maxPt.y) / 2)
        // 10% overlap so adjacent explored cells merge without visible seams.
        let radius = max(abs(maxPt.x - minPt.x), abs(maxPt.y - minPt.y)) * 0.9
        return (center, radius)
    }

    private func drawHole(
        for cell: CellID,
        drawRect: CGRect,
        coordinateConverter: (CLLocationCoordinate2D) -> CGPoint,
        in context: CGContext
    ) {
        let (center, radius) = cellGeometry(for: cell, coordinateConverter: coordinateConverter)
        guard radius > 0.5 else { return }  // skip sub-pixel cells
        let gradientRect = CGRect(x: center.x - radius, y: center.y - radius,
                                  width: radius * 2,    height: radius * 2)
        guard gradientRect.intersects(drawRect) else { return }

        // Both gradient stops end at alpha 0, so `.drawsAfterEndLocation` — which fills the
        // entire clip region with the end color beyond `endRadius` — was a full-clip no-op
        // that cost a rasterization pass per visited cell. `options: []` is pixel-identical.
        context.drawRadialGradient(
            holeGradient,
            startCenter: center, startRadius: 0,
            endCenter:   center, endRadius:   radius,
            options:     []
        )
    }

    private func drawHighlight(
        for cell: CellID,
        drawRect: CGRect,
        coordinateConverter: (CLLocationCoordinate2D) -> CGPoint,
        in context: CGContext
    ) {
        let (center, radius) = cellGeometry(for: cell, coordinateConverter: coordinateConverter)
        guard radius > 0.5 else { return }
        let gradientRect = CGRect(x: center.x - radius, y: center.y - radius,
                                  width: radius * 2,    height: radius * 2)
        guard gradientRect.intersects(drawRect) else { return }

        // Same reasoning as drawHole: the gold gradient also ends at alpha 0.
        context.drawRadialGradient(
            highlightGradient,
            startCenter: center, startRadius: 0,
            endCenter:   center, endRadius:   radius,
            options:     []
        )
    }
}

// MARK: - FogOverlayRenderer

/// Bridges FogRenderer into MapKit's overlay rendering pipeline.
/// MapKit calls `draw(_:zoomScale:in:)` on background threads; all state shared
/// with the main thread is protected by `NSLock` via the `snapshot` property.
final class FogOverlayRenderer: MKOverlayRenderer {

    // MARK: Thread-safe snapshot

    private let lock = NSLock()
    private var _snapshot: CellSnapshot

    /// Replace atomically from the main thread whenever the visited-cell set changes.
    var snapshot: CellSnapshot {
        get { lock.withLock { _snapshot } }
        set { lock.withLock { _snapshot = newValue } }
    }

    private let fogRenderer = FogRenderer()

    // MARK: Init

    init(overlay: MKOverlay, snapshot: CellSnapshot) {
        self._snapshot = snapshot
        super.init(overlay: overlay)
    }

    // MARK: Drawing

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let snap     = snapshot
        let drawRect = rect(for: mapRect)   // CGRect in renderer space — set up by MapKit

        let region  = MKCoordinateRegion(mapRect)
        let margin  = kCellSizeMeters / GridMath.metersPerDegree
        let halfLat = region.span.latitudeDelta  / 2.0
        let halfLon = region.span.longitudeDelta / 2.0
        let latRange = (region.center.latitude  - halfLat - margin)...(region.center.latitude  + halfLat + margin)
        let lonRange = (region.center.longitude - halfLon - margin)...(region.center.longitude + halfLon + margin)
        let cells   = snap.visitedCells(inLatRange: latRange, lonRange: lonRange)
        let recent  = snap.recentCells(inLatRange: latRange, lonRange: lonRange)

        fogRenderer.render(
            cells: cells,
            recentCells: recent,
            drawRect: drawRect,
            coordinateConverter: { [weak self] coord in
                self?.point(for: MKMapPoint(coord)) ?? .zero
            },
            in: context
        )
    }
}
