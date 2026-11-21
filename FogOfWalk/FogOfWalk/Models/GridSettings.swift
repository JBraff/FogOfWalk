import Foundation
import Observation

/// What the gold today overlay shows. Tapping the today count cycles through the cases.
enum TodayHighlight: String {
    case off
    /// Cells first visited today.
    case newToday
    /// Every cell walked today, including cells first visited on an earlier day.
    case walkedToday

    var next: TodayHighlight {
        switch self {
        case .off:         .newToday
        case .newToday:    .walkedToday
        case .walkedToday: .off
        }
    }

    var basis: HighlightBasis {
        self == .walkedToday ? .lastVisited : .firstVisited
    }
}

/// How the map draws the fog and the today highlight. Chosen in Settings.
enum FogStyle: String, CaseIterable, Identifiable {
    /// Grey fog with round holes and a gold tint over today's cells.
    case original
    /// Soft fog with a route line through today's cells.
    case trail
    /// Soft fog that leaves only today's cells fully clear while the highlight is on.
    case spotlight

    var id: Self { self }

    var title: String {
        switch self {
        case .original:  "Original"
        case .trail:     "Trail"
        case .spotlight: "Spotlight"
        }
    }
}

@MainActor
@Observable
final class GridSettings {
    @ObservationIgnored private let defaults: UserDefaults?

    var todayHighlight: TodayHighlight {
        didSet {
            defaults?.set(todayHighlight.rawValue, forKey: Keys.todayHighlight)
        }
    }

    var showLandmarks: Bool {
        didSet {
            defaults?.set(showLandmarks, forKey: Keys.showLandmarks)
        }
    }

    var fogStyle: FogStyle {
        didSet {
            defaults?.set(fogStyle.rawValue, forKey: Keys.fogStyle)
        }
    }

    private enum Keys {
        static let todayHighlight = "com.fogofwalk.todayHighlight"
        /// The earlier on/off setting, read once when `todayHighlight` is unset.
        static let legacyHighlightToday = "com.fogofwalk.highlightToday"
        static let showLandmarks  = "com.fogofwalk.showLandmarks"
        static let fogStyle       = "com.fogofwalk.fogStyle"
    }

    /// The cutoff date for highlighting — start of today when active, nil when off.
    var highlightCutoffDate: Date? {
        todayHighlight == .off ? nil : Calendar.current.startOfDay(for: Date())
    }

    /// Passing nil keeps settings in memory, for isolated fixtures.
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let raw = defaults?.string(forKey: Keys.todayHighlight),
           let saved = TodayHighlight(rawValue: raw) {
            todayHighlight = saved
        } else {
            todayHighlight = defaults?.bool(forKey: Keys.legacyHighlightToday) == true ? .newToday : .off
        }
        showLandmarks  = defaults?.bool(forKey: Keys.showLandmarks) ?? false
        fogStyle       = defaults?.string(forKey: Keys.fogStyle).flatMap(FogStyle.init(rawValue:)) ?? .original
    }
}
