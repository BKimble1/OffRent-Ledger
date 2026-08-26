import Foundation
import XCTest
@testable import OffRentDomain

/// The figures the App Store gallery claims, asserted against the app's own engines.
///
/// Six screenshots have to agree with each other and with the words printed beside them. The
/// running total on the hero has to be the running total in the widget; the expected, invoiced
/// and difference figures on the closing frame have to be the ones the invoice review screen
/// computes; the counts on the widget have to be the counts on Today. None of that survives an
/// edit to the fixture unless something checks it, and a screenshot is the worst possible place
/// to discover it did not — by then the file has been uploaded.
///
/// So every number the gallery shows is derived here, by `RentalRateEngine`, `SnapshotBuilder`
/// and `InvoiceComparisonEngine`, and compared against `AppStoreCaptureFixture.expectations`,
/// which is what the placement guide and `marketing/screenshots/README.md` quote.
///
/// These run under `swift test`, with no simulator, in the first minute of CI.
final class AppStoreCaptureFixtureTests: XCTestCase {

    private typealias Fixture = AppStoreCaptureFixture

    // MARK: - The instant

    func testTheFixedClockIsTheOneTheCaptureScriptPasses() {
        // 2026-05-09T15:00:00Z is 10:00 in America/Chicago, which is the time of day every
        // screenshot's status bar and every "Calculated" row will read.
        let components = Fixture.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: Fixture.now
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 5)
        XCTAssertEqual(components.day, 9)
        XCTAssertEqual(components.hour, 10)
        XCTAssertEqual(components.minute, 0)
    }

    func testTheFixtureIsNotADescriptionOfToday() {
        // The whole reason this fixture exists. The walkthrough fixture's estimate climbs by its
        // day rate every twenty-four hours because it is measured against the wall clock; this
        // one is measured against a frozen instant, so the figure a capture produces in 2030 is
        // the figure it produces now.
        let later = Fixture.now.addingTimeInterval(365 * 24 * 60 * 60)
        XCTAssertEqual(
            runningTotal(asOf: Fixture.now),
            Fixture.expectations.estimatedRentRunning
        )
        XCTAssertNotEqual(
            runningTotal(asOf: later),
            Fixture.expectations.estimatedRentRunning,
            "if a year of wall clock does not move the figure, the test is not measuring anything"
        )
    }

    // MARK: - Identity

    func testEveryRecordIsDistinctAndFictional() {
        let machines = Fixture.machines
        XCTAssertEqual(machines.count, 4)
        XCTAssertEqual(Set(machines.map(\.id)).count, 4, "two machines share an identifier")
        XCTAssertEqual(
            Set(machines.map(\.agreementID)).count, 4,
            """
            one agreement per machine, or RootView counts the one invoice as awaiting review for \
            every item on the agreement it hangs off — and the widget says "2 to review" beside \
            an app that lists one
            """
        )
        XCTAssertEqual(
            Set(machines.map(\.vendorEquipmentIdentifier)),
            ["EX-118", "LT-044", "BL-204", "CTL-247"]
        )

        for company in Fixture.companies {
            XCTAssertTrue(
                company.email.hasSuffix(".invalid"),
                "\(company.name) has a deliverable email address in a screenshot fixture"
            )
            XCTAssertTrue(
                company.phone.contains("5550"),
                "\(company.name)'s number is outside the 555-01xx range reserved for fiction"
            )
        }
    }

    func testTheStatusesAreTheOnesTheGalleryNeeds() {
        let byStatus = Dictionary(grouping: Fixture.machines, by: \.status).mapValues(\.count)
        XCTAssertEqual(byStatus[.active], 2, "two rentals still running, for the hero's figure")
        XCTAssertEqual(byStatus[.awaitingPickup], 1, "one off rent, for the proof and map frames")
        XCTAssertEqual(byStatus[.invoiceReview], 1, "one invoice in, for the closing frame")
    }

    func testEveryMachineHasSomewhereToBeDrawn() {
        // A rental with no jobsite coordinate is never placed on the map — correctly, the app
        // refuses to guess — and the map frame would then be a map of nothing.
        XCTAssertEqual(Fixture.jobsites.count, 3)
        for machine in Fixture.machines {
            XCTAssertTrue(
                Fixture.jobsites.contains(where: { $0.id == machine.jobsite.id }),
                "\(machine.vendorEquipmentIdentifier) is at a jobsite the fixture does not create"
            )
            XCTAssertNotEqual(machine.jobsite.latitude, 0)
            XCTAssertNotEqual(machine.jobsite.longitude, 0)
        }
    }

    func testTheRentalsListHasOneDeterministicOrder() {
        // Four equal `modifiedAt` values is four rows in whatever order SwiftData feels like.
        let stamps = Fixture.machines.map(\.lastTouchedAt)
        XCTAssertEqual(Set(stamps).count, stamps.count, "two machines share a modifiedAt")
    }

    // MARK: - The hero's figure, and the widget's

    func testTheRunningTotalIsBelievableAndExact() {
        // Mini excavator: 5 periods × $425 = $2,125. Light tower: 8 × $95 = $760.
        XCTAssertEqual(runningTotal(asOf: Fixture.now), Fixture.amount("2885.00"))
        XCTAssertLessThan(
            runningTotal(asOf: Fixture.now), Fixture.amount("10000.00"),
            "a screenshot showing five figures of running rent is not a rental, it is a lawsuit"
        )
    }

    func testEveryAccruingEstimateIsCompleteSoNothingIsExcludedFromTheTotal() {
        // Today draws "N rentals have no confirmed rate and are not included" above the figure
        // when an estimate is incomplete. On the hero screenshot that reads as a defect.
        for machine in Fixture.machines {
            let estimate = RentalRateEngine.estimate(
                terms: machine.terms, asOf: Fixture.now, calendar: Fixture.calendar
            )
            XCTAssertTrue(
                estimate.isComplete,
                "\(machine.vendorEquipmentIdentifier)'s estimate is incomplete"
            )
            XCTAssertTrue(
                estimate.issues.isEmpty,
                """
                \(machine.vendorEquipmentIdentifier) carries \(estimate.issues.count) rate \
                warning(s), which the detail screen draws as inline alerts: \
                \(estimate.issues.map(\.message))
                """
            )
        }
    }

    func testAConfirmedMachinesEstimateHasStoppedMoving() {
        for machine in Fixture.machines where machine.confirmation != nil {
            let estimate = RentalRateEngine.estimate(
                terms: machine.terms, asOf: Fixture.now, calendar: Fixture.calendar
            )
            XCTAssertTrue(
                estimate.hasStoppedAccruing,
                "\(machine.vendorEquipmentIdentifier) was confirmed off rent and is still accruing"
            )
        }
    }

    func testTheWidgetSaysExactlyWhatTheAppSays() {
        let snapshot = Fixture.snapshot()
        let expected = Fixture.expectations
        XCTAssertEqual(snapshot.estimatedRentRunning, expected.estimatedRentRunning)
        XCTAssertEqual(snapshot.openItemCount, expected.openItemCount)
        XCTAssertEqual(snapshot.accruingItemCount, expected.accruingItemCount)
        XCTAssertEqual(snapshot.awaitingPickupCount, expected.awaitingPickupCount)
        XCTAssertEqual(snapshot.invoicesAwaitingReviewCount, expected.invoicesAwaitingReviewCount)
        XCTAssertEqual(snapshot.nextRateChangeDate, expected.nextRateChangeDate)
        XCTAssertFalse(snapshot.isEmpty)
    }

    func testTheNextRateChangeLandsInsideTodaysWindow() throws {
        // Today's "Upcoming rate changes" section only draws boundaries within 48 hours. The hero
        // screenshot is a good deal emptier without it.
        let next = try XCTUnwrap(Fixture.expectations.nextRateChangeDate)
        let interval = next.timeIntervalSince(Fixture.now)
        XCTAssertGreaterThanOrEqual(interval, 0)
        XCTAssertLessThanOrEqual(interval, 48 * 60 * 60)
    }

    // MARK: - The closing frame's three figures

    func testTheInvoiceDifferenceIsExactlyOneExtraDay() throws {
        let comparison = try XCTUnwrap(Fixture.invoiceComparison())
        let expected = Fixture.expectations
        let derived = try XCTUnwrap(comparison.expectedRentalSubtotal)

        XCTAssertEqual(derived, expected.invoiceExpected)                            // $2,280
        XCTAssertEqual(comparison.invoicedRentalSubtotal, expected.invoiceInvoiced)   // $2,565
        XCTAssertEqual(comparison.possibleVariance, expected.invoiceDifference)       // $285

        XCTAssertEqual(
            comparison.invoicedRentalSubtotal - derived,
            Fixture.trackLoader.dailyRate,
            "the difference has to be one day at the day rate, or the frame explains nothing"
        )
    }

    func testTheInvoiceTotalAgreesWithItsOwnLines() throws {
        // A total that differs from the sum of the lines raises a second finding, and the closing
        // frame would then carry five figures where its argument is three.
        let comparison = try XCTUnwrap(Fixture.invoiceComparison())
        XCTAssertEqual(comparison.invoiceTotal, comparison.lineSum)
        XCTAssertFalse(
            comparison.findings.contains { $0.type == .invoiceTotalDoesNotMatchLines }
        )
        XCTAssertTrue(
            comparison.reviewFlags.isEmpty,
            "a charge the app has no opinion about adds a checklist the screenshot has no room for"
        )
    }

    func testTheOverbilledDayIsExplained() throws {
        // Not just a number. The invoice is billed through one day after the confirmation the
        // user recorded, so the app can say *why* the two disagree.
        let comparison = try XCTUnwrap(Fixture.invoiceComparison())
        XCTAssertTrue(comparison.findings.contains { $0.type == .rentalSubtotalDiffers })
        XCTAssertTrue(comparison.findings.contains { $0.type == .billedBeyondConfirmationDate })
        XCTAssertFalse(
            comparison.isFullyExplained,
            "with an open finding, Accept is disabled and names its reason — which is the state "
            + "the screenshot is of"
        )
    }

    func testTheExpectedAmountIsTheMachinesOwnFinalEstimate() {
        // The detail screen shows the track loader's final estimate; the invoice review shows the
        // expected rental amount. They are the same $2,280, and a reader who checks will find
        // they match rather than finding two numbers for one rental.
        let estimate = RentalRateEngine.estimate(
            terms: Fixture.trackLoader.terms, asOf: Fixture.now, calendar: Fixture.calendar
        )
        XCTAssertEqual(estimate.estimatedTotal, Fixture.expectations.invoiceExpected)
    }

    // MARK: - Helpers

    private func runningTotal(asOf instant: Date) -> Decimal {
        var amounts: [Decimal] = []
        for machine in Fixture.machines where machine.status.accruesRent {
            let estimate = RentalRateEngine.estimate(
                terms: machine.terms, asOf: instant, calendar: Fixture.calendar
            )
            guard estimate.isComplete else { continue }
            amounts.append(estimate.estimatedTotal)
        }
        return MoneyMath.sum(amounts)
    }
}
