import XCTest
@testable import OffRentDomain

/// The invoice audit. §19 of the product spec is reproduced verbatim as
/// `FinancialWalkthroughTests` at the bottom of this file.
final class InvoiceComparisonTests: XCTestCase {

    private let delivered = date(2026, 5, 4, 7)
    private let confirmed = date(2026, 5, 11, 9)   // 7 whole days later → 8 daily periods
    private let pickedUp = date(2026, 5, 12, 14)

    private func input(
        invoice: InvoiceValue,
        confirmationDate: Date? = nil,
        pickupDate: Date? = nil,
        expectedOverride: Decimal? = nil,
        terms: RentalTerms? = nil
    ) -> InvoiceComparisonInput {
        InvoiceComparisonInput(
            terms: terms ?? .skidSteer(delivered: delivered),
            confirmationDate: confirmationDate,
            pickupDate: pickupDate,
            invoice: invoice,
            expectedRentalSubtotalOverride: expectedOverride,
            calendar: calendar(),
            now: date(2026, 5, 20, 9)
        )
    }

    // MARK: - Expectation

    func testExpectationRunsToTheConfirmationDateNotToPickup() {
        // This is the product's whole thesis: off-rent stops the clock, even though the machine
        // physically sat on the jobsite for another day.
        let comparison = InvoiceComparisonEngine.compare(
            input(
                invoice: InvoiceValue(receivedDate: date(2026, 5, 18)),
                confirmationDate: confirmed,
                pickupDate: pickedUp
            )
        )
        XCTAssertEqual(comparison.expectedBilledThroughDate, confirmed)
        XCTAssertEqual(comparison.expectedPeriods, 8)
        XCTAssertEqual(comparison.expectedRentalSubtotal, money("2280.00"))  // 285 × 8
    }

    func testExpectationFallsBackToPickupWhenNoConfirmationWasRecorded() {
        let comparison = InvoiceComparisonEngine.compare(
            input(invoice: InvoiceValue(receivedDate: date(2026, 5, 18)), pickupDate: pickedUp)
        )
        XCTAssertEqual(comparison.expectedBilledThroughDate, pickedUp)
        XCTAssertEqual(comparison.expectedPeriods, 9)
    }

    func testUserEnteredExpectationOverridesTheDerivedOne() {
        let comparison = InvoiceComparisonEngine.compare(
            input(
                invoice: InvoiceValue(receivedDate: date(2026, 5, 18)),
                confirmationDate: confirmed,
                expectedOverride: money("1999.99")
            )
        )
        XCTAssertEqual(comparison.expectedRentalSubtotal, money("1999.99"))
        XCTAssertEqual(comparison.expectationBasis, "You entered this expected rental amount.")
    }

    func testNoExpectationIsInventedWhenNoRateIsConfirmed() {
        let terms = RentalTerms(deliveryDate: delivered, rateCard: RateCard(), billingBasis: .daily)
        let comparison = InvoiceComparisonEngine.compare(
            input(
                invoice: InvoiceValue(receivedDate: date(2026, 5, 18), invoiceTotal: money("999.00")),
                confirmationDate: confirmed,
                terms: terms
            )
        )
        XCTAssertNil(comparison.expectedRentalSubtotal)
        XCTAssertTrue(comparison.expectationBasis.contains("cannot form an expected rental amount"))
        XCTAssertFalse(
            comparison.findings.contains { $0.type == .rentalSubtotalDiffers },
            "no expectation means no mismatch claim"
        )
    }

    // MARK: - Variance

    func testMatchingInvoiceHasZeroVariance() {
        let invoice = InvoiceValue(
            invoiceNumber: "INV-88213",
            receivedDate: date(2026, 5, 18),
            billedThroughDate: confirmed,
            lines: [
                InvoiceLineValue(category: .rentalSubtotal, amount: money("2280.00"),
                                 appearedInContract: true, reviewState: .accepted),
                InvoiceLineValue(category: .delivery, amount: money("150.00"),
                                 appearedInContract: true, reviewState: .accepted),
                InvoiceLineValue(category: .taxes, amount: money("200.48"), reviewState: .accepted),
            ],
            invoiceTotal: money("2630.48")
        )
        let comparison = InvoiceComparisonEngine.compare(
            input(invoice: invoice, confirmationDate: confirmed, pickupDate: pickedUp)
        )
        XCTAssertEqual(comparison.possibleVariance, .zero)
        XCTAssertTrue(comparison.findings.isEmpty)
        XCTAssertTrue(comparison.reviewFlags.isEmpty)
        XCTAssertTrue(comparison.isFullyExplained)
    }

    func testOneExtraRentalDayIsSurfacedAsAPossibleMismatch() {
        let invoice = InvoiceValue(
            receivedDate: date(2026, 5, 18),
            billedThroughDate: confirmed,
            lines: [
                InvoiceLineValue(category: .rentalSubtotal, amount: money("2565.00"),  // 9 days
                                 appearedInContract: true, reviewState: .accepted)
            ],
            invoiceTotal: money("2565.00")
        )
        let comparison = InvoiceComparisonEngine.compare(
            input(invoice: invoice, confirmationDate: confirmed)
        )
        XCTAssertEqual(comparison.possibleVariance, money("285.00"))
        XCTAssertEqual(comparison.findings.count, 1)
        XCTAssertEqual(comparison.findings[0].type, .rentalSubtotalDiffers)
        XCTAssertEqual(comparison.findings[0].expectedAmount, money("2280.00"))
        XCTAssertEqual(comparison.findings[0].invoicedAmount, money("2565.00"))
        XCTAssertEqual(comparison.findings[0].difference, money("285.00"))
        XCTAssertFalse(comparison.isFullyExplained)
    }

    func testUnderBillingIsAlsoSurfaced() {
        // The app is a ledger, not an advocate. A vendor undercharge is a mismatch too.
        let invoice = InvoiceValue(
            receivedDate: date(2026, 5, 18),
            lines: [InvoiceLineValue(category: .rentalSubtotal, amount: money("1995.00"),
                                     reviewState: .accepted)],
            invoiceTotal: money("1995.00")
        )
        let comparison = InvoiceComparisonEngine.compare(
            input(invoice: invoice, confirmationDate: confirmed)
        )
        XCTAssertEqual(comparison.possibleVariance, money("285.00"))
        XCTAssertTrue(comparison.findings[0].explanation.contains("less than"))
    }

    func testTotalNotMatchingLinesIsFlaggedAsALikelyEntryError() {
        let invoice = InvoiceValue(
            receivedDate: date(2026, 5, 18),
            lines: [
                InvoiceLineValue(category: .rentalSubtotal, amount: money("2280.00"),
                                 reviewState: .accepted),
                InvoiceLineValue(category: .delivery, amount: money("150.00"),
                                 reviewState: .accepted),
            ],
            invoiceTotal: money("2500.00")
        )
        let comparison = InvoiceComparisonEngine.compare(
            input(invoice: invoice, confirmationDate: confirmed)
        )
        let finding = comparison.findings.first { $0.type == .invoiceTotalDoesNotMatchLines }
        XCTAssertNotNil(finding)
        XCTAssertEqual(finding?.difference, money("70.00"))
        XCTAssertTrue(
            finding?.explanation.contains("entered twice") ?? false,
            "the app should suspect the user's typing before it suspects the vendor"
        )
    }

    func testBillingPastTheConfirmationDateIsFlaggedButIsNotVariance() {
        let invoice = InvoiceValue(
            receivedDate: date(2026, 5, 18),
            billedThroughDate: date(2026, 5, 14, 9),
            lines: [InvoiceLineValue(category: .rentalSubtotal, amount: money("2280.00"),
                                     reviewState: .accepted)],
            invoiceTotal: money("2280.00")
        )
        let comparison = InvoiceComparisonEngine.compare(
            input(invoice: invoice, confirmationDate: confirmed)
        )
        let finding = comparison.findings.first { $0.type == .billedBeyondConfirmationDate }
        XCTAssertNotNil(finding)
        XCTAssertEqual(comparison.possibleVariance, .zero, "a date flag is not a money claim")
    }

    // MARK: - Review flags

    func testUnreviewedNonDerivableChargesBecomeReviewFlagsNotMismatches() {
        let invoice = InvoiceValue(
            receivedDate: date(2026, 5, 18),
            lines: [
                InvoiceLineValue(category: .rentalSubtotal, amount: money("2280.00"),
                                 reviewState: .accepted),
                InvoiceLineValue(category: .damage, detail: "Cracked glass", amount: money("450.00")),
                InvoiceLineValue(category: .cleaning, amount: money("125.00")),
            ],
            invoiceTotal: money("2855.00")
        )
        let comparison = InvoiceComparisonEngine.compare(
            input(invoice: invoice, confirmationDate: confirmed)
        )
        XCTAssertEqual(comparison.reviewFlags.count, 2)
        XCTAssertEqual(comparison.possibleVariance, .zero)
        XCTAssertFalse(comparison.isFullyExplained)
        XCTAssertTrue(comparison.reviewFlags[0].prompt.hasPrefix("Review this charge"))
        XCTAssertTrue(
            comparison.reviewFlags[0].prompt.contains("not in the terms you entered")
        )
    }

    func testReviewingAChargeClearsItsFlag() {
        var line = InvoiceLineValue(category: .damage, amount: money("450.00"))
        line.reviewState = .accepted
        let invoice = InvoiceValue(
            receivedDate: date(2026, 5, 18),
            lines: [
                InvoiceLineValue(category: .rentalSubtotal, amount: money("2280.00"),
                                 reviewState: .accepted),
                line,
            ],
            invoiceTotal: money("2730.00")
        )
        let comparison = InvoiceComparisonEngine.compare(
            input(invoice: invoice, confirmationDate: confirmed)
        )
        XCTAssertTrue(comparison.reviewFlags.isEmpty)
        XCTAssertTrue(comparison.isFullyExplained)
    }

    func testZeroAmountLinesDoNotDemandReview() {
        let invoice = InvoiceValue(
            receivedDate: date(2026, 5, 18),
            lines: [
                InvoiceLineValue(category: .rentalSubtotal, amount: money("2280.00"),
                                 reviewState: .accepted),
                InvoiceLineValue(category: .fuel, amount: .zero),
            ],
            invoiceTotal: money("2280.00")
        )
        let comparison = InvoiceComparisonEngine.compare(
            input(invoice: invoice, confirmationDate: confirmed)
        )
        XCTAssertTrue(comparison.reviewFlags.isEmpty)
    }

    func testNegativeInvoiceTotalIsFlagged() {
        let invoice = InvoiceValue(receivedDate: date(2026, 5, 18), invoiceTotal: money("-50.00"))
        let comparison = InvoiceComparisonEngine.compare(
            input(invoice: invoice, confirmationDate: confirmed, expectedOverride: .zero)
        )
        XCTAssertTrue(comparison.findings.contains { $0.type == .negativeInvoiceTotal })
    }

    func testCentLevelDifferencesBelowRoundingAreNotMismatches() {
        let invoice = InvoiceValue(
            receivedDate: date(2026, 5, 18),
            lines: [InvoiceLineValue(category: .rentalSubtotal, amount: money("2280.001"),
                                     reviewState: .accepted)],
            invoiceTotal: money("2280.001")
        )
        let comparison = InvoiceComparisonEngine.compare(
            input(invoice: invoice, confirmationDate: confirmed)
        )
        XCTAssertTrue(comparison.findings.isEmpty)
    }
}

/// §19 of the product specification, executed end to end against the domain engines.
///
/// This does not exercise the UI, SwiftData, or a device. What it does prove is that the numbers
/// the UI will display, and the state the UI will persist, are correct — which is the part that
/// no amount of tapping through a simulator would catch.
final class FinancialWalkthroughTests: XCTestCase {

    private let cal = calendar()
    private let delivered = date(2026, 5, 4, 7)

    /// Steps 1–10: matching invoice, zero variance, resolvable.
    func testHappyPathReachesZeroVarianceAndResolves() {
        // 1–2. Create a skid-steer rental and confirm its terms.
        var terms = RentalTerms.skidSteer(
            delivered: delivered,
            mode: .manual,
            nextRollover: date(2026, 5, 11, 7),
            expectedIncrement: "285.00"
        )
        var status = RentalItemStatus.draft

        // 3. Today shows an estimate.
        status = expectSuccess(.activate, from: status, expecting: .active)
        let onDayFour = RentalRateEngine.estimate(terms: terms, asOf: date(2026, 5, 8, 8), calendar: cal)
        XCTAssertEqual(onDayFour.estimatedTotal, money("1425.00"))  // 285 × 5 periods
        XCTAssertTrue(onDayFour.isComplete)

        // 4–5. Mark done. The app must route through Contact Vendor, not to a confirmed state.
        status = expectSuccess(.markEquipmentDone, from: status, expecting: .contactVendor)
        XCTAssertEqual(
            StatusTransitionService.availableIntents(for: status).count, 1,
            "Contact Vendor offers exactly one way forward: record what the vendor said"
        )

        // 6. Record a vendor confirmation number.
        let confirmedAt = date(2026, 5, 11, 9)
        let evidence = ConfirmationEvidence(
            confirmationNumber: "OR-44921",
            vendorRepresentative: "Dana at the Ash Street yard",
            contactMethod: .phone,
            confirmedAt: confirmedAt,
            userAffirmedContact: true,
            meterReading: money("214.6"),
            fuelLevel: .threeQuarters
        )
        status = expectSuccess(
            .recordVendorConfirmation(evidence), from: status, expecting: .confirmationRecorded
        )

        // 7. It moves on to Awaiting Pickup.
        status = expectSuccess(.acknowledgeAwaitingPickup, from: status, expecting: .awaitingPickup)

        // 8. Record fuel, meter and pickup. Accrual stops at the confirmation, not at pickup.
        terms.accrualStoppedAt = confirmedAt
        let pickup = PickupEvidence(
            pickedUpAt: date(2026, 5, 12, 14),
            observedBy: "Marco",
            finalMeterReading: money("214.6"),
            finalFuelLevel: .threeQuarters
        )
        status = expectSuccess(.recordPickup(pickup), from: status, expecting: .pickedUp)
        status = expectSuccess(.beginAwaitingInvoice, from: status, expecting: .awaitingInvoice)

        let finalEstimate = RentalRateEngine.estimate(terms: terms, asOf: date(2026, 6, 1), calendar: cal)
        XCTAssertEqual(finalEstimate.estimatedTotal, money("2280.00"))
        XCTAssertTrue(finalEstimate.hasStoppedAccruing)

        // 9. Attach an invoice matching the confirmed expectation.
        status = expectSuccess(.attachInvoice, from: status, expecting: .invoiceReview)
        let invoice = InvoiceValue(
            invoiceNumber: "INV-88213",
            receivedDate: date(2026, 5, 18),
            billedThroughDate: confirmedAt,
            lines: [
                InvoiceLineValue(category: .rentalSubtotal, amount: money("2280.00"),
                                 appearedInContract: true, reviewState: .accepted),
                InvoiceLineValue(category: .delivery, amount: money("150.00"),
                                 appearedInContract: true, reviewState: .accepted),
            ],
            invoiceTotal: money("2430.00")
        )
        let comparison = InvoiceComparisonEngine.compare(
            InvoiceComparisonInput(
                terms: terms, confirmationDate: confirmedAt, pickupDate: pickup.pickedUpAt,
                invoice: invoice, calendar: cal, now: date(2026, 5, 18, 10)
            )
        )

        // 10. Variance is zero and the item resolves.
        XCTAssertEqual(comparison.possibleVariance, .zero)
        XCTAssertTrue(comparison.isFullyExplained)
        status = expectSuccess(
            .resolve(openDiscrepancyCount: comparison.openFindings.count),
            from: status, expecting: .resolved
        )
        XCTAssertFalse(status.isOpen)
    }

    /// Steps 11–15: an extra rental day survives as an open follow-up.
    func testExtraDayPathLeavesAnUnresolvedFollowUp() {
        var terms = RentalTerms.skidSteer(delivered: delivered)
        let confirmedAt = date(2026, 5, 11, 9)
        terms.accrualStoppedAt = confirmedAt

        // 11. Same rental, invoice carries one more day than expected.
        let invoice = InvoiceValue(
            invoiceNumber: "INV-88240",
            receivedDate: date(2026, 5, 18),
            billedThroughDate: date(2026, 5, 12, 9),
            lines: [
                InvoiceLineValue(category: .rentalSubtotal, amount: money("2565.00"),
                                 appearedInContract: true, reviewState: .accepted)
            ],
            invoiceTotal: money("2565.00")
        )
        let comparison = InvoiceComparisonEngine.compare(
            InvoiceComparisonInput(
                terms: terms, confirmationDate: confirmedAt, invoice: invoice,
                calendar: cal, now: date(2026, 5, 18, 10)
            )
        )

        // 12. The difference is surfaced — as a possible mismatch, not a verdict.
        XCTAssertEqual(comparison.possibleVariance, money("285.00"))
        XCTAssertEqual(comparison.openFindings.count, 2)   // subtotal + billed-past-confirmation
        XCTAssertFalse(
            comparison.findings.contains { $0.explanation.lowercased().contains("overcharge") }
        )

        // 13. Resolve is refused while a mismatch is open; a follow-up is the way forward.
        let refusal = StatusTransitionService.apply(
            .resolve(openDiscrepancyCount: comparison.openFindings.count), to: .invoiceReview
        )
        guard case let .failure(rejection) = refusal else {
            return XCTFail("resolving with open mismatches must be refused")
        }
        XCTAssertEqual(rejection, .cannotResolveWithOpenDiscrepancies(count: 2))

        let status = expectSuccess(
            .flagFollowUp(reason: "Billed one day past the OR-44921 confirmation. Called Dana 5/19."),
            from: .invoiceReview, expecting: .needsFollowUp
        )

        // 14–15. Nothing here depends on process lifetime: the comparison is a pure function of
        // stored values, so recomputing it after a relaunch yields the identical result. The
        // persistence half of this is asserted in OffRentLedgerTests/RelaunchPersistenceTests.
        let recomputed = InvoiceComparisonEngine.compare(
            InvoiceComparisonInput(
                terms: terms, confirmationDate: confirmedAt, invoice: invoice,
                calendar: cal, now: date(2026, 5, 25, 8)
            )
        )
        XCTAssertEqual(recomputed.possibleVariance, comparison.possibleVariance)
        XCTAssertEqual(recomputed.openFindings.count, comparison.openFindings.count)
        XCTAssertTrue(status.isOpen, "the follow-up must still be open")
    }

    private func expectSuccess(
        _ intent: TransitionIntent,
        from current: RentalItemStatus,
        expecting expected: RentalItemStatus,
        file: StaticString = #filePath, line: UInt = #line
    ) -> RentalItemStatus {
        switch StatusTransitionService.apply(intent, to: current) {
        case let .success(outcome):
            XCTAssertEqual(outcome.resultingStatus, expected, file: file, line: line)
            return outcome.resultingStatus
        case let .failure(rejection):
            XCTFail("expected \(expected) but was rejected: \(rejection.message)", file: file, line: line)
            return current
        }
    }
}
