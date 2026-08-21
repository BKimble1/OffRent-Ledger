import Foundation

enum DiscrepancyType: String, CaseIterable, Codable, Sendable {
    case rentalSubtotalDiffers
    case invoiceTotalDoesNotMatchLines
    case billedBeyondConfirmationDate
    case billedBeyondPickupDate
    case negativeInvoiceTotal
    case chargeNotInConfirmedTerms

    var displayName: String {
        switch self {
        case .rentalSubtotalDiffers: "Rental subtotal differs from your confirmed terms"
        case .invoiceTotalDoesNotMatchLines: "Invoice total differs from the sum of its lines"
        case .billedBeyondConfirmationDate: "Billed past the date you recorded a confirmation"
        case .billedBeyondPickupDate: "Billed past the pickup date you recorded"
        case .negativeInvoiceTotal: "Invoice total is negative"
        case .chargeNotInConfirmedTerms: "Charge is not in the terms you confirmed"
        }
    }

    /// Whether this finding carries a monetary difference that belongs in "possible variance".
    ///
    /// Only differences the app can actually derive from user-confirmed terms count. A damage fee
    /// the app knows nothing about is surfaced for review, but calling it "variance" would be
    /// claiming the app knows the charge is wrong. It does not.
    var contributesToVariance: Bool {
        switch self {
        case .rentalSubtotalDiffers, .invoiceTotalDoesNotMatchLines: true
        case .billedBeyondConfirmationDate, .billedBeyondPickupDate, .negativeInvoiceTotal,
             .chargeNotInConfirmedTerms:
            false
        }
    }
}

enum DiscrepancyStatus: String, CaseIterable, Codable, Sendable {
    case open
    case accepted
    case followUpRecorded
    case resolved

    var displayName: String {
        switch self {
        case .open: "Open"
        case .accepted: "Accepted"
        case .followUpRecorded: "Follow-up recorded"
        case .resolved: "Resolved"
        }
    }

    var isOpen: Bool { self == .open || self == .followUpRecorded }
}

/// One thing worth a second look. Never a verdict.
struct DiscrepancyValue: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var type: DiscrepancyType
    var lineID: UUID?
    var expectedAmount: Decimal?
    var invoicedAmount: Decimal?
    var difference: Decimal?
    /// Written to be readable months later by someone who was not there, and phrased so that it
    /// never asserts the vendor is wrong.
    var explanation: String
    var status: DiscrepancyStatus
    var createdAt: Date
    var resolvedAt: Date?
    var resolutionNotes: String?

    init(
        id: UUID = UUID(),
        type: DiscrepancyType,
        lineID: UUID? = nil,
        expectedAmount: Decimal? = nil,
        invoicedAmount: Decimal? = nil,
        difference: Decimal? = nil,
        explanation: String,
        status: DiscrepancyStatus = .open,
        createdAt: Date,
        resolvedAt: Date? = nil,
        resolutionNotes: String? = nil
    ) {
        self.id = id
        self.type = type
        self.lineID = lineID
        self.expectedAmount = expectedAmount
        self.invoicedAmount = invoicedAmount
        self.difference = difference
        self.explanation = explanation
        self.status = status
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.resolutionNotes = resolutionNotes
    }
}

/// A line the user has not yet said anything about, in a category the app cannot form an
/// expectation for. Shown as "Review this charge" — a checklist item, not an accusation.
struct ChargeReviewFlag: Sendable, Equatable, Identifiable {
    var id: UUID { lineID }
    var lineID: UUID
    var category: InvoiceCategory
    var amount: Decimal
    var detail: String
    var appearedInContract: Bool

    var prompt: String {
        appearedInContract
            ? "Review this charge. It matches something in the terms you entered."
            : "Review this charge. It is not in the terms you entered."
    }
}

/// Everything the comparison needs. All user-confirmed; none of it inferred.
struct InvoiceComparisonInput: Sendable {
    var terms: RentalTerms
    /// When the user recorded the vendor's off-rent confirmation, if they have.
    var confirmationDate: Date?
    var pickupDate: Date?
    var invoice: InvoiceValue
    /// If the user typed what they expect the rental portion to be, that wins over anything the
    /// app derives. The user has the contract; the app has a scan of part of it.
    var expectedRentalSubtotalOverride: Decimal?
    var calendar: Calendar
    var now: Date

    init(
        terms: RentalTerms,
        confirmationDate: Date? = nil,
        pickupDate: Date? = nil,
        invoice: InvoiceValue,
        expectedRentalSubtotalOverride: Decimal? = nil,
        calendar: Calendar,
        now: Date
    ) {
        self.terms = terms
        self.confirmationDate = confirmationDate
        self.pickupDate = pickupDate
        self.invoice = invoice
        self.expectedRentalSubtotalOverride = expectedRentalSubtotalOverride
        self.calendar = calendar
        self.now = now
    }
}

struct InvoiceComparison: Sendable, Equatable {
    var expectedRentalSubtotal: Decimal?
    /// Plain-language account of how `expectedRentalSubtotal` was reached, shown verbatim in the
    /// side-by-side review and in the evidence packet. If the app cannot explain a number, it
    /// should not be showing it.
    var expectationBasis: String
    var expectedBilledThroughDate: Date?
    var expectedPeriods: Int

    var invoicedRentalSubtotal: Decimal
    var invoiceTotal: Decimal
    var lineSum: Decimal

    var findings: [DiscrepancyValue]
    var reviewFlags: [ChargeReviewFlag]

    /// Sum of the absolute differences of the open findings that carry a derived expectation.
    var possibleVariance: Decimal

    var openFindings: [DiscrepancyValue] { findings.filter { $0.status.isOpen } }

    /// True when there is nothing left for the user to look at. Drives whether Resolve is offered.
    var isFullyExplained: Bool { openFindings.isEmpty && reviewFlags.isEmpty }
}

/// Compares a vendor invoice against the terms the user confirmed.
///
/// Every output of this engine is a *review flag*. The engine never decides that an invoice is
/// wrong, never suggests an amount the user should pay, and never characterises a vendor. It
/// answers one question: "given what you told me, is there anything here you would want to look
/// at?" The user decides everything after that.
enum InvoiceComparisonEngine {

    static func compare(_ input: InvoiceComparisonInput) -> InvoiceComparison {
        let invoice = input.invoice
        var findings: [DiscrepancyValue] = []

        let invoicedRentalSubtotal = invoice.amount(for: .rentalSubtotal)
        let lineSum = invoice.lineSum

        // MARK: The expectation

        // Off-rent is the point of the product: the rental should stop being billed when the
        // vendor confirmed it, even if the machine physically sits on site for another week.
        // So the expectation runs to the confirmation date when there is one, and only falls
        // back to pickup — or to now — when there is not.
        let billedThrough = input.confirmationDate ?? input.pickupDate ?? input.now
        let expectedPeriods = expectedPeriods(terms: input.terms, billedThrough: billedThrough, calendar: input.calendar)

        var expected: Decimal?
        var basis: String

        if let override = input.expectedRentalSubtotalOverride {
            expected = MoneyMath.rounded(override)
            basis = "You entered this expected rental amount."
        } else if let perPeriod = input.terms.rateCard.amount(for: input.terms.billingBasis),
                  perPeriod > .zero {
            expected = MoneyMath.rounded(MoneyMath.multiply(perPeriod, by: expectedPeriods))
            let source = input.confirmationDate != nil
                ? "the date you recorded the vendor's confirmation"
                : (input.pickupDate != nil ? "the pickup date you recorded" : "today")
            basis = """
                Based on the terms you confirmed: \(expectedPeriods) \
                \(expectedPeriods == 1 ? input.terms.billingBasis.shortName : input.terms.billingBasis.shortName + "s") \
                at the \(input.terms.billingBasis.shortName) rate, counted from delivery through \(source).
                """
        } else {
            expected = nil
            basis = """
                No \(input.terms.billingBasis.shortName) rate is confirmed for this item, so \
                OffRent Ledger cannot form an expected rental amount. Review the invoice against \
                your contract directly.
                """
        }

        // MARK: Findings

        if let expected, !MoneyMath.equalToTheCent(expected, invoicedRentalSubtotal) {
            let difference = MoneyMath.absoluteDifference(invoicedRentalSubtotal, expected)
            let direction = invoicedRentalSubtotal > expected ? "more than" : "less than"
            findings.append(
                DiscrepancyValue(
                    type: .rentalSubtotalDiffers,
                    expectedAmount: expected,
                    invoicedAmount: MoneyMath.rounded(invoicedRentalSubtotal),
                    difference: difference,
                    explanation: """
                        The invoice's rental subtotal is \(direction) the amount expected from the \
                        terms you confirmed. \(basis) This is a possible mismatch to look at, not \
                        a determination that the invoice is wrong.
                        """,
                    createdAt: input.now
                )
            )
        }

        if !invoice.lines.isEmpty, !MoneyMath.equalToTheCent(invoice.invoiceTotal, lineSum) {
            findings.append(
                DiscrepancyValue(
                    type: .invoiceTotalDoesNotMatchLines,
                    expectedAmount: MoneyMath.rounded(lineSum),
                    invoicedAmount: MoneyMath.rounded(invoice.invoiceTotal),
                    difference: MoneyMath.absoluteDifference(invoice.invoiceTotal, lineSum),
                    explanation: """
                        The total you entered does not equal the sum of the lines you entered. \
                        Check for a line that was missed or entered twice before treating this as \
                        a vendor issue.
                        """,
                    createdAt: input.now
                )
            )
        }

        if MoneyMath.isNegative(invoice.invoiceTotal) {
            findings.append(
                DiscrepancyValue(
                    type: .negativeInvoiceTotal,
                    invoicedAmount: MoneyMath.rounded(invoice.invoiceTotal),
                    explanation: "The invoice total is negative. If this is a credit memo, note that here.",
                    createdAt: input.now
                )
            )
        }

        if let billedThroughDate = invoice.billedThroughDate {
            if let confirmationDate = input.confirmationDate,
               input.calendar.wholeDays(from: confirmationDate, to: billedThroughDate) > 0 {
                let days = input.calendar.wholeDays(from: confirmationDate, to: billedThroughDate)
                findings.append(
                    DiscrepancyValue(
                        type: .billedBeyondConfirmationDate,
                        explanation: """
                            The invoice is billed through a date \(days) day\(days == 1 ? "" : "s") \
                            after the confirmation you recorded. Vendor terms decide whether that \
                            is correct — this is a prompt to check, using the confirmation number \
                            you captured.
                            """,
                        createdAt: input.now
                    )
                )
            } else if input.confirmationDate == nil,
                      let pickupDate = input.pickupDate,
                      input.calendar.wholeDays(from: pickupDate, to: billedThroughDate) > 0 {
                findings.append(
                    DiscrepancyValue(
                        type: .billedBeyondPickupDate,
                        explanation: """
                            The invoice is billed through a date after the pickup you recorded. \
                            Check the vendor's terms for how it bills between off-rent and pickup.
                            """,
                        createdAt: input.now
                    )
                )
            }
        }

        // MARK: Review flags

        // Not findings. A checklist of charges the app has no basis to have an opinion about,
        // which clears as the user works through them.
        let reviewFlags = invoice.lines
            .filter { $0.reviewState == .unreviewed && !$0.category.isDerivableFromTerms }
            .filter { $0.amount != .zero }
            .map {
                ChargeReviewFlag(
                    lineID: $0.id,
                    category: $0.category,
                    amount: MoneyMath.rounded($0.amount),
                    detail: $0.detail,
                    appearedInContract: $0.appearedInContract
                )
            }

        let variance = MoneyMath.sum(
            findings
                .filter { $0.status.isOpen && $0.type.contributesToVariance }
                .compactMap(\.difference)
        )

        return InvoiceComparison(
            expectedRentalSubtotal: expected,
            expectationBasis: basis,
            expectedBilledThroughDate: billedThrough,
            expectedPeriods: expectedPeriods,
            invoicedRentalSubtotal: MoneyMath.rounded(invoicedRentalSubtotal),
            invoiceTotal: MoneyMath.rounded(invoice.invoiceTotal),
            lineSum: MoneyMath.rounded(lineSum),
            findings: findings,
            reviewFlags: reviewFlags,
            possibleVariance: MoneyMath.rounded(variance)
        )
    }

    static func expectedPeriods(
        terms: RentalTerms, billedThrough: Date, calendar: Calendar
    ) -> Int {
        let days = calendar.wholeDays(from: terms.deliveryDate, to: billedThrough)
        return RentalRateEngine.periodsStarted(daysOnRent: days, basis: terms.billingBasis)
    }
}
