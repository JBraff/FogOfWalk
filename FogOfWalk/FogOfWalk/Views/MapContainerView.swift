import SwiftUI
import MapKit

struct MapContainerView: UIViewRepresentable {
    @Environment(ExplorationStore.self)       private var store
    @Environment(GridSettings.self)           private var gridSettings
    @Environment(LocationService.self)        private var locationService
    @Environment(LandmarkStore.self)          private var landmarkStore
    @Environment(LandmarkSearchService.self)  private var searchService

    var onLandmarkTapped: ((String) -> Void)?
    var navigateTo: MapNavigationTarget?
    /// Mirrors `store.recentCellsGeneration` so SwiftUI diffs this representable's value
    /// on a day-rollover highlight rebuild even when no other input changed, forcing
    /// `updateUIView` to run and pick up the new snapshot.
    var highlightGeneration: UInt64 = 0
    /// Mirrors `store.visitedCellsCache.count` for the same reason: recording happens outside
    /// the map (see `ExplorationRecorder`), and this input guarantees `updateUIView` runs and
    /// pushes a fresh fog snapshot when a cell is added.
    var visitedCellCount: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store, gridSettings: gridSettings,
                    landmarkStore: landmarkStore, searchService: searchService)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()

        // Map fills the container.
        let mapView               = MKMapView(frame: container.bounds)
        mapView.delegate          = context.coordinator
        mapView.showsCompass      = false   // Replaced by the compass button below the tracking button.
        mapView.autoresizingMask  = [.flexibleWidth, .flexibleHeight]
        container.addSubview(mapView)

        // Native recenter/follow/heading-up control, top right like Apple Maps. The compass
        // sits under it and appears only while the map is rotated.
        let trackingButton = Self.makeTrackingButton(for: mapView)
        let compassButton  = MKCompassButton(mapView: mapView)
        compassButton.compassVisibility = .adaptive
        compassButton.translatesAutoresizingMaskIntoConstraints = false

        Self.applyLocationDisplay(to: mapView, trackingButton: trackingButton,
                                  enabled: locationService.usesMapLocation)
        locationService.installStudyMapControl { [weak mapView, weak trackingButton] enabled in
            guard let mapView else { return }
            Self.applyLocationDisplay(to: mapView, trackingButton: trackingButton, enabled: enabled)
        }

        // Fog is rendered by MapKit as an MKOverlay — no UIView sibling needed.
        // MapKit handles all pan/zoom compositing natively.
        let fogOverlay = FogOverlay()
        mapView.addOverlay(fogOverlay, level: .aboveLabels)
        context.coordinator.fogOverlay = fogOverlay

        // Landmark overlay sits as a UIView sibling above the map so pins are
        // always visible through the fog and support tap hit-testing.
        let landmarkView              = LandmarkOverlayView(frame: container.bounds)
        landmarkView.mapView          = mapView
        landmarkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        landmarkView.onPinTapped      = onLandmarkTapped
        container.addSubview(landmarkView)
        context.coordinator.landmarkOverlayView = landmarkView

        // Controls go above the pin overlay so its hit-testing never swallows their taps.
        container.addSubview(trackingButton)
        container.addSubview(compassButton)
        let guide = container.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            trackingButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            trackingButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -12),
            trackingButton.widthAnchor.constraint(equalToConstant: 44),
            trackingButton.heightAnchor.constraint(equalToConstant: 44),
            compassButton.topAnchor.constraint(equalTo: trackingButton.bottomAnchor, constant: 8),
            compassButton.centerXAnchor.constraint(equalTo: trackingButton.centerXAnchor),
        ])

        return container
    }

    static func makeTrackingButton(for mapView: MKMapView) -> MKUserTrackingButton {
        let button = MKUserTrackingButton(mapView: mapView)
        button.backgroundColor    = .systemBackground.withAlphaComponent(0.9)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    /// Shows or hides the blue dot and its tracking button together. Study's automatic
    /// pause/resume and tracking-OFF modes turn MapKit's user location off, so the button
    /// would have nothing to follow.
    static func applyLocationDisplay(to mapView: MKMapView, trackingButton: UIView?, enabled: Bool) {
        if enabled {
            let wasDisabled = !mapView.showsUserLocation
            mapView.showsUserLocation = true
            if wasDisabled { mapView.userTrackingMode = .follow }
        } else {
            mapView.userTrackingMode = .none
            mapView.showsUserLocation = false
        }
        trackingButton?.isHidden = !enabled
    }

    /// Moves the map to a stats-sheet target and leaves follow mode, so the map stays where
    /// it was sent instead of snapping back to the user. Tapping the tracking button resumes.
    static func navigate(_ mapView: MKMapView, to target: MapNavigationTarget) {
        mapView.setUserTrackingMode(.none, animated: false)
        mapView.setRegion(MKCoordinateRegion(center: target.center, span: target.span),
                          animated: true)
    }

    func updateUIView(_ container: UIView, context: Context) {
        guard let mapView = container.subviews.first as? MKMapView else { return }
        context.coordinator.store         = store
        context.coordinator.gridSettings  = gridSettings
        context.coordinator.landmarkStore = landmarkStore
        context.coordinator.searchService = searchService

        if let landmarkView = container.subviews.first(where: { $0 is LandmarkOverlayView })
                                as? LandmarkOverlayView {
            landmarkView.onPinTapped = onLandmarkTapped
        }

        // Recording is wired once in FogOfWalkApp.init; the map only reflects the store.
        // `visitedCellCount`/`highlightGeneration` inputs make SwiftUI re-run this method
        // when a new cell or highlight rebuild lands.
        let coordinator = context.coordinator

        // Navigate to target if it's new
        if let target = navigateTo, target.id != coordinator.lastNavigationTargetID {
            Self.navigate(mapView, to: target)
            coordinator.lastNavigationTargetID = target.id
        }

        // If the cache was populated after the renderer was created (e.g.
        // initial Core Data load completing after makeUIView), push the
        // updated cells to the fog renderer.
        let currentCount = store.visitedCellsCache.count
        let currentRecentGen = store.recentCellsGeneration
        if currentCount != coordinator.lastSnapshotCellCount
            || currentRecentGen != coordinator.lastRecentCellGeneration {
            coordinator.invalidateFogTiles()
        }
        // A new cell re-runs this method; rebuild pins only when landmark state changed.
        // Region changes refresh pins through `regionDidChangeAnimated`.
        if coordinator.refreshLandmarksIfChanged(in: mapView.region, mapView: mapView) {
            coordinator.landmarkOverlayView?.setNeedsDisplay()
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var store:        ExplorationStore
        var gridSettings: GridSettings
        var landmarkStore: LandmarkStore
        var searchService: LandmarkSearchService

        // Fog is now an MKOverlay; MapKit holds the strong references.
        weak var fogOverlay:          FogOverlay?
        weak var fogRenderer:         FogOverlayRenderer?
        weak var landmarkOverlayView: LandmarkOverlayView?

        /// Where the overlay's center and probe point were on the map at the last full
        /// landmark render. Tracking both through a gesture gives its pan, zoom and rotation.
        private var referenceCenter: CLLocationCoordinate2D?
        private var referenceProbe:  CLLocationCoordinate2D?

        /// Screen offset of the probe point from the overlay's center at the reference render.
        static let probeOffset = CGVector(dx: 100, dy: 0)

        /// Tracks the cell count at the last fog snapshot push so `updateUIView`
        /// can detect when the cache was populated after the renderer was created.
        var lastSnapshotCellCount: Int = -1

        /// Tracks the recent-cell generation so `updateUIView` can detect highlight changes
        /// even when the cell count is unchanged (e.g., toggling on/off with 0 cells today).
        var lastRecentCellGeneration: UInt64 = 0

        /// Tracks the last navigation target ID applied so `updateUIView` only animates once per tap.
        var lastNavigationTargetID: UUID?

        /// The landmark inputs pins were last built from. Pins depend only on these and the
        /// region, so `updateUIView` can skip the rebuild when neither changed.
        struct LandmarkRenderState: Equatable {
            let showLandmarks: Bool
            let landmarkCount: Int
            let discoveredCount: Int
        }
        private(set) var lastLandmarkRenderState: LandmarkRenderState?

        private var currentLandmarkRenderState: LandmarkRenderState {
            LandmarkRenderState(showLandmarks: gridSettings.showLandmarks,
                                landmarkCount: landmarkStore.allLandmarks.count,
                                discoveredCount: landmarkStore.totalDiscovered)
        }

        init(store: ExplorationStore, gridSettings: GridSettings,
             landmarkStore: LandmarkStore, searchService: LandmarkSearchService) {
            self.store         = store
            self.gridSettings  = gridSettings
            self.landmarkStore = landmarkStore
            self.searchService = searchService
        }

        // MARK: - Fog tile management

        /// Creates a fresh CellSnapshot from the current cache and marks visible
        /// fog tiles as needing redisplay. Safe to call from the main thread at any time;
        /// no-ops gracefully if the renderer hasn't been created yet.
        func invalidateFogTiles() {
            let snap = CellSnapshot(cells: store.visitedCellsCache,
                                    recentCells: store.recentCellsCache)
            fogRenderer?.snapshot = snap
            fogRenderer?.setNeedsDisplay()
            lastSnapshotCellCount    = store.visitedCellsCache.count
            lastRecentCellGeneration = store.recentCellsGeneration
        }

        /// Removes the current FogOverlay and adds a new one with a fresh snapshot.
        func replaceFogOverlay(mapView: MKMapView) {
            if let old = fogOverlay {
                mapView.removeOverlay(old)
            }
            fogRenderer = nil
            let new = FogOverlay()
            fogOverlay = new
            mapView.addOverlay(new, level: .aboveLabels)
            // lastRenderedCellSize is updated in mapView(_:rendererFor:) when MapKit
            // calls back to create the renderer for the newly added overlay.
        }

        // MARK: - Landmark refresh

        /// Rebuilds pins only if landmark state changed since the last refresh. Returns
        /// whether it did.
        @discardableResult
        func refreshLandmarksIfChanged(in region: MKCoordinateRegion, mapView: MKMapView) -> Bool {
            guard currentLandmarkRenderState != lastLandmarkRenderState else { return false }
            refreshLandmarks(in: region, mapView: mapView)
            return true
        }

        func refreshLandmarks(in region: MKCoordinateRegion, mapView: MKMapView) {
            lastLandmarkRenderState = currentLandmarkRenderState
            // Clear rather than early-return so stale pins from before the toggle was
            // flipped off (or from the previous region) stop drawing; both this guard and
            // the wide-zoom one below rely on that to keep the overlay in sync.
            guard gridSettings.showLandmarks else {
                landmarkOverlayView?.update(pins: [])
                return
            }

            // Above the ingest span the map is an orientation view, where pins carry no
            // useful detail. Clear rather than early-return so stale pins from the previous
            // region stop drawing; `regionDidChangeAnimated` repopulates on the way back in.
            let widestSpan = max(region.span.latitudeDelta, region.span.longitudeDelta)
            guard widestSpan <= GridMath.maxIngestSpanDegrees else {
                landmarkOverlayView?.update(pins: [])
                return
            }

            let nearby = landmarkStore.landmarks(in: region)
            let pins = nearby.map { landmark in
                LandmarkPin(
                    identifier:  landmark.identifier,
                    name:        landmark.name,
                    category:    landmark.category,
                    coordinate:  CLLocationCoordinate2D(latitude:  landmark.latitude,
                                                        longitude: landmark.longitude),
                    isDiscovered: landmark.isDiscovered
                )
            }
            landmarkOverlayView?.update(pins: pins)
        }

        // MARK: - Gesture transform (LandmarkOverlayView only)

        /// Computes a CATransform3D for the landmark overlay during pan, zoom and rotation.
        /// Fog tracking is handled natively by MapKit; only LandmarkOverlayView needs this.
        ///
        /// At the reference render the overlay's center coordinate was drawn at `viewCenter`
        /// and the probe coordinate at `viewCenter + probeOffset`. `referenceCenterScreen` and
        /// `referenceProbeScreen` are where those coordinates are on screen now. The transform
        /// (about the layer's center, its anchor point) maps both old positions onto the new
        /// ones: the vector between them gives the scale and rotation, the center's move gives
        /// the translation. Span ratios can't be used, because a rotated map's region is the
        /// bounding box of the rotated view.
        ///
        /// This is a static func so the math can be unit-tested without a live MKMapView.
        static func gestureTransform(
            referenceCenterScreen: CGPoint,
            referenceProbeScreen: CGPoint,
            viewCenter: CGPoint,
            probeOffset: CGVector
        ) -> CATransform3D {
            let referenceLength = hypot(probeOffset.dx, probeOffset.dy)
            guard referenceLength > 0 else { return CATransform3DIdentity }
            let dx = referenceProbeScreen.x - referenceCenterScreen.x
            let dy = referenceProbeScreen.y - referenceCenterScreen.y
            let scale = hypot(dx, dy) / referenceLength
            let angle = atan2(dy, dx) - atan2(probeOffset.dy, probeOffset.dx)

            var t = CATransform3DIdentity
            t = CATransform3DTranslate(t, referenceCenterScreen.x - viewCenter.x,
                                          referenceCenterScreen.y - viewCenter.y, 0)
            t = CATransform3DScale(t, scale, scale, 1)
            t = CATransform3DRotate(t, angle, 0, 0, 1)
            return t
        }

        /// Records the coordinates under the overlay's center and probe point, the baseline
        /// for the next gesture's transform.
        private func setReference(mapView: MKMapView, overlay: UIView) {
            let center = CGPoint(x: overlay.bounds.midX, y: overlay.bounds.midY)
            let probe  = CGPoint(x: center.x + Self.probeOffset.dx, y: center.y + Self.probeOffset.dy)
            referenceCenter = mapView.convert(center, toCoordinateFrom: overlay)
            referenceProbe  = mapView.convert(probe,  toCoordinateFrom: overlay)
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let fogOverlay = overlay as? FogOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let snap = CellSnapshot(cells: store.visitedCellsCache,
                                    recentCells: store.recentCellsCache)
            let renderer = FogOverlayRenderer(overlay: fogOverlay, snapshot: snap)
            fogRenderer              = renderer
            lastSnapshotCellCount    = store.visitedCellsCache.count
            lastRecentCellGeneration = store.recentCellsGeneration
            return renderer
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = mapView.region

            // Refresh the landmark overlay with a clean render for the new region.
            refreshLandmarks(in: region, mapView: mapView)
            landmarkOverlayView?.setNeedsDisplay()
            landmarkOverlayView?.layer.displayIfNeeded()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            landmarkOverlayView?.layer.transform = CATransform3DIdentity
            CATransaction.commit()
            if let landmarkOverlayView { setReference(mapView: mapView, overlay: landmarkOverlayView) }

            searchService.searchIfNeeded(region: region,
                                        landmarkStore: landmarkStore,
                                        visitedCells: store.visitedCellsCache)
        }

        /// Fires continuously during pan, zoom and rotation, including heading-up tracking.
        /// Applies a GPU-composited CATransform3D to LandmarkOverlayView so pins track the
        /// map until `regionDidChangeAnimated` redraws them.
        /// The fog overlay tracks natively — no manual transform is needed for it.
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            guard let landmarkOverlayView else { return }
            guard let referenceCenter, let referenceProbe else {
                // No reference yet — establish one so the first gesture has a baseline.
                setReference(mapView: mapView, overlay: landmarkOverlayView)
                return
            }

            let t = Coordinator.gestureTransform(
                referenceCenterScreen: mapView.convert(referenceCenter, toPointTo: landmarkOverlayView),
                referenceProbeScreen:  mapView.convert(referenceProbe,  toPointTo: landmarkOverlayView),
                viewCenter: CGPoint(x: landmarkOverlayView.bounds.midX,
                                    y: landmarkOverlayView.bounds.midY),
                probeOffset: Self.probeOffset
            )

            landmarkOverlayView.layer.transform = t
        }
    }
}
