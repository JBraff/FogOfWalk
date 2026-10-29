import SwiftUI
import MapKit

struct MapContainerView: UIViewRepresentable {
    @Environment(\.scenePhase) private var scenePhase
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
    /// Explicit inputs ensure ingest and discovery refresh annotations even without a new cell.
    var landmarkGeneration: UInt64 = 0
    var showsLandmarks: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store, gridSettings: gridSettings,
                    landmarkStore: landmarkStore, searchService: searchService)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()

        // Map fills the container.
        let mapView               = HeadingMapView(frame: container.bounds)
        mapView.sceneActive       = scenePhase == .active
        mapView.delegate          = context.coordinator
        mapView.showsCompass      = false   // Replaced by the compass button below the tracking button.
        mapView.autoresizingMask  = [.flexibleWidth, .flexibleHeight]
        container.addSubview(mapView)

        // Recenter without entering heading-up tracking. The compass appears only
        // after the user manually rotates the map.
        let trackingButton = Self.makeTrackingButton(for: mapView)
        context.coordinator.trackingButton = trackingButton
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

        // Native annotations stay above the fog and move with MapKit at a fixed size.
        context.coordinator.onLandmarkTapped = onLandmarkTapped

        // Controls remain above the map and its annotations.
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

    static func makeTrackingButton(for mapView: MKMapView) -> UIButton {
        let button = UIButton(type: .system)
        updateTrackingButton(button, mode: mapView.userTrackingMode)
        button.accessibilityLabel = "Recenter on my location"
        button.addAction(UIAction { [weak mapView] _ in
            guard let mapView, mapView.showsUserLocation else { return }
            mapView.setUserTrackingMode(.follow, animated: true)
        }, for: .touchUpInside)
        button.backgroundColor    = .systemBackground.withAlphaComponent(0.9)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    static func updateTrackingButton(_ button: UIButton, mode: MKUserTrackingMode) {
        let follows = mode != .none
        button.setImage(UIImage(systemName: follows ? "location.fill" : "location"), for: .normal)
        button.accessibilityValue = follows ? "Following location" : "Not following location"
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
        (mapView as? HeadingMapView)?.locationDisplayEnabled = enabled
        trackingButton?.isHidden = !enabled
        if let button = trackingButton as? UIButton {
            updateTrackingButton(button, mode: mapView.userTrackingMode)
        }
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
        (mapView as? HeadingMapView)?.sceneActive = scenePhase == .active
        context.coordinator.store         = store
        context.coordinator.gridSettings  = gridSettings
        context.coordinator.landmarkStore = landmarkStore
        context.coordinator.searchService = searchService

        context.coordinator.onLandmarkTapped = onLandmarkTapped

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
        coordinator.refreshLandmarksIfChanged(in: mapView.region, mapView: mapView)
    }

    static func dismantleUIView(_ container: UIView, coordinator: Coordinator) {
        (container.subviews.first as? HeadingMapView)?.locationDisplayEnabled = false
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var store:        ExplorationStore
        var gridSettings: GridSettings
        var landmarkStore: LandmarkStore
        var searchService: LandmarkSearchService

        weak var trackingButton: UIButton?

        // Fog is now an MKOverlay; MapKit holds the strong references.
        weak var fogOverlay:          FogOverlay?
        weak var fogRenderer:         FogOverlayRenderer?
        var onLandmarkTapped: ((String) -> Void)?
        private(set) var landmarkAnnotations: [String: LandmarkAnnotation] = [:]

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
            let generation: UInt64
        }
        private(set) var lastLandmarkRenderState: LandmarkRenderState?

        private var currentLandmarkRenderState: LandmarkRenderState {
            LandmarkRenderState(showLandmarks: gridSettings.showLandmarks,
                                generation: landmarkStore.renderGeneration)
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
            let widestSpan = max(region.span.latitudeDelta, region.span.longitudeDelta)
            let landmarks = gridSettings.showLandmarks && widestSpan <= GridMath.maxIngestSpanDegrees
                ? landmarkStore.landmarksForDisplay(in: region) : []
            let wantedIDs = Set(landmarks.map { $0.identifier })
            let removed = landmarkAnnotations.values.filter { !wantedIDs.contains($0.identifier) }
            mapView.removeAnnotations(removed)
            for annotation in removed { landmarkAnnotations.removeValue(forKey: annotation.identifier) }

            var added: [LandmarkAnnotation] = []
            for landmark in landmarks {
                let pin = LandmarkPin(landmark: landmark)
                if let annotation = landmarkAnnotations[pin.identifier] {
                    if annotation.update(pin: pin) {
                        // In-place discovery updates include visible views. Reused/offscreen
                        // views are configured from the latest annotation in viewFor.
                        (mapView.view(for: annotation) as? LandmarkAnnotationView)?.configure(traits: mapView.traitCollection)
                    }
                } else {
                    let annotation = LandmarkAnnotation(pin: pin)
                    landmarkAnnotations[pin.identifier] = annotation
                    added.append(annotation)
                }
            }
            mapView.addAnnotations(added)
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            if let trackingButton { MapContainerView.updateTrackingButton(trackingButton, mode: mode) }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                let identifier = "heading-user-location"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                            as? HeadingUserLocationView)
                    ?? HeadingUserLocationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                view.zPriority = .max
                view.selectedZPriority = .max
                view.setHeading((mapView as? HeadingMapView)?.headingController.heading,
                                mapHeading: mapView.camera.heading)
                return view
            }
            guard annotation is LandmarkAnnotation else { return nil }
            let identifier = LandmarkAnnotationView.reuseID
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                        as? LandmarkAnnotationView)
                ?? LandmarkAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.configure(traits: mapView.traitCollection)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? LandmarkAnnotation else { return }
            mapView.deselectAnnotation(annotation, animated: false)
            guard annotation.pin.isDiscovered else { return }
            onLandmarkTapped?(annotation.identifier)
        }

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

            refreshLandmarks(in: region, mapView: mapView)

            searchService.searchIfNeeded(region: region,
                                        landmarkStore: landmarkStore,
                                        visitedCells: store.visitedCellsCache)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            (mapView as? HeadingMapView)?.updateHeadingMarker()
        }
    }
}

/// Isolate landmark dependencies to the map while retaining explicit representable inputs
/// on every supported iOS version. Count-neutral changes also invalidate this child.
struct LandmarkMapView: View {
    @Environment(LandmarkStore.self) private var landmarks
    @Environment(GridSettings.self) private var settings
    var onLandmarkTapped: ((String) -> Void)?
    var navigateTo: MapNavigationTarget?
    var highlightGeneration: UInt64
    var visitedCellCount: Int

    var body: some View {
        MapContainerView(onLandmarkTapped: onLandmarkTapped, navigateTo: navigateTo,
            highlightGeneration: highlightGeneration, visitedCellCount: visitedCellCount,
            landmarkGeneration: landmarks.renderGeneration, showsLandmarks: settings.showLandmarks)
    }
}
