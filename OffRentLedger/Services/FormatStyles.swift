import Foundation

/// Formatting used everywhere a number or a date is drawn.
///
/// Centralised so that "how money looks" is one decision. `Decimal` is formatted through
/// `NumberFormatter`/`FormatStyle` and never through `String(format:)` — `%.2f` takes a `Double`,
/// which is the one conversion this app spends its whole domain layer avoiding.
enum Formatters {

    static var currencyLocale: Locale { Locale(identifier: "en_US") }

    /// `$2,280.00`
    static func currency(_ value: Decimal) -> String {
        MoneyMath.rounded(value).formatted(
            .currency(code: "USD").locale(currencyLocale).precision(.fractionLength(2))
        )
    }

    /// `$2,280` — for glanceable contexts like the widget, where two decimal places of an
    /// estimate are noise.
    static func currencyRounded(_ value: Decimal) -> String {
        value.formatted(
            .currency(code: "USD").locale(currencyLocale).precision(.fractionLength(0))
        )
    }

    /// Spoken form, so VoiceOver says "two thousand two hundred eighty dollars" rather than
    /// spelling out punctuation.
    static func currencyAccessible(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = currencyLocale
        formatter.formattingContext = .standalone
        return formatter.string(from: MoneyMath.rounded(value) as NSDecimalNumber) ?? currency(value)
    }

    /// `May 11, 2026`
    static func mediumDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// `May 11, 2026 at 9:00 AM`
    static func dateAndTime(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
    }

    /// `Mon, May 11`
    static func shortWeekdayDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "in 2 days", "tomorrow", "3 hours ago"
    static func relative(_ date: Date, from reference: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = currencyLocale
        return formatter.localizedString(for: date, relativeTo: reference)
    }

    /// `6 days`, `1 day`
    static func dayCount(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }

    /// `214.6 hr`
    static func meterReading(_ value: Decimal, unit: MeterUnit) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...1)))
        return unit == .none ? number : "\(number) \(unit.abbreviation)"
    }
}
