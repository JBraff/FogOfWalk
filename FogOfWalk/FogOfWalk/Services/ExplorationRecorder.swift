import CoreLocation

/// Shared recording path for map-driven legacy delivery and the app-owned Study
/// source. Study can record during a background launch before any map exists.
@MainActor
struct ExplorationRecorder {
    let store: ExplorationStore
    let landmarks: LandmarkStore
    var diagnostics: LocationDiagnosticRecording = LocationStudyDiagnostics.shared

    /// Whether the visible fog needs refreshing.
    @discardableResult
    func record(_ location: CLLocation) -> Bool {
        store.configure()
        let dayRollover = store.refreshForDayChangeIfNeeded()
        let cell = GridMath.cellID(for: location.coordinate)
        let isNew = store.addCell(cell)
        // Only real delivered samples become cells; no interpolation or haptics.
        let discoveries = isNew ? landmarks.checkDiscovery(newCell: cell).count : 0
        diagnostics.recordDownstream(cell: cell, isNew: isNew,
                                     discoveries: discoveries, dayRollover: dayRollover)
        return isNew || dayRollover
    }
}
