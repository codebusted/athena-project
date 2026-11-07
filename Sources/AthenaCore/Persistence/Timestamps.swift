import Foundation

/// Date policy:
/// - Timestamps (`*_at` columns) are ISO-8601 in UTC with fractional seconds.
/// - A "day" (sessions, streaks, completion) is the user's *local* calendar day, stored as `yyyy-MM-dd`.
///   The day rolls over at local midnight in whatever time zone the Mac is currently in.
public enum Timestamps {
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let lock = NSLock()

    public static func string(from date: Date) -> String {
        lock.withLock { iso.string(from: date) }
    }

    public static func date(from string: String) -> Date? {
        lock.withLock { iso.date(from: string) }
    }
}

public struct DayClock: Sendable {
    public var calendar: Calendar
    public var now: @Sendable () -> Date

    public init(calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.calendar = calendar
        self.now = now
    }

    public func dayString(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public var today: String { dayString(for: now()) }

    public func date(fromDay day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    public func day(_ day: String, offsetBy days: Int) -> String {
        guard let date = date(fromDay: day), let shifted = calendar.date(byAdding: .day, value: days, to: date) else {
            return day
        }
        return dayString(for: shifted)
    }
}
