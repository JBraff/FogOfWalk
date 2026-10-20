import CoreLocation

/// The single recording path: location sample → cell → landmark discovery. It is wired
/// in `FogOfWalkApp.init` for both app identities, so recording never depends on the
/// map view existing (iOS can relaunch the app in the background with no scene).
@MainActor
struct ExplorationRecorder {
    let store: ExplorationStore
    let landmarks: LandmarkStore
    /// Bundled landmark data ingested around each new cell. Nil disables walk-time ingest.
    var landmarkSource: (any LandmarkDataProviding)? = nil
    var diagnostics: LocationDiagnosticRecording = LocationStudyDiagnostics.shared

    /// Connects everything that must happen per recorded location or new cell. Call once,
    /// at app launch, before any view exists.
    static func connect(location: LocationService,
                        store: ExplorationStore,
                        landmarks: LandmarkStore,
                        geocoder: LocalityGeocoder,
                        landmarkSource: (any LandmarkDataProviding)?) {
        let recorder = ExplorationRecorder(store: store, landmarks: landmarks,
                                           landmarkSource: landmarkSource)
        location.onLocationUpdate = { recorder.record($0) }
        store.onNewCell = { [geocoder] cell in geocoder.enqueue(cell) }
    }

    /// Whether the visible fog needs refreshing.
    @discardableResult
    func record(_ location: CLLocation) -> Bool {
        store.configure()
        let dayRollover = store.refreshForDayChangeIfNeeded()
        let cell = GridMath.cellID(for: location.coordinate)
        let isNew = store.addCell(cell)
        // Only real delivered samples become cells; no interpolation or haptics.
        var discoveries = 0
        if isNew {
            if let landmarkSource {
                discoveries += landmarks.ingestLandmarks(near: cell, from: landmarkSource,
                                                         visitedCells: store.visitedCellsCache).count
            }
            discoveries += landmarks.checkDiscovery(newCell: cell).count
        }
        diagnostics.recordDownstream(cell: cell, isNew: isNew,
                                     discoveries: discoveries, dayRollover: dayRollover)
        return isNew || dayRollover
    }
}
