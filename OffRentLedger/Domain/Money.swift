import Foundation

/// Currency amounts in OffRent Ledger are `Decimal`, never `Double`.
///
/// Binary floating point cannot represent 0.10 exactly, and a rental estimate is added to itself
/// once per billing period for the life of the rental. Over a 400-day rental that error is
/// visible to the user, and this app's entire value proposition is that its numbers can be put
/// next to a vendor invoice.
typealias Money = Decimal

/// The single place where money is rounded.
///
/// Every derived figure in the app passes through `MoneyMath.rounded` exactly once, at the point
/// it becomes a value the user will see or store. Intermediate arithmetic is left unrounded so
/// that rounding is applied once rather than compounding.
enum MoneyMath {

    /// US dollars. Revisit if the app ever ships outside the US App Store.
    static let fractionDigits: Int16 = 2

    /// Banker's rounding (round-half-to-even).
    ///
    /// Chosen over `.plain` because the app repeatedly rounds sums of similar magnitudes;
    /// round-half-up biases such a series upward, which would systematically overstate an
    /// estimate the user is about to compare against a real invoice.
    static let mode: NSDecimalNumber.RoundingMode = .bankers

    static func rounded(_ value: Decimal, places: Int16 = fractionDigits) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, Int(places), mode)
        return output
    }

    static func sum(_ values: [Decimal]) -> Decimal {
        values.reduce(Decimal.zero, +)
    }

    /// `value * count`, expressed without `Double` at any point.
    static func multiply(_ value: Decimal, by count: Int) -> Decimal {
        value * Decimal(count)
    }

    /// True when the two amounts agree to the cent.
    ///
    /// Both sides are rounded first: an expectation built from a daily rate and an invoice figure
    /// typed by a user can differ in the third decimal place without meaning anything.
    static func equalToTheCent(_ lhs: Decimal, _ rhs: Decimal) -> Bool {
        rounded(lhs) == rounded(rhs)
    }

    static func isNegative(_ value: Decimal) -> Bool { value < .zero }

    /// Absolute difference, rounded. Never negative.
    static func absoluteDifference(_ lhs: Decimal, _ rhs: Decimal) -> Decimal {
        let difference = rounded(lhs) - rounded(rhs)
        return difference < .zero ? -difference : difference
    }

    /// Parses a currency amount out of free text, for OCR suggestions and for pasted input.
    ///
    /// Accepts `1234.56`, `1,234.56`, `$1,234.56`, `USD 1,234.56`. Accounting negatives —
    /// `(45.00)` — are recognised, because vendor credit lines use them.
    ///
    /// Rejects anything where the comma is not an unambiguous US thousands separator. `12,34` is
    /// a European decimal comma and is refused rather than read as `1234`: on a scanned invoice
    /// there is no way to tell those apart from the text alone, and being wrong turns $1,200.50
    /// into $1.20 on a document the user is about to take back to their rental yard.
    static func parse(_ raw: String) -> Decimal? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        var negative = false
        if text.hasPrefix("(") && text.hasSuffix(")") {
            negative = true
            text = String(text.dropFirst().dropLast())
        }
        if text.hasPrefix("-") {
            negative = true
            text = String(text.dropFirst())
        }

        // Strip currency decoration, but nothing that could carry magnitude.
        text = text
            .uppercased()
            .replacingOccurrences(of: "USD", with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        if text.contains(",") {
            guard let ungrouped = strippingUSThousandsSeparators(text) else { return nil }
            text = ungrouped
        }

        let allowed = Set("0123456789.")
        guard text.allSatisfy({ allowed.contains($0) }) else { return nil }
        // Two decimal points is not a number; it is two numbers run together by OCR.
        guard text.filter({ $0 == "." }).count <= 1 else { return nil }
        guard !text.hasPrefix("."), !text.hasSuffix(".") else { return nil }
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        return negative ? -value : value
    }

    /// Returns the digits with grouping commas removed, or nil when the commas are not valid US
    /// thousands separators: `1,234,567.89` yes, `12,34` no, `1,2345` no.
    private static func strippingUSThousandsSeparators(_ text: String) -> String? {
        let groups = text.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard groups.count >= 2 else { return nil }

        // The leading group is 1–3 digits.
        guard (1...3).contains(groups[0].count), groups[0].allSatisfy(\.isNumber) else { return nil }

        for (offset, group) in groups.dropFirst().enumerated() {
            let isFinalGroup = offset == groups.count - 2
            if isFinalGroup {
                // Only the last group may carry the decimal portion.
                let parts = group.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
                guard parts.count <= 2 else { return nil }
                guard parts[0].count == 3, parts[0].allSatisfy(\.isNumber) else { return nil }
                if parts.count == 2 {
                    guard !parts[1].isEmpty, parts[1].allSatisfy(\.isNumber) else { return nil }
                }
            } else {
                guard group.count == 3, group.allSatisfy(\.isNumber) else { return nil }
            }
        }
        return text.replacingOccurrences(of: ",", with: "")
    }
}
