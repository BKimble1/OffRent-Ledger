import Foundation

/// One row of the rental summary CSV.
struct RentalSummaryRow: Sendable, Equatable {
    var vendorName: String
    var vendorBranch: String?
    var jobSiteName: String?
    var agreementNumber: String?
    /// The contractor's own purchase-order or job number.
    ///
    /// The vendor's agreement number identifies the paperwork; this identifies the *job*, and it
    /// is the column an accounts department joins this export to their own cost codes on. It was
    /// captured on the agreement, editable on the form, searchable and on the map — and missing
    /// from the one output anybody reconciles with.
    var purchaseOrderNumber: String?
    var equipmentName: String
    var vendorEquipmentIdentifier: String?
    var status: RentalItemStatus
    var deliveryDate: Date
    var billingBasis: BillingBasis
    var dailyRate: Decimal?
    var weeklyRate: Decimal?
    var fourWeekRate: Decimal?
    var nextRolloverDate: Date?
    var estimatedRunningCost: Decimal?
    var estimateIsComplete: Bool
    var confirmationNumber: String?
    var confirmationRecordedAt: Date?
    var pickupRecordedAt: Date?
    var invoiceNumber: String?
    var invoiceTotal: Decimal?
    var possibleVariance: Decimal?
    var openMismatchCount: Int
    var notes: String?
}

/// Produces a spreadsheet-safe CSV.
///
/// Two things here are not decoration:
///
/// - **Escaping.** A jobsite called `Ridgeline, Phase 2` or a note containing a newline will
///   otherwise silently shift every subsequent column, and the user will not notice until they
///   are reading the wrong number in front of their rental yard.
/// - **Formula neutralisation.** A vendor name beginning `=`, `+`, `-` or `@` is executed as a
///   formula when the file is opened in Excel or Numbers. That is CSV injection, and the fix is
///   to prefix the cell with an apostrophe so it opens as text.
enum CSVExport {

    static let header = [
        "Vendor", "Branch", "Jobsite", "Agreement #", "PO / Reference",
        "Equipment", "Vendor Equipment ID",
        "Status", "Delivery Date", "Billing Basis", "Daily Rate", "Weekly Rate", "4-Week Rate",
        "Next Rate Change", "Estimated Rent (estimate)", "Estimate Complete",
        "Confirmation #", "Confirmation Recorded", "Pickup Recorded",
        "Invoice #", "Invoice Total", "Possible Variance", "Open Possible Mismatches", "Notes",
    ]

    static func makeCSV(rows: [RentalSummaryRow], calendar: Calendar) -> String {
        var lines = [header.map(escape).joined(separator: ",")]
        for row in rows {
            let fields: [String] = [
                row.vendorName,
                row.vendorBranch ?? "",
                row.jobSiteName ?? "",
                row.agreementNumber ?? "",
                row.purchaseOrderNumber ?? "",
                row.equipmentName,
                row.vendorEquipmentIdentifier ?? "",
                row.status.displayName,
                isoDate(row.deliveryDate, calendar: calendar),
                row.billingBasis.displayName,
                amount(row.dailyRate),
                amount(row.weeklyRate),
                amount(row.fourWeekRate),
                row.nextRolloverDate.map { isoDate($0, calendar: calendar) } ?? "",
                row.estimateIsComplete ? amount(row.estimatedRunningCost) : "",
                row.estimateIsComplete ? "yes" : "no",
                row.confirmationNumber ?? "",
                row.confirmationRecordedAt.map { isoDateTime($0, calendar: calendar) } ?? "",
                row.pickupRecordedAt.map { isoDateTime($0, calendar: calendar) } ?? "",
                row.invoiceNumber ?? "",
                amount(row.invoiceTotal),
                amount(row.possibleVariance),
                String(row.openMismatchCount),
                row.notes ?? "",
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// RFC 4180 quoting, plus formula neutralisation.
    static func escape(_ field: String) -> String {
        var value = field
        if let first = value.first, "=+-@\t\r".contains(first) {
            value = "'" + value
        }
        let needsQuotes = value.contains(",") || value.contains("\"")
            || value.contains("\n") || value.contains("\r")
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Plain decimal digits, no currency symbol and no grouping.
    ///
    /// A spreadsheet parses `1234.56`; it treats `$1,234.56` as text, and the user's SUM silently
    /// returns zero.
    static func amount(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return "\(MoneyMath.rounded(value))"
    }

    static func isoDate(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func isoDateTime(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
