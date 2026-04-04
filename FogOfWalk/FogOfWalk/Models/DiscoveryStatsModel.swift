import CoreData
import CoreLocation
import MapKit
import Observation

// MARK: - Supporting types

struct DailyCount: Identifiable {
    let date: Date   // midnight of the day (Calendar.current.startOfDay)
    let count: Int
    var id: Date { date }
}

struct LocalityStats: Identifiable {
    let locality: String
    let count: Int
    let center: CLLocationCoordinate2D
    let span: MKCoordinateSpan
    var id: String { locality }
}

// MARK: - LocalityStats geometry helpers

private func localityCentroid(_ cells: [CellID], cellSizeMeters: Double) -> CLLocationCoordinate2D {
    guard !cells.isEmpty else { return CLLocationCoordinate2D() }
    var sumLat = 0.0
    var sumLon = 0.0
    for cell in cells {
        let c = GridMath.center(for: cell, cellSizeMeters: cellSizeMeters)
        sumLat += c.latitude
        sumLon += c.longitude
    }
    return CLLocationCoordinate2D(latitude: sumLat / Double(cells.count),
                                  longitude: sumLon / Double(cells.count))
}

private func localitySpan(_ cells: [CellID], cellSizeMeters: Double) -> MKCoordinateSpan {
    guard !cells.isEmpty else {
        return MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    }
    var minLat = Double.infinity, maxLat = -Double.infinity
    var minLon = Double.infinity, maxLon = -Double.infinity
    for cell in cells {
        let b = GridMath.bounds(for: cell, cellSizeMeters: cellSizeMeters)
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
    /// Sorted by count descending. Cells with nil locality appear as "Unknown".
    var last7DaysByLocality: [LocalityStats] = []
    var allTimeTotal: Int = 0
    var firstWalkDate: Date? = nil
    var bestDayCount: Int = 0
    var bestDayDate: Date? = nil
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var totalDaysActive: Int = 0
    var estimatedDistanceMeters: Double = 0
    var allTimeByLocality: [LocalityStats] = []

    // MARK: - Refresh

    func refresh(context: NSManagedObjectContext, cellSizeMeters: Double) {
        let request = VisitedCell.fetchRequest()
        request.predicate = NSPredicate(format: "cellSizeMeters == %f", cellSizeMeters)
        request.sortDescriptors = [NSSortDescriptor(key: "firstVisited", ascending: true)]

        guard let cells = try? context.fetch(request) else { return }

        let now = Date()
        let calendar = Calendar.current

        // All-time
        allTimeTotal = cells.count
        firstWalkDate = cells.first?.firstVisited

        // Best day — group all cells by their calendar day
        var allDayCounts: [Date: Int] = [:]
        for cell in cells {
            guard let visited = cell.firstVisited else { continue }
            let day = calendar.startOfDay(for: visited)
            allDayCounts[day, default: 0] += 1
        }
        if let best = allDayCounts.max(by: { $0.value < $1.value }) {
            bestDayCount = best.value
            bestDayDate  = best.key
        } else {
            bestDayCount = 0
            bestDayDate  = nil
        }

        // Total days active
        totalDaysActive = allDayCounts.count

        // Streaks
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

        // Estimated distance
        estimatedDistanceMeters = Double(allTimeTotal) * cellSizeMeters

        // All-time locality breakdown
        var allLocalityCells: [String: [CellID]] = [:]
        for cell in cells {
            let name = cell.locality ?? "Unknown"
            allLocalityCells[name, default: []].append(CellID(x: cell.cellX, y: cell.cellY))
        }
        allTimeByLocality = allLocalityCells
            .map { name, ids in
                LocalityStats(
                    locality: name,
                    count: ids.count,
                    center: localityCentroid(ids, cellSizeMeters: cellSizeMeters),
                    span: localitySpan(ids, cellSizeMeters: cellSizeMeters)
                )
            }
            .sorted { $0.count > $1.count }

        // Last 24 hours
        let cutoff24h = now.addingTimeInterval(-86400)
        last24HourCount = cells.filter { ($0.firstVisited ?? .distantPast) >= cutoff24h }.count

        // Last 7 days — build 7 slots (index 0 = 6 days ago, index 6 = today)
        let cutoff7d = calendar.startOfDay(for: now.addingTimeInterval(-6 * 86400))
        let recentCells = cells.filter { ($0.firstVisited ?? .distantPast) >= cutoff7d }

        var dayCounts: [Date: Int] = [:]
        for cell in recentCells {
            guard let visited = cell.firstVisited else { continue }
            let day = calendar.startOfDay(for: visited)
            dayCounts[day, default: 0] += 1
        }
        last7DaysByDay = (0..<7).map { offset in
            let date = calendar.startOfDay(for: now.addingTimeInterval(Double(offset - 6) * 86400))
            return DailyCount(date: date, count: dayCounts[date] ?? 0)
        }

        // Locality breakdown for the last 7 days
        var localityCells: [String: [CellID]] = [:]
        for cell in recentCells {
            let name = cell.locality ?? "Unknown"
            localityCells[name, default: []].append(CellID(x: cell.cellX, y: cell.cellY))
        }
        last7DaysByLocality = localityCells
            .map { name, ids in
                LocalityStats(
                    locality: name,
                    count: ids.count,
                    center: localityCentroid(ids, cellSizeMeters: cellSizeMeters),
                    span: localitySpan(ids, cellSizeMeters: cellSizeMeters)
                )
            }
            .sorted { $0.count > $1.count }
    }
}
