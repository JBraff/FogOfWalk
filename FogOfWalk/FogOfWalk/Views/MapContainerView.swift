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

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store, gridSettings: gridSettings,
                    landmarkStore: landmarkStore, searchService: searchService)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()

        // Map fills the container.
        let mapView               = MKMapView(frame: container.bounds)
        mapView.delegate          = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode  = .follow
        mapView.autoresizingMask  = [.flexibleWidth, .flexibleHeight]
        container.addSubview(mapView)

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

        return container
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

        // Always rewire so location updates are never dropped after a SwiftUI rebuild.
        let coordinator = context.coordinator
        locationService.onLocationUpdate = { [weak coordinator] location in
            coordinator?.handle(location: location)
        }

        // Navigate to target if it's new
        if let target = navigateTo, target.id != coordinator.lastNavigationTargetID {
            mapView.setRegion(
                MKCoordinateRegion(center: target.center, span: target.span),
                animated: true
            )
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
        coordinator.refreshLandmarks(in: mapView.region, mapView: mapView)
        coordinator.landmarkOverlayView?.setNeedsDisplay()
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

        /// The map region at the last full landmark render, used to compute
        /// the gesture transform for LandmarkOverlayView during panning.
        private var referenceRegion: MKCoordinateRegion?

        /// Tracks the cell count at the last fog snapshot push so `updateUIView`
        /// can detect when the cache was populated after the renderer was created.
        var lastSnapshotCellCount: Int = -1

        /// Tracks the recent-cell generation so `updateUIView` can detect highlight changes
        /// even when the cell count is unchanged (e.g., toggling on/off with 0 cells today).
        var lastRecentCellGeneration: UInt64 = 0

        /// Tracks the last navigation target ID applied so `updateUIView` only animates once per tap.
        var lastNavigationTargetID: UUID?

        init(store: ExplorationStore, gridSettings: GridSettings,
             landmarkStore: LandmarkStore, searchService: LandmarkSearchService) {
            self.store         = store
            self.gridSettings  = gridSettings
            self.landmarkStore = landmarkStore
            self.searchService = searchService
        }

        // MARK: - Location handling

        func handle(location: CLLocation) {
            store.configure()
            let cell  = GridMath.cellID(for: location.coordinate)
            let isNew = store.addCell(cell)
            if isNew {
                // Push the updated cell set into the renderer; MapKit re-renders
                // only the affected visible tiles asynchronously.
                invalidateFogTiles()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()

                // Only the cell just walked can produce a new discovery, so hand over that one
                // cell rather than the whole visited set. Cost is then independent of how much
                // ground the user has covered.
                let discovered = landmarkStore.checkDiscovery(newCell: cell)
                if !discovered.isEmpty {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
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

        func refreshLandmarks(in region: MKCoordinateRegion, mapView: MKMapView) {
            // Above the ingest span the map is an orientation view — the fog has already
            // vanished at this scale, so pins carry no useful detail either. Clear rather
            // than early-return so stale pins from the previous region stop drawing;
            // `regionDidChangeAnimated` repopulates on the way back in.
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

        /// Computes a CATransform3D for the landmark overlay during pan/zoom gestures.
        /// Fog tracking is handled natively by MapKit; only LandmarkOverlayView needs this.
        ///
        /// This is a static func so the math can be unit-tested without a live MKMapView.
        static func gestureTransform(
            referenceCenterScreen: CGPoint,
            viewCenter: CGPoint,
            referenceSpan: MKCoordinateSpan,
            currentSpan: MKCoordinateSpan
        ) -> CATransform3D {
            let tx = referenceCenterScreen.x - viewCenter.x
            let ty = referenceCenterScreen.y - viewCenter.y
            let sx = CGFloat(referenceSpan.longitudeDelta / max(currentSpan.longitudeDelta, 1e-15))
            let sy = CGFloat(referenceSpan.latitudeDelta  / max(currentSpan.latitudeDelta,  1e-15))

            var t = CATransform3DIdentity
            t = CATransform3DTranslate(t, tx, ty, 0)
            t = CATransform3DScale(t, sx, sy, 1)
            return t
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
            referenceRegion = region

            searchService.searchIfNeeded(region: region,
                                        landmarkStore: landmarkStore,
                                        visitedCells: store.visitedCellsCache)
        }

        /// Fires continuously during pan/zoom. Applies a GPU-composited CATransform3D
        /// to LandmarkOverlayView so pins track the map during gestures.
        /// The fog overlay tracks natively — no manual transform is needed for it.
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            guard let ref = referenceRegion,
                  let landmarkOverlayView else {
                // No reference yet — establish one so the first gesture has a baseline.
                referenceRegion = mapView.region
                return
            }

            let refCenterNow = mapView.convert(ref.center, toPointTo: landmarkOverlayView)
            let viewCenter   = CGPoint(x: landmarkOverlayView.bounds.midX,
                                       y: landmarkOverlayView.bounds.midY)

            let t = Coordinator.gestureTransform(
                referenceCenterScreen: refCenterNow,
                viewCenter: viewCenter,
                referenceSpan: ref.span,
                currentSpan: mapView.region.span
            )

            landmarkOverlayView.layer.transform = t
        }
    }
}
