import Foundation
@testable import OffRentDomain

enum TZ {
    static let chicago = TimeZone(identifier: "America/Chicago") ?? .gmt
    static let denver = TimeZone(identifier: "America/Denver") ?? .gmt
    static let honolulu = TimeZone(identifier: "Pacific/Honolulu") ?? .gmt   // no DST
    static let gmt = TimeZone(identifier: "GMT") ?? .gmt
}

func calendar(_ timeZone: TimeZone = TZ.chicago) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
}

/// `date(2026, 3, 6, 7)` — readable fixtures, no formatter parsing in tests.
func date(
    _ year: Int, _ month: Int, _ day: Int,
    _ hour: Int = 0, _ minute: Int = 0,
    _ timeZone: TimeZone = TZ.chicago
) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = timeZone
    guard let result = cal.date(from: components) else {
        fatalError("Test fixture date is not constructible: \(year)-\(month)-\(day) \(hour):\(minute)")
    }
    return result
}

func money(_ string: String) -> Decimal {
    guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
        fatalError("Test fixture money is not parseable: \(string)")
    }
    return value
}

extension RentalTerms {
    /// A skid-steer on a daily rate, the walkthrough fixture from the product spec.
    static func skidSteer(
        delivered: Date,
        daily: String = "285.00",
        basis: BillingBasis = .daily,
        mode: RolloverMode = .manual,
        nextRollover: Date? = nil,
        expectedIncrement: String? = nil
    ) -> RentalTerms {
        RentalTerms(
            deliveryDate: delivered,
            rateCard: RateCard(daily: money(daily), weekly: money("985.00"), fourWeek: money("2450.00")),
            billingBasis: basis,
            rolloverMode: mode,
            nextRolloverDate: nextRollover,
            expectedNextIncrement: expectedIncrement.map(money)
        )
    }
}
