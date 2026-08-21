import Foundation

/// "Now" is injected everywhere.
///
/// Rental billing is entirely about when a boundary is crossed, so a test that cannot control the
/// clock cannot test the thing that matters. Nothing in `Domain` calls `Date()`.
protocol Clock: Sendable {
    var now: Date { get }
    /// The calendar to use for day arithmetic, including its time zone.
    var calendar: Calendar { get }
}

struct SystemClock: Clock {
    var timeZone: TimeZone
    var calendarIdentifier: Calendar.Identifier

    init(timeZone: TimeZone = .current, calendarIdentifier: Calendar.Identifier = .gregorian) {
        self.timeZone = timeZone
        self.calendarIdentifier = calendarIdentifier
    }

    var now: Date { Date() }

    var calendar: Calendar {
        var calendar = Calendar(identifier: calendarIdentifier)
        calendar.timeZone = timeZone
        return calendar
    }
}

/// A clock frozen at a chosen instant, for tests and previews.
struct FixedClock: Clock {
    var now: Date
    var calendar: Calendar

    init(now: Date, timeZone: TimeZone = TimeZone(identifier: "America/Chicago") ?? .gmt) {
        self.now = now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// Convenience for readable test setup: `FixedClock(2026, 3, 7, 9, 0, in: "America/Chicago")`.
    init(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0,
        in timeZoneIdentifier: String = "America/Chicago"
    ) {
        let zone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        self.calendar = calendar
        self.now = calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}

extension Calendar {
    /// Whole calendar days between two instants, counted by day boundary rather than by elapsed
    /// seconds.
    ///
    /// This distinction is the reason rentals bill correctly across a daylight-saving change: the
    /// day the clocks move forward is 23 hours long, and dividing elapsed seconds by 86 400 loses
    /// it. `dateComponents(_:from:to:)` does not.
    func wholeDays(from start: Date, to end: Date) -> Int {
        let startDay = startOfDay(for: start)
        let endDay = startOfDay(for: end)
        return dateComponents([.day], from: startDay, to: endDay).day ?? 0
    }

    func addingDays(_ days: Int, to date: Date) -> Date {
        self.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// Same wall-clock time of day, `days` later. Used for rollover boundaries, which vendors
    /// express as "next Tuesday at 7am", not as "168 hours from now".
    func addingDaysPreservingTimeOfDay(_ days: Int, to date: Date) -> Date {
        var components = dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        components.day = (components.day ?? 0) + days
        return self.date(from: components) ?? addingDays(days, to: date)
    }
}
