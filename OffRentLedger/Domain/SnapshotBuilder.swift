import Foundation

/// What the snapshot builder needs to know about one item.
struct SnapshotItemInput: Sendable, Equatable {
    var status: RentalItemStatus
    var terms: RentalTerms
    var hasInvoiceAwaitingReview: Bool

    init(status: RentalItemStatus, terms: RentalTerms, hasInvoiceAwaitingReview: Bool = false) {
        self.status = status
        self.terms = terms
        self.hasInvoiceAwaitingReview = hasInvoiceAwaitingReview
    }
}

/// Reduces the whole store to the handful of numbers the widget is allowed to see.
///
/// Pure, so the privacy property — that no vendor, jobsite, equipment or per-item figure can
/// reach the widget — is asserted by a test rather than by review. The output type has no field
/// capable of carrying any of them, and this is the only thing that constructs it.
enum SnapshotBuilder {

    static func build(
        items: [SnapshotItemInput],
        now: Date,
        calendar: Calendar
    ) -> RentalSummarySnapshot {

        var openCount = 0
        var accruingCount = 0
        var runningTotal = Decimal.zero
        var awaitingPickup = 0
        var invoicesToReview = 0
        var nextRateChange: Date?

        for item in items {
            if item.status.isOpen { openCount += 1 }

            if item.status.accruesRent {
                accruingCount += 1
                let estimate = RentalRateEngine.estimate(
                    terms: item.terms, asOf: now, calendar: calendar
                )
                // An incomplete estimate contributes nothing rather than zero-with-confidence.
                if estimate.isComplete { runningTotal += estimate.estimatedTotal }

                if let rollover = RentalRateEngine.nextRollover(
                    terms: item.terms, asOf: now, calendar: calendar
                ), rollover.date >= now {
                    nextRateChange = min(nextRateChange ?? rollover.date, rollover.date)
                }
            }

            if item.status == .awaitingPickup || item.status == .confirmationRecorded {
                awaitingPickup += 1
            }
            if item.hasInvoiceAwaitingReview { invoicesToReview += 1 }
        }

        return RentalSummarySnapshot(
            generatedAt: now,
            openItemCount: openCount,
            accruingItemCount: accruingCount,
            estimatedRentRunning: MoneyMath.rounded(runningTotal),
            awaitingPickupCount: awaitingPickup,
            invoicesAwaitingReviewCount: invoicesToReview,
            nextRateChangeDate: nextRateChange
        )
    }
}
