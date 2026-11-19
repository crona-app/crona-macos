import Foundation

/// Retains three browsed months plus the dates needed by the current dashboard.
struct StatsSnapshotCache {
    private var entries: [String: PopoverStatsSnapshot] = [:]
    private var months: [String] = []
    var protectedDates: Set<String> = [] { didSet { prune() } }

    subscript(date: String) -> PopoverStatsSnapshot? {
        mutating get {
            if entries[date] != nil { touch(date) }
            return entries[date]
        }
        set {
            entries[date] = newValue
            if newValue != nil { touch(date); prune() }
        }
    }

    mutating func removeAll() {
        entries.removeAll()
        months.removeAll()
    }

    private mutating func touch(_ date: String) {
        let month = String(date.prefix(7))
        months.removeAll { $0 == month }
        months.append(month)
    }

    private mutating func prune() {
        months = Array(months.suffix(3))
        let retained = Set(months)
        entries = entries.filter { protectedDates.contains($0.key) || retained.contains(String($0.key.prefix(7))) }
    }
}
