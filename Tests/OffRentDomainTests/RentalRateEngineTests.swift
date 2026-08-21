import Foundation
import XCTest
@testable import OffRentDomain

/// The money tests. If any of these is wrong, the app's core claim is wrong.
final class RentalRateEngineTests: XCTestCase {

    // MARK: - Period counting

    func testDeliveryDayIsPeriodOne() {
        // Every rental yard bills a minimum of one period. A machine dropped this morning is on
        // day 1, not day 0.
        XCTAssertEqual(RentalRateEngine.periodsStarted(daysOnRent: 0, basis: .daily), 1)
        XCTAssertEqual(RentalRateEngine.periodsStarted(daysOnRent: 0, basis: .weekly), 1)
        XCTAssertEqual(RentalRateEngine.periodsStarted(daysOnRent: 0, basis: .fourWeek), 1)
    }

    func testDailyPeriodsAdvanceEveryDay() {
        XCTAssertEqual(RentalRateEngine.periodsStarted(daysOnRent: 1, basis: .daily), 2)
        XCTAssertEqual(RentalRateEngine.periodsStarted(daysOnRent: 6, basis: .daily), 7)
        XCTAssertEqual(RentalRateEngine.periodsStarted(daysOnRent: 30, basis: .daily), 31)
    }

    func testWeeklyPeriodTurnsOverOnDaySeven() {
        XCTAssertEqual(RentalRateEngine.periodsStarted(daysOnRent: 6, basis: .weekly), 1)
        XCTAssertEqual(RentalRateEngine.periodsStarted(daysOnRent: 7, basis: .weekly), 2)
        XCTAssertEqual(RentalRateEngine.periodsStarted(daysOnRent: 13, basis: .weekly), 2)
        XCTAssertEqual(RentalRateEngine.periodsStarted(daysOnRent: 14, basis: .weekly), 3)
    }

    func testFourWeekPeriodTurnsOverOnDayTwentyEight() {
        XCTAssertEqual(RentalRateEngine.periodsStarted(daysOnRent: 27, basis: .fourWeek), 1)
        XCTAssertEqual(RentalRateEngine.periodsStarted(daysOnRent: 28, basis: .fourWeek), 2)
        XCTAssertEqual(RentalRateEngine.periodsStarted(daysOnRent: 55, basis: .fourWeek), 2)
        XCTAssertEqual(RentalRateEngine.periodsStarted(daysOnRent: 56, basis: .fourWeek), 3)
    }

    func testNegativeDaysProduceNoPeriods() {
        XCTAssertEqual(RentalRateEngine.periodsStarted(daysOnRent: -1, basis: .daily), 0)
    }

    // MARK: - Estimating

    func testDailyEstimateOnDeliveryDay() {
        let delivered = date(2026, 5, 4, 7)
        let terms = RentalTerms.skidSteer(delivered: delivered)
        let estimate = RentalRateEngine.estimate(
            terms: terms, asOf: date(2026, 5, 4, 16), calendar: calendar()
        )
        XCTAssertTrue(estimate.isComplete)
        XCTAssertEqual(estimate.daysOnRent, 0)
        XCTAssertEqual(estimate.periodsStarted, 1)
        XCTAssertEqual(estimate.estimatedTotal, money("285.00"))
    }

    func testDailyEstimateAfterFiveDays() {
        let delivered = date(2026, 5, 4, 7)
        let terms = RentalTerms.skidSteer(delivered: delivered)
        let estimate = RentalRateEngine.estimate(
            terms: terms, asOf: date(2026, 5, 9, 7), calendar: calendar()
        )
        XCTAssertEqual(estimate.daysOnRent, 5)
        XCTAssertEqual(estimate.periodsStarted, 6)
        XCTAssertEqual(estimate.estimatedTotal, money("1710.00"))  // 285 × 6
    }

    func testEstimateIsUnavailableWhenTheBasisRateIsMissing() {
        let terms = RentalTerms(
            deliveryDate: date(2026, 5, 4),
            rateCard: RateCard(daily: money("285.00")),   // no weekly rate
            billingBasis: .weekly
        )
        let estimate = RentalRateEngine.estimate(
            terms: terms, asOf: date(2026, 5, 20), calendar: calendar()
        )
        XCTAssertFalse(estimate.isComplete)
        XCTAssertEqual(estimate.estimatedTotal, .zero)
        XCTAssertEqual(estimate.blockingIssue, .missingRateForBasis(.weekly))
    }

    func testNegativeRateBlocksTheEstimateRatherThanProducingANegativeOne() {
        let terms = RentalTerms(
            deliveryDate: date(2026, 5, 4),
            rateCard: RateCard(daily: money("-285.00")),
            billingBasis: .daily
        )
        let estimate = RentalRateEngine.estimate(
            terms: terms, asOf: date(2026, 5, 10), calendar: calendar()
        )
        XCTAssertFalse(estimate.isComplete)
        XCTAssertEqual(estimate.estimatedTotal, .zero)
        XCTAssertTrue(estimate.issues.contains(.negativeRate(.daily)))
    }

    func testZeroRateStillEstimatesButIsFlagged() {
        // A $0.00 estimate that looks like good news is worse than a warning.
        let terms = RentalTerms(
            deliveryDate: date(2026, 5, 4),
            rateCard: RateCard(daily: .zero),
            billingBasis: .daily
        )
        let estimate = RentalRateEngine.estimate(
            terms: terms, asOf: date(2026, 5, 10), calendar: calendar()
        )
        XCTAssertTrue(estimate.isComplete)
        XCTAssertEqual(estimate.estimatedTotal, .zero)
        XCTAssertTrue(estimate.issues.contains(.zeroRate(.daily)))
        XCTAssertNil(estimate.blockingIssue)
    }

    func testDeliveryInTheFutureEstimatesZeroRatherThanFailing() {
        let terms = RentalTerms.skidSteer(delivered: date(2026, 6, 1, 7))
        let estimate = RentalRateEngine.estimate(
            terms: terms, asOf: date(2026, 5, 20, 7), calendar: calendar()
        )
        XCTAssertTrue(estimate.isComplete)
        XCTAssertEqual(estimate.periodsStarted, 0)
        XCTAssertEqual(estimate.estimatedTotal, .zero)
    }

    func testAccrualStopsWhenTheItemIsDone() {
        var terms = RentalTerms.skidSteer(delivered: date(2026, 5, 4, 7))
        terms.accrualStoppedAt = date(2026, 5, 9, 7)

        let atStop = RentalRateEngine.estimate(
            terms: terms, asOf: date(2026, 5, 9, 7), calendar: calendar()
        )
        let muchLater = RentalRateEngine.estimate(
            terms: terms, asOf: date(2026, 8, 30, 7), calendar: calendar()
        )
        XCTAssertEqual(atStop.estimatedTotal, muchLater.estimatedTotal)
        XCTAssertTrue(muchLater.hasStoppedAccruing)
    }

    // MARK: - Daylight saving

    func testSpringForwardDayStillCountsAsAWholeDay() {
        // US DST began 2026-03-08. The 8th is 23 hours long, so dividing elapsed seconds by
        // 86 400 loses a day and under-bills the customer by one period.
        let delivered = date(2026, 3, 6, 7)
        let now = date(2026, 3, 9, 7)

        let elapsedSeconds = now.timeIntervalSince(delivered)
        XCTAssertEqual(elapsedSeconds, 3 * 86_400 - 3_600, "fixture should straddle spring-forward")
        XCTAssertEqual(Int(elapsedSeconds) / 86_400, 2, "naive arithmetic would say 2 days")

        let terms = RentalTerms.skidSteer(delivered: delivered)
        let estimate = RentalRateEngine.estimate(terms: terms, asOf: now, calendar: calendar())
        XCTAssertEqual(estimate.daysOnRent, 3, "calendar arithmetic must say 3 days")
        XCTAssertEqual(estimate.estimatedTotal, money("1140.00"))  // 285 × 4 periods
    }

    func testFallBackDayStillCountsAsAWholeDay() {
        // US DST ended 2026-11-01. That day is 25 hours long.
        let delivered = date(2026, 10, 30, 7)
        let now = date(2026, 11, 2, 7)

        let elapsedSeconds = now.timeIntervalSince(delivered)
        XCTAssertEqual(elapsedSeconds, 3 * 86_400 + 3_600, "fixture should straddle fall-back")

        let terms = RentalTerms.skidSteer(delivered: delivered)
        let estimate = RentalRateEngine.estimate(terms: terms, asOf: now, calendar: calendar())
        XCTAssertEqual(estimate.daysOnRent, 3)
        XCTAssertEqual(estimate.estimatedTotal, money("1140.00"))
    }

    func testRolloverPreservesTimeOfDayAcrossSpringForward() {
        let delivered = date(2026, 3, 6, 7)
        let terms = RentalTerms.skidSteer(delivered: delivered, basis: .weekly, mode: .simpleSchedule)
        let rollover = RentalRateEngine.nextRollover(
            terms: terms, asOf: date(2026, 3, 7, 7), calendar: calendar()
        )
        let components = calendar().dateComponents([.year, .month, .day, .hour], from: rollover!.date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 13)
        XCTAssertEqual(components.hour, 7, "a 7am boundary must stay 7am after the clocks move")
    }

    func testEstimateIsStableAcrossTimeZonesForTheSameCalendarDays() {
        // Same wall-clock delivery and same wall-clock "now" in a DST zone and a non-DST zone.
        let chicago = RentalRateEngine.estimate(
            terms: .skidSteer(delivered: date(2026, 5, 4, 7, 0, TZ.chicago)),
            asOf: date(2026, 5, 9, 7, 0, TZ.chicago),
            calendar: calendar(TZ.chicago)
        )
        let honolulu = RentalRateEngine.estimate(
            terms: .skidSteer(delivered: date(2026, 5, 4, 7, 0, TZ.honolulu)),
            asOf: date(2026, 5, 9, 7, 0, TZ.honolulu),
            calendar: calendar(TZ.honolulu)
        )
        XCTAssertEqual(chicago.estimatedTotal, honolulu.estimatedTotal)
        XCTAssertEqual(chicago.daysOnRent, honolulu.daysOnRent)
    }

    // MARK: - Rollover behaviour

    func testManualModeUsesOnlyTheUserConfirmedDate() {
        let terms = RentalTerms.skidSteer(
            delivered: date(2026, 5, 4, 7),
            mode: .manual,
            nextRollover: date(2026, 5, 18, 7),
            expectedIncrement: "985.00"
        )
        let rollover = RentalRateEngine.nextRollover(
            terms: terms, asOf: date(2026, 5, 6), calendar: calendar()
        )
        XCTAssertEqual(rollover?.date, date(2026, 5, 18, 7))
        XCTAssertEqual(rollover?.expectedIncrement, money("985.00"))
        XCTAssertTrue(rollover?.isUserConfirmed ?? false)
    }

    func testManualModeInventsNothingWhenTheUserHasNotConfirmedADate() {
        let terms = RentalTerms.skidSteer(delivered: date(2026, 5, 4, 7), mode: .manual)
        XCTAssertNil(
            RentalRateEngine.nextRollover(terms: terms, asOf: date(2026, 5, 6), calendar: calendar())
        )
        let estimate = RentalRateEngine.estimate(
            terms: terms, asOf: date(2026, 5, 6), calendar: calendar()
        )
        XCTAssertTrue(estimate.issues.contains(.missingManualRollover))
        XCTAssertTrue(estimate.isComplete, "a missing rollover must not block the running estimate")
    }

    func testSimpleScheduleProjectsFromDelivery() {
        let terms = RentalTerms.skidSteer(
            delivered: date(2026, 5, 4, 7), basis: .weekly, mode: .simpleSchedule
        )
        let first = RentalRateEngine.nextRollover(
            terms: terms, asOf: date(2026, 5, 4, 8), calendar: calendar()
        )
        XCTAssertEqual(first?.date, date(2026, 5, 11, 7))
        XCTAssertFalse(first?.isUserConfirmed ?? true)

        let later = RentalRateEngine.nextRollover(
            terms: terms, asOf: date(2026, 5, 12, 8), calendar: calendar()
        )
        XCTAssertEqual(later?.date, date(2026, 5, 18, 7))
    }

    func testManualOverrideWinsInsideSimpleScheduleMode() {
        var terms = RentalTerms.skidSteer(
            delivered: date(2026, 5, 4, 7), basis: .weekly, mode: .simpleSchedule
        )
        terms.manualRolloverOverride = true
        terms.nextRolloverDate = date(2026, 5, 15, 7)
        terms.expectedNextIncrement = money("500.00")

        let rollover = RentalRateEngine.nextRollover(
            terms: terms, asOf: date(2026, 5, 5), calendar: calendar()
        )
        XCTAssertEqual(rollover?.date, date(2026, 5, 15, 7))
        XCTAssertEqual(rollover?.expectedIncrement, money("500.00"))
        XCTAssertTrue(rollover?.isUserConfirmed ?? false)
    }

    func testManualModeDoesNotExtrapolateBeyondWhatTheUserGave() {
        let terms = RentalTerms.skidSteer(
            delivered: date(2026, 5, 4, 7),
            mode: .manual,
            nextRollover: date(2026, 5, 11, 7),
            expectedIncrement: "985.00"
        )
        let projected = RentalRateEngine.projectedRollovers(
            terms: terms,
            asOf: date(2026, 5, 5),
            through: date(2026, 12, 31),
            calendar: calendar()
        )
        XCTAssertEqual(projected.count, 1, "manual mode must not become a schedule by itself")
    }

    func testManualModeAddsExactlyOneMoreWhenASubsequentIntervalIsGiven() {
        var terms = RentalTerms.skidSteer(
            delivered: date(2026, 5, 4, 7),
            mode: .manual,
            nextRollover: date(2026, 5, 11, 7),
            expectedIncrement: "985.00"
        )
        terms.subsequentIntervalDays = 7
        let projected = RentalRateEngine.projectedRollovers(
            terms: terms, asOf: date(2026, 5, 5), through: date(2026, 12, 31), calendar: calendar()
        )
        XCTAssertEqual(projected.count, 2)
        XCTAssertEqual(projected[1].date, date(2026, 5, 18, 7))
    }

    func testScheduledProjectionIsBoundedByTheLimit() {
        let terms = RentalTerms.skidSteer(
            delivered: date(2026, 1, 1, 7), basis: .daily, mode: .simpleSchedule
        )
        let projected = RentalRateEngine.projectedRollovers(
            terms: terms,
            asOf: date(2026, 1, 1, 8),
            through: date(2030, 1, 1),
            calendar: calendar(),
            limit: 10
        )
        XCTAssertEqual(projected.count, 10)
    }

    func testFortyEightHourWindow() {
        let terms = RentalTerms.skidSteer(
            delivered: date(2026, 5, 4, 7),
            mode: .manual,
            nextRollover: date(2026, 5, 11, 7),
            expectedIncrement: "985.00"
        )
        let window: TimeInterval = 48 * 60 * 60
        XCTAssertTrue(
            RentalRateEngine.hasRolloverWithin(
                window, terms: terms, asOf: date(2026, 5, 10, 7), calendar: calendar()
            )
        )
        XCTAssertFalse(
            RentalRateEngine.hasRolloverWithin(
                window, terms: terms, asOf: date(2026, 5, 8, 7), calendar: calendar()
            )
        )
        XCTAssertFalse(
            RentalRateEngine.hasRolloverWithin(
                window, terms: terms, asOf: date(2026, 5, 12, 7), calendar: calendar()
            ),
            "a boundary already in the past is not upcoming"
        )
    }

    // MARK: - Rounding

    func testLongRentalDoesNotDriftAcrossFourHundredPeriods() {
        // The reason money is Decimal. 0.1 is not representable in binary floating point, and
        // this rental adds it 400 times.
        let terms = RentalTerms(
            deliveryDate: date(2026, 1, 1, 7),
            rateCard: RateCard(daily: money("0.10")),
            billingBasis: .daily
        )
        let estimate = RentalRateEngine.estimate(
            terms: terms, asOf: date(2027, 2, 4, 7), calendar: calendar()
        )
        XCTAssertEqual(estimate.periodsStarted, 400)
        XCTAssertEqual(estimate.estimatedTotal, money("40.00"))
    }

    func testFractionalCentRateRoundsOnceAtTheEnd() {
        let terms = RentalTerms(
            deliveryDate: date(2026, 1, 1, 7),
            rateCard: RateCard(daily: money("33.335")),
            billingBasis: .daily
        )
        let estimate = RentalRateEngine.estimate(
            terms: terms, asOf: date(2026, 1, 3, 7), calendar: calendar()
        )
        // 33.335 × 3 = 100.005, rounded once → 100.00 under banker's rounding.
        XCTAssertEqual(estimate.periodsStarted, 3)
        XCTAssertEqual(estimate.estimatedTotal, money("100.00"))
    }
}
