import Foundation

/// What the snapshot builder needs to know about one item.
struct SnapshotItemInput: Sendable, Equatable {
    /// The item's own identifier, so a widget row can open that rental.
    var id: UUID
    /// The equipment, as the user typed it.
    var equipmentName: String
    var status: RentalItemStatus
    var terms: RentalTerms
    var hasInvoiceAwaitingReview: Bool

    init(
        id: UUID = UUID(),
        equipmentName: String = "",
        status: RentalItemStatus,
        terms: RentalTerms,
        hasInvoiceAwaitingReview: Bool = false
    ) {
        self.id = id
        self.equipmentName = equipmentName
        self.status = status
        self.terms = terms
        self.hasInvoiceAwaitingReview = hasInvoiceAwaitingReview
    }
}

/// Reduces the whole store to the handful of things the widget is allowed to see.
///
/// Pure, so the privacy property is asserted by a test rather than by review: the output carries
/// counts, one aggregate figure, one date, and a capped list of machine names with their own
/// estimates. It has no field capable of carrying a rental company, a jobsite, an address, an
/// agreement number, an invoice number or a confirmation number, and this is the only thing that
/// constructs it.
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
        var rows: [RentalSummarySnapshot.Row] = []

        for item in items {
            if item.status.isOpen { openCount += 1 }

            var itemEstimate: Decimal?
            var itemDays: Int?

            if item.status.accruesRent {
                accruingCount += 1
                let estimate = RentalRateEngine.estimate(
                    terms: item.terms, asOf: now, calendar: calendar
                )
                // An incomplete estimate contributes nothing rather than zero-with-confidence,
                // and reaches the row as `nil` rather than as `$0`.
                if estimate.isComplete {
                    runningTotal += estimate.estimatedTotal
                    itemEstimate = MoneyMath.rounded(estimate.estimatedTotal)
                    itemDays = estimate.daysOnRent
                }

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

            // Only open items get a row. A resolved rental is history; the widget is for the
            // things still costing money or still needing a phone call.
            if item.status.isOpen, let state = rowState(for: item.status) {
                rows.append(
                    RentalSummarySnapshot.Row(
                        id: item.id,
                        machine: displayMachine(item.equipmentName),
                        state: state,
                        estimate: itemEstimate,
                        daysOnRent: itemDays
                    )
                )
            }
        }

        return RentalSummarySnapshot(
            generatedAt: now,
            openItemCount: openCount,
            accruingItemCount: accruingCount,
            estimatedRentRunning: MoneyMath.rounded(runningTotal),
            awaitingPickupCount: awaitingPickup,
            invoicesAwaitingReviewCount: invoicesToReview,
            nextRateChangeDate: nextRateChange,
            rows: rank(rows)
        )
    }

    /// Most urgent first, then the largest estimate, then by name so the order is stable between
    /// refreshes. A widget whose rows reshuffle every hour for no visible reason reads as broken.
    private static func rank(_ rows: [RentalSummarySnapshot.Row]) -> [RentalSummarySnapshot.Row] {
        let sorted = rows.sorted { left, right in
            if left.state.urgency != right.state.urgency {
                return left.state.urgency < right.state.urgency
            }
            let leftEstimate = left.estimate ?? .zero
            let rightEstimate = right.estimate ?? .zero
            if leftEstimate != rightEstimate { return leftEstimate > rightEstimate }
            if left.machine != right.machine { return left.machine < right.machine }
            return left.id.uuidString < right.id.uuidString
        }
        return Array(sorted.prefix(RentalSummarySnapshot.maxRows))
    }

    /// `nil` for the statuses that are not open, which never reach here.
    private static func rowState(for status: RentalItemStatus) -> RentalSummarySnapshot.Row.State? {
        switch status {
        case .draft: .draft
        case .active: .accruing
        case .contactVendor: .contactVendor
        case .confirmationRecorded: .confirmationRecorded
        case .awaitingPickup: .awaitingPickup
        case .pickedUp: .pickedUp
        case .awaitingInvoice: .awaitingInvoice
        case .invoiceReview: .invoiceReview
        case .needsFollowUp: .needsFollowUp
        case .resolved, .archived: nil
        }
    }

    /// Trimmed, truncated, and never empty. A blank row in a widget looks like a rendering bug;
    /// a rental with no name yet is honestly described as untitled.
    private static func displayMachine(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled rental" }
        guard trimmed.count > RentalSummarySnapshot.machineNameLimit else { return trimmed }
        return String(trimmed.prefix(RentalSummarySnapshot.machineNameLimit - 1)) + "\u{2026}"
    }
}
