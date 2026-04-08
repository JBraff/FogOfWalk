import Foundation
import Observation

@MainActor
@Observable
final class GridSettings {
    var highlightToday: Bool {
        didSet {
            UserDefaults.standard.set(highlightToday, forKey: Keys.highlightToday)
        }
    }

    private enum Keys {
        static let highlightToday = "com.fogofwalk.highlightToday"
    }

    /// The cutoff date for highlighting — start of today when active, nil when off.
    var highlightCutoffDate: Date? {
        highlightToday ? Calendar.current.startOfDay(for: Date()) : nil
    }

    init() {
        highlightToday = UserDefaults.standard.bool(forKey: Keys.highlightToday)
    }
}
