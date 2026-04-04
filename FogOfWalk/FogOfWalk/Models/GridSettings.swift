import Foundation
import Observation

enum HighlightPeriod: String, CaseIterable, Identifiable {
    case off       = "off"
    case lastHour  = "lastHour"
    case today     = "today"
    case thisWeek  = "thisWeek"
    case thisMonth = "thisMonth"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:       return "Off"
        case .lastHour:  return "Last Hour"
        case .today:     return "Today"
        case .thisWeek:  return "This Week"
        case .thisMonth: return "This Month"
        }
    }

    /// The earliest date whose cells should be highlighted, or nil for `.off`.
    var cutoffDate: Date? {
        switch self {
        case .off:       return nil
        case .lastHour:  return Calendar.current.date(byAdding: .hour, value: -1, to: Date())
        case .today:     return Calendar.current.startOfDay(for: Date())
        case .thisWeek:  return Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start
        case .thisMonth: return Calendar.current.dateInterval(of: .month, for: Date())?.start
        }
    }
}

@MainActor
@Observable
final class GridSettings {
    var cellSizeMeters: Double {
        didSet {
            UserDefaults.standard.set(cellSizeMeters, forKey: Keys.cellSizeMeters)
        }
    }

    var highlightPeriod: HighlightPeriod {
        didSet {
            UserDefaults.standard.set(highlightPeriod.rawValue, forKey: Keys.highlightPeriod)
        }
    }

    private enum Keys {
        static let cellSizeMeters  = "com.fogofwalk.cellSizeMeters"
        static let highlightPeriod = "com.fogofwalk.highlightPeriod"
    }

    init() {
        let saved = UserDefaults.standard.double(forKey: Keys.cellSizeMeters)
        cellSizeMeters = saved > 0 ? saved : CellSizeMeters.normal.rawValue

        let savedPeriod = UserDefaults.standard.string(forKey: Keys.highlightPeriod) ?? ""
        highlightPeriod = HighlightPeriod(rawValue: savedPeriod) ?? .off
    }
}
