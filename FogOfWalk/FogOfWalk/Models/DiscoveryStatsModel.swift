import CoreData
import CoreLocation
import MapKit
import Observation

// MARK: - Supporting types

enum LocalityPeriod: String, CaseIterable, Identifiable {
    case today     = "today"
    case thisWeek  = "thisWeek"
    case thisMonth = "thisMonth"
    case allTime   = "allTime"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today:     return "Today"
        case .thisWeek:  return "This Week"
        case .thisMonth: return "This Month"
        case .allTime:   return "All Time"
        }
    }

    var emptyStateLabel: String {
        switch self {
        case .today:     return "today"
        case .thisWeek:  return "this week"
        case .thisMonth: return "this month"
        case .allTime:   return "yet"
        }
    }
}

struct DailyCount: Identifiable {
    let date: Date   // midnight of the day (Calendar.current.startOfDay)
    let count: Int
    var id: Date { date }
}

struct LocalityStats: Identifiable {
    let name: String
    let count: Int
    let center: CLLocationCoordinate2D
    let span: MKCoordinateSpan
    var id: String { name }
}

// MARK: - LocalityStats geometry helpers

private func localityCentroid(_ cells: [CellID]) -> CLLocationCoordinate2D {
    guard !cells.isEmpty else { return CLLocationCoordinate2D() }
    var sumLat = 0.0
    var sumLon = 0.0
    for cell in cells {
        let c = GridMath.center(for: cell)
        sumLat += c.latitude
        sumLon += c.longitude
    }
    return CLLocationCoordinate2D(latitude: sumLat / Double(cells.count),
                                  longitude: sumLon / Double(cells.count))
}

private func localitySpan(_ cells: [CellID]) -> MKCoordinateSpan {
    guard !cells.isEmpty else {
        return MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    }
    var minLat = Double.infinity, maxLat = -Double.infinity
    var minLon = Double.infinity, maxLon = -Double.infinity
    for cell in cells {
        let b = GridMath.bounds(for: cell)
        minLat = min(minLat, b.min.latitude)
        maxLat = max(maxLat, b.max.latitude)
        minLon = min(minLon, b.min.longitude)
        maxLon = max(maxLon, b.max.longitude)
    }
    return MKCoordinateSpan(
        latitudeDelta: max((maxLat - minLat) * 1.5, 0.01),
        longitudeDelta: max((maxLon - minLon) * 1.5, 0.01)
    )
}

// MARK: - DiscoveryStatsModel

@MainActor
@Observable
final class DiscoveryStatsModel {

    // MARK: - Published state

    var last24HourCount: Int = 0
    /// Always exactly 7 entries, oldest-to-newest, zero-filled for empty days.
    var last7DaysByDay: [DailyCount] = []
    var allTimeTotal: Int = 0
    var firstWalkDate: Date? = nil
    var bestDayCount: Int = 0
    var bestDayDate: Date? = nil
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var totalDaysActive: Int = 0
    var estimatedDistanceMeters: Double = 0
    /// Sorted by count descending for each period. Cells with nil locality appear as "Unknown".
    var localityByPeriod: [LocalityPeriod: [LocalityStats]] = [:]
    /// All-time only (no per-period breakdown). Cells with nil state/country appear as "Unknown".
    var stateStats: [LocalityStats] = []
    /// All-time only (no per-period breakdown). Cells with nil state/country appear as "Unknown".
    var countryStats: [LocalityStats] = []

    func locality(for period: LocalityPeriod) -> [LocalityStats] {
        localityByPeriod[period] ?? []
    }

    // MARK: - Refresh

    func refresh(context: NSManagedObjectContext) {
        let request = VisitedCell.fetchRequest()
        request.predicate = NSPredicate(format: "cellSizeMeters == %f", kCellSizeMeters)
        request.sortDescriptors = [NSSortDescriptor(key: "firstVisited", ascending: true)]

        guard let cells = try? context.fetch(request) else { return }

        let now      = Date()
        let calendar = Calendar.current

        // Cutoffs — use Calendar-safe arithmetic to correctly handle DST transitions.
        let cutoff24h   = calendar.startOfDay(for: now)
        let cutoff7d    = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -6, to: now) ?? now
        )
        let cutoffToday = calendar.startOfDay(for: now)
        let cutoffMonth = calendar.dateInterval(of: .month, for: now)?.start
                          ?? calendar.startOfDay(for: calendar.date(byAdding: .month, value: -1, to: now) ?? now)

        // Single pass: accumulate all stat buckets simultaneously.
        var allDayCounts:      [Date: Int]        = [:]
        var allLocalityCells:  [String: [CellID]] = [:]
        var allStateCells:     [String: [CellID]] = [:]
        var allCountryCells:   [String: [CellID]] = [:]
        var last24Count        = 0
        var recentDayCounts:   [Date: Int]        = [:]
        var recentLocalCells:  [String: [CellID]] = [:]
        var todayLocalCells:   [String: [CellID]] = [:]
        var monthLocalCells:   [String: [CellID]] = [:]

        for cell in cells {
            guard let visited = cell.firstVisited else { continue }
            let day      = calendar.startOfDay(for: visited)
            let cellID   = CellID(x: cell.cellX, y: cell.cellY)
            let locality = cell.locality ?? "Unknown"

            // All-time buckets
            allDayCounts[day, default: 0] += 1
            allLocalityCells[locality, default: []].append(cellID)
            let state   = cell.state ?? "Unknown"
            let country = cell.country ?? "Unknown"
            allStateCells[state, default: []].append(cellID)
            allCountryCells[country, default: []].append(cellID)

            // Last 24 hours
            if visited >= cutoff24h { last24Count += 1 }

            // Last 7 days
            if visited >= cutoff7d {
                recentDayCounts[day, default: 0] += 1
                recentLocalCells[locality, default: []].append(cellID)
            }

            // Today
            if visited >= cutoffToday {
                todayLocalCells[locality, default: []].append(cellID)
            }

            // This month
            if visited >= cutoffMonth {
                monthLocalCells[locality, default: []].append(cellID)
            }
        }

        // All-time stats
        allTimeTotal   = cells.count
        firstWalkDate  = cells.first?.firstVisited

        if let best = allDayCounts.max(by: { $0.value < $1.value }) {
            bestDayCount = best.value
            bestDayDate  = best.key
        } else {
            bestDayCount = 0
            bestDayDate  = nil
        }

        totalDaysActive        = allDayCounts.count
        estimatedDistanceMeters = Double(allTimeTotal) * kCellSizeMeters

        // Streaks (computed from sorted day keys)
        let sortedDays = allDayCounts.keys.sorted()
        var longestRun = 0
        var currentRun = 0
        var prevDay: Date? = nil
        for day in sortedDays {
            if let prev = prevDay,
               calendar.dateComponents([.day], from: prev, to: day).day == 1 {
                currentRun += 1
            } else {
                currentRun = 1
            }
            longestRun = max(longestRun, currentRun)
            prevDay = day
        }
        longestStreak = longestRun

        // Current streak — must include today or yesterday
        let today = calendar.startOfDay(for: now)
        if let last = sortedDays.last,
           (calendar.dateComponents([.day], from: last, to: today).day ?? Int.max) <= 1 {
            var streak = 1
            for i in stride(from: sortedDays.count - 2, through: 0, by: -1) {
                if calendar.dateComponents([.day], from: sortedDays[i], to: sortedDays[i + 1]).day == 1 {
                    streak += 1
                } else {
                    break
                }
            }
            currentStreak = streak
        } else {
            currentStreak = 0
        }

        // Last 24-hour count
        last24HourCount = last24Count

        // Last 7 days — build 7 slots (index 0 = 6 days ago, index 6 = today)
        last7DaysByDay = (0..<7).map { offset in
            let date = calendar.startOfDay(
                for: calendar.date(byAdding: .day, value: offset - 6, to: now) ?? now
            )
            return DailyCount(date: date, count: recentDayCounts[date] ?? 0)
        }

        // Locality breakdown by period
        func buildStats(_ dict: [String: [CellID]]) -> [LocalityStats] {
            dict.map { name, ids in
                LocalityStats(
                    name: name,
                    count: ids.count,
                    center: localityCentroid(ids),
                    span: localitySpan(ids)
                )
            }
            .sorted { $0.count > $1.count }
        }

        localityByPeriod = [
            .today:     buildStats(todayLocalCells),
            .thisWeek:  buildStats(recentLocalCells),
            .thisMonth: buildStats(monthLocalCells),
            .allTime:   buildStats(allLocalityCells),
        ]

        stateStats   = buildStats(allStateCells)
        countryStats = buildStats(allCountryCells)
    }
}
