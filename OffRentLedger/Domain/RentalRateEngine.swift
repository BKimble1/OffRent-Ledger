import Foundation

/// One billing boundary: the instant the meter of *money* ticks over.
struct ProjectedRollover: Sendable, Equatable {
    var date: Date
    var periodNumber: Int
    var expectedIncrement: Decimal?
    /// True when this boundary came from the user rather than from the app's projection.
    var isUserConfirmed: Bool
}

/// The result of estimating what a rental has cost so far.
///
/// Every field the UI could draw is here, including the reasons the number might be wrong, so no
/// view has to re-derive anything or decide on its own what caveat to show.
struct RunningEstimate: Sendable, Equatable {
    var asOf: Date
    var deliveryDate: Date

    /// Whole calendar days between delivery and `asOf`. Zero on the delivery day itself.
    var daysOnRent: Int

    /// Billing periods the vendor is likely to have started, including the one in progress.
    var periodsStarted: Int

    var basis: BillingBasis
    var amountPerPeriod: Decimal

    /// `amountPerPeriod × periodsStarted`, rounded once. Always an *estimate*.
    var estimatedTotal: Decimal

    var nextRolloverDate: Date?
    var expectedNextIncrement: Decimal?

    /// False when something stopped the engine producing a figure. `estimatedTotal` is zero and
    /// must not be drawn as money when this is false — `EstimateLabel` refuses to.
    var isComplete: Bool

    /// Everything worth telling the user, blocking or not.
    var issues: [RateValidationIssue]

    /// True once the equipment stopped accruing, so the UI can say "final estimate" rather than
    /// implying the figure is still moving.
    var hasStoppedAccruing: Bool

    var blockingIssue: RateValidationIssue? { issues.first(where: \.blocksEstimate) }

    static func unavailable(
        asOf: Date,
        deliveryDate: Date,
        basis: BillingBasis,
        issues: [RateValidationIssue]
    ) -> RunningEstimate {
        RunningEstimate(
            asOf: asOf,
            deliveryDate: deliveryDate,
            daysOnRent: 0,
            periodsStarted: 0,
            basis: basis,
            amountPerPeriod: .zero,
            estimatedTotal: .zero,
            nextRolloverDate: nil,
            expectedNextIncrement: nil,
            isComplete: false,
            issues: issues,
            hasStoppedAccruing: false
        )
    }
}

/// Estimates what a rental is costing, and when the next rate change lands.
///
/// The engine is intentionally unclever. It does not choose the cheapest combination of daily,
/// weekly and four-week rates, it does not interpret contract prose, and it does not compute
/// overtime or excess meter hours. Every one of those requires knowing a vendor's terms better
/// than a scanned page can convey, and being confidently wrong about a number the user is about
/// to put in front of their rental yard is worse than showing nothing.
enum RentalRateEngine {

    // MARK: - Estimating

    static func estimate(
        terms: RentalTerms,
        asOf now: Date,
        calendar: Calendar
    ) -> RunningEstimate {

        // Once the equipment is done, the figure freezes. Otherwise a resolved rental from March
        // would keep climbing in the history list forever.
        let effectiveNow = min(terms.accrualStoppedAt ?? now, now)
        let hasStopped = terms.accrualStoppedAt != nil

        var issues = terms.rateCard.issues()

        guard let amountPerPeriod = terms.rateCard.amount(for: terms.billingBasis) else {
            issues.append(.missingRateForBasis(terms.billingBasis))
            return .unavailable(
                asOf: now, deliveryDate: terms.deliveryDate, basis: terms.billingBasis,
                issues: issues
            )
        }

        if amountPerPeriod < .zero {
            return .unavailable(
                asOf: now, deliveryDate: terms.deliveryDate, basis: terms.billingBasis,
                issues: issues
            )
        }

        if let rollover = terms.nextRolloverDate, rollover < terms.deliveryDate {
            issues.append(.rolloverBeforeDelivery)
        }
        if terms.rolloverMode == .manual {
            if terms.nextRolloverDate == nil { issues.append(.missingManualRollover) }
            if terms.expectedNextIncrement == nil { issues.append(.missingExpectedIncrement) }
        }

        let daysOnRent = calendar.wholeDays(from: terms.deliveryDate, to: effectiveNow)

        // Delivery is in the future: nothing is running yet, and saying "$0 estimated" is the
        // truthful answer rather than a missing one.
        guard daysOnRent >= 0 else {
            return RunningEstimate(
                asOf: now,
                deliveryDate: terms.deliveryDate,
                daysOnRent: 0,
                periodsStarted: 0,
                basis: terms.billingBasis,
                amountPerPeriod: MoneyMath.rounded(amountPerPeriod),
                estimatedTotal: .zero,
                nextRolloverDate: nextRollover(terms: terms, asOf: effectiveNow, calendar: calendar)?.date,
                expectedNextIncrement: expectedIncrement(terms: terms),
                isComplete: true,
                issues: issues,
                hasStoppedAccruing: hasStopped
            )
        }

        let periodsStarted = periodsStarted(daysOnRent: daysOnRent, basis: terms.billingBasis)
        let total = accruedTotal(
            terms: terms,
            periodsStarted: periodsStarted,
            amountPerPeriod: amountPerPeriod,
            asOf: effectiveNow,
            calendar: calendar
        )

        return RunningEstimate(
            asOf: now,
            deliveryDate: terms.deliveryDate,
            daysOnRent: daysOnRent,
            periodsStarted: periodsStarted,
            basis: terms.billingBasis,
            amountPerPeriod: MoneyMath.rounded(amountPerPeriod),
            estimatedTotal: total,
            nextRolloverDate: nextRollover(terms: terms, asOf: effectiveNow, calendar: calendar)?.date,
            expectedNextIncrement: expectedIncrement(terms: terms),
            isComplete: true,
            issues: issues,
            hasStoppedAccruing: hasStopped
        )
    }

    /// What the periods started so far have accrued, honouring a rate change the user confirmed.
    ///
    /// The old arithmetic was `amountPerPeriod × periodsStarted`, which ignores
    /// `expectedNextIncrement` entirely — so a contractor who did exactly what the form asks,
    /// and recorded that their yard rolls onto a different rate on the 11th, watched the
    /// estimate go on adding the old rate afterwards. Manual rollover is the *default* mode and
    /// §6 names calendar-month billing as its reason for existing, which is precisely the case
    /// where the two amounts differ. The number the whole app is built around was wrong for it.
    ///
    /// The rule is one sentence: periods that start before the confirmed rollover accrue the
    /// rate card's amount, and periods from the rollover onward accrue the amount the user said
    /// the next period would add.
    ///
    /// Note what this is *not*. It does not extrapolate a second, third or fourth rate change —
    /// the user confirmed one boundary and one amount, and inventing a schedule from that is
    /// simple-schedule mode wearing a disguise (`projectedRollovers` says the same thing). And
    /// when the two amounts are equal — which is every rental on a simple schedule, because
    /// `expectedIncrement` returns the rate card's own figure there — this is arithmetically
    /// identical to the multiplication it replaces. It changes only the case that was wrong.
    static func accruedTotal(
        terms: RentalTerms,
        periodsStarted: Int,
        amountPerPeriod: Decimal,
        asOf now: Date,
        calendar: Calendar
    ) -> Decimal {
        guard periodsStarted > 0 else { return .zero }

        // Only a boundary the user confirmed changes the rate. A projected one carries the rate
        // card's own amount, so it could not change anything even if it were used.
        guard terms.rolloverMode == .manual || terms.manualRolloverOverride,
              let rolloverDate = terms.nextRolloverDate,
              let newAmount = terms.expectedNextIncrement,
              newAmount != amountPerPeriod,
              rolloverDate <= now
        else {
            return MoneyMath.rounded(MoneyMath.multiply(amountPerPeriod, by: periodsStarted))
        }

        // The period the rollover falls in is the first one billed at the new rate.
        let firstNewPeriod = periodNumber(for: rolloverDate, terms: terms, calendar: calendar)
        let atOldRate = max(0, min(periodsStarted, firstNewPeriod - 1))
        let atNewRate = periodsStarted - atOldRate

        // Each half is rounded once, then added — the same discipline as everywhere else in this
        // engine, so a segmented total cannot drift from an unsegmented one by a rounding step.
        let old = MoneyMath.rounded(MoneyMath.multiply(amountPerPeriod, by: atOldRate))
        let new = MoneyMath.rounded(MoneyMath.multiply(newAmount, by: atNewRate))
        return MoneyMath.rounded(old + new)
    }

    /// Whether a rate change the user confirmed actually lands on or before `asOf`.
    ///
    /// The same five conditions `accruedTotal` guards on, exposed so a caller can say *why* a
    /// figure is what it is without re-deriving the rule and drifting from it.
    static func rateChangeApplies(terms: RentalTerms, asOf: Date) -> Bool {
        guard terms.rolloverMode == .manual || terms.manualRolloverOverride,
              let rolloverDate = terms.nextRolloverDate,
              let newAmount = terms.expectedNextIncrement,
              newAmount != terms.rateCard.amount(for: terms.billingBasis),
              rolloverDate <= asOf
        else { return false }
        return true
    }

    /// Billing periods started, counting the one in progress.
    ///
    /// A machine delivered this morning and still on site is on its first day, not its zeroth —
    /// every yard bills a minimum of one period. So day 0 is period 1, and a weekly rental crosses
    /// into period 2 on day 7, not day 8.
    static func periodsStarted(daysOnRent: Int, basis: BillingBasis) -> Int {
        guard daysOnRent >= 0 else { return 0 }
        return (daysOnRent / basis.dayCount) + 1
    }

    // MARK: - Rollovers

    /// The next rate change after `now`, or nil when the app has no honest basis for one.
    static func nextRollover(
        terms: RentalTerms,
        asOf now: Date,
        calendar: Calendar
    ) -> ProjectedRollover? {

        // The user's confirmed date always wins, in both modes. `manualRolloverOverride` exists
        // so that a user on a simple schedule can pin one odd boundary — a holiday shutdown, a
        // yard that bills Fridays — without abandoning the schedule for the rest of the rental.
        if terms.rolloverMode == .manual || terms.manualRolloverOverride {
            guard let date = terms.nextRolloverDate else { return nil }
            return ProjectedRollover(
                date: date,
                periodNumber: periodNumber(for: date, terms: terms, calendar: calendar),
                expectedIncrement: terms.expectedNextIncrement,
                isUserConfirmed: true
            )
        }

        let daysOnRent = max(0, calendar.wholeDays(from: terms.deliveryDate, to: now))
        let periods = periodsStarted(daysOnRent: daysOnRent, basis: terms.billingBasis)
        let offsetDays = periods * terms.billingBasis.dayCount

        // Preserving the time of day is what makes this correct across a daylight-saving change:
        // a boundary the vendor calls "7am Tuesday" stays at 7am, rather than drifting to 6am or
        // 8am after the clocks move.
        let date = calendar.addingDaysPreservingTimeOfDay(offsetDays, to: terms.deliveryDate)

        return ProjectedRollover(
            date: date,
            periodNumber: periods + 1,
            expectedIncrement: terms.rateCard.amount(for: terms.billingBasis),
            isUserConfirmed: false
        )
    }

    /// Boundaries from `now` up to `end`, for the rollover reminder planner and the detail view.
    ///
    /// In manual mode this returns at most the one boundary the user confirmed, plus one more if
    /// they also gave a subsequent interval. The app will not extrapolate a manual schedule
    /// indefinitely — that would be simple-schedule mode wearing a disguise.
    static func projectedRollovers(
        terms: RentalTerms,
        asOf now: Date,
        through end: Date,
        calendar: Calendar,
        limit: Int = 24
    ) -> [ProjectedRollover] {
        guard limit > 0, end >= now else { return [] }
        guard var current = nextRollover(terms: terms, asOf: now, calendar: calendar) else {
            return []
        }

        var result: [ProjectedRollover] = []

        if terms.rolloverMode == .manual || terms.manualRolloverOverride {
            if current.date <= end { result.append(current) }
            if let interval = terms.subsequentIntervalDays, interval > 0 {
                let following = calendar.addingDaysPreservingTimeOfDay(interval, to: current.date)
                if following <= end {
                    result.append(
                        ProjectedRollover(
                            date: following,
                            periodNumber: current.periodNumber + 1,
                            expectedIncrement: terms.expectedNextIncrement,
                            isUserConfirmed: true
                        )
                    )
                }
            }
            return result
        }

        while current.date <= end && result.count < limit {
            result.append(current)
            let next = calendar.addingDaysPreservingTimeOfDay(
                terms.billingBasis.dayCount, to: current.date
            )
            // Defensive: a pathological calendar that fails to advance would spin here forever.
            guard next > current.date else { break }
            current = ProjectedRollover(
                date: next,
                periodNumber: current.periodNumber + 1,
                expectedIncrement: current.expectedIncrement,
                isUserConfirmed: false
            )
        }
        return result
    }

    /// True when a rate change lands inside `window` of `now`. Drives the Today "upcoming rate
    /// changes" section, which the spec fixes at 48 hours.
    static func hasRolloverWithin(
        _ window: TimeInterval,
        terms: RentalTerms,
        asOf now: Date,
        calendar: Calendar
    ) -> Bool {
        guard let rollover = nextRollover(terms: terms, asOf: now, calendar: calendar) else {
            return false
        }
        let interval = rollover.date.timeIntervalSince(now)
        return interval >= 0 && interval <= window
    }

    // MARK: - Private

    private static func expectedIncrement(terms: RentalTerms) -> Decimal? {
        if terms.rolloverMode == .manual || terms.manualRolloverOverride {
            return terms.expectedNextIncrement
        }
        return terms.rateCard.amount(for: terms.billingBasis)
    }

    private static func periodNumber(
        for date: Date, terms: RentalTerms, calendar: Calendar
    ) -> Int {
        let days = max(0, calendar.wholeDays(from: terms.deliveryDate, to: date))
        return periodsStarted(daysOnRent: days, basis: terms.billingBasis)
    }
}
