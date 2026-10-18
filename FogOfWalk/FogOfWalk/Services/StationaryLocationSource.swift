import CoreLocation

/// The persisted experiment is meaningful only in the isolated Study identity.
enum StudyLocationSource: String, CaseIterable {
    case legacy
    case liveUpdates

    static let defaultsKey = "locationStudy.source"

    static func selected(in defaults: UserDefaults) -> Self {
        Self(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .legacy
    }
}

enum StationaryLocationEvent {
    case update(location: CLLocation?, stationary: Bool, diagnostic: String)
    case ended(String)
}

@MainActor
protocol StationaryLocationSource: AnyObject {
    func start(_ receive: @escaping @MainActor (StationaryLocationEvent) -> Void)
    func stop()
}

/// Retained by LocationService, never by the map. Keep the sequence open during
/// stationary suspension: breaking its loop would disable automatic resume.
@MainActor
final class LiveStationaryLocationSource: StationaryLocationSource {
    private var task: Task<Void, Never>?
    private var backgroundSession: CLBackgroundActivitySession?
    private var serviceSession: CLServiceSession?

    func start(_ receive: @escaping @MainActor (StationaryLocationEvent) -> Void) {
        guard task == nil else { return }
        serviceSession = CLServiceSession(authorization: .always)
        backgroundSession = CLBackgroundActivitySession()
        task = Task { @MainActor in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard !Task.isCancelled else { return }
                    let flags = "denied=\(update.authorizationDenied) globalDenied=\(update.authorizationDeniedGlobally) restricted=\(update.authorizationRestricted) insufficientlyInUse=\(update.insufficientlyInUse) unavailable=\(update.locationUnavailable) accuracyLimited=\(update.accuracyLimited) serviceRequired=\(update.serviceSessionRequired) requesting=\(update.authorizationRequestInProgress)"
                    receive(.update(location: update.location, stationary: update.stationary,
                                    diagnostic: flags))
                }
                if !Task.isCancelled { receive(.ended("sequence_finished")) }
            } catch {
                guard !Task.isCancelled else { return }
                let error = error as NSError
                receive(.ended("\(error.domain):\(error.code)"))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        serviceSession?.invalidate()
        serviceSession = nil
    }

    deinit {
        task?.cancel()
        backgroundSession?.invalidate()
        serviceSession?.invalidate()
    }
}
