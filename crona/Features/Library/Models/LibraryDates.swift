import Foundation

/// Date-only arithmetic uses UTC; timestamps use the daemon's display timezone.
enum LibraryDates {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    static func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value) ?? Date()
    }

    static func string(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func adding(_ days: Int, to value: String) -> String {
        string(calendar.date(byAdding: .day, value: days, to: date(value))!)
    }

    static func timestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func clock(_ value: String?, timezone: String, includeDate: Bool = false, settings: CronaCoreSettings? = nil)
        -> String?
    {
        guard let date = timestamp(value) else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
        formatter.dateStyle = includeDate ? .medium : .none
        formatter.timeStyle = .short
        if includeDate, let settings {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = formatter.timeZone
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let shownDate = CronaDateDisplayFormatter.string(
                fromISODate: dateFormatter.string(from: date), settings: settings)
            formatter.dateStyle = .none
            return "\(shownDate) at \(formatter.string(from: date))"
        }
        return formatter.string(from: date)
    }
}
