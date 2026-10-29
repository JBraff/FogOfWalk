import Foundation
import Observation

@MainActor
@Observable
final class GridSettings {
    @ObservationIgnored private let defaults: UserDefaults?

    var highlightToday: Bool {
        didSet {
            defaults?.set(highlightToday, forKey: Keys.highlightToday)
        }
    }

    var showLandmarks: Bool {
        didSet {
            defaults?.set(showLandmarks, forKey: Keys.showLandmarks)
        }
    }

    private enum Keys {
        static let highlightToday = "com.fogofwalk.highlightToday"
        static let showLandmarks  = "com.fogofwalk.showLandmarks"
    }

    /// The cutoff date for highlighting — start of today when active, nil when off.
    var highlightCutoffDate: Date? {
        highlightToday ? Calendar.current.startOfDay(for: Date()) : nil
    }

    /// Passing nil keeps settings in memory, for isolated fixtures.
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        highlightToday = defaults?.bool(forKey: Keys.highlightToday) ?? false
        showLandmarks  = defaults?.bool(forKey: Keys.showLandmarks) ?? false
    }
}
