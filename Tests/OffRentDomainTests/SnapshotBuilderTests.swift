import Foundation
import XCTest
@testable import OffRentDomain

final class SnapshotBuilderTests: XCTestCase {

    private let now = date(2026, 5, 9, 10)

    private func item(
        _ status: RentalItemStatus,
        machine: String = "Skid Steer",
        daily: String = "285.00",
        delivered: Date? = nil,
        rollover: Date? = nil,
        invoiceToReview: Bool = false
    ) -> SnapshotItemInput {
        SnapshotItemInput(
            equipmentName: machine,
            status: status,
            terms: .skidSteer(
                delivered: delivered ?? date(2026, 5, 4, 7),
                daily: daily,
                mode: .manual,
                nextRollover: rollover ?? date(2026, 5, 11, 7),
                expectedIncrement: daily
            ),
            hasInvoiceAwaitingReview: invoiceToReview
        )
    }

    func testCountsAndAggregate() {
        let snapshot = SnapshotBuilder.build(
            items: [
                item(.active),                       // 5 days on rent → 6 × 285 = 1710
                item(.contactVendor, daily: "100.00"),  // 6 × 100 = 600
                item(.awaitingPickup),
                item(.invoiceReview, invoiceToReview: true),
                item(.resolved),
                item(.archived),
            ],
            now: now, calendar: calendar()
        )
        XCTAssertEqual(snapshot.openItemCount, 4)
        XCTAssertEqual(snapshot.accruingItemCount, 2)
        XCTAssertEqual(snapshot.estimatedRentRunning, money("2310.00"))
        XCTAssertEqual(snapshot.awaitingPickupCount, 1)
        XCTAssertEqual(snapshot.invoicesAwaitingReviewCount, 1)
        XCTAssertEqual(snapshot.nextRateChangeDate, date(2026, 5, 11, 7))
    }

    func testSoonestRateChangeWins() {
        let snapshot = SnapshotBuilder.build(
            items: [
                item(.active, rollover: date(2026, 5, 20, 7)),
                item(.active, rollover: date(2026, 5, 12, 7)),
                item(.active, rollover: date(2026, 5, 16, 7)),
            ],
            now: now, calendar: calendar()
        )
        XCTAssertEqual(snapshot.nextRateChangeDate, date(2026, 5, 12, 7))
    }

    func testIncompleteEstimatesContributeNothingRatherThanZero() {
        let noRate = SnapshotItemInput(
            equipmentName: "No rate",
            status: .active,
            terms: RentalTerms(deliveryDate: date(2026, 5, 4, 7), rateCard: RateCard(), billingBasis: .daily)
        )
        let snapshot = SnapshotBuilder.build(items: [noRate, item(.active)], now: now, calendar: calendar())
        XCTAssertEqual(snapshot.estimatedRentRunning, money("1710.00"))
        XCTAssertEqual(snapshot.accruingItemCount, 2)
    }

    func testEmptyStoreProducesAnEmptySnapshot() {
        let snapshot = SnapshotBuilder.build(items: [], now: now, calendar: calendar())
        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertEqual(snapshot.estimatedRentRunning, .zero)
    }

    /// The widget privacy property.
    ///
    /// The snapshot carries machine names now, because a widget that says "3 open" without saying
    /// which three is a number rather than a tool. Everything that identifies somebody *other*
    /// than the user stays out, and this is the test that fails if a `vendorName` or a `jobsite`
    /// is added later. Encoding it and searching the JSON is blunt, and blunt is the point: it
    /// catches a new field whatever it is called.
    ///
    /// The other half of the guarantee — that machine names never reach the *lock screen* — is
    /// structural and lives in `SummaryWidgetView`, whose accessory branches read only the
    /// counts. `scripts/verify_repository.py` fails the build if one of them starts reading
    /// `rows`.
    func testEncodedSnapshotCarriesTheMachineAndNothingElseIdentifying() throws {
        let snapshot = SnapshotBuilder.build(
            items: [
                item(.active, machine: "Skid Steer"),
                item(.awaitingPickup, machine: "Scissor Lift"),
            ],
            now: now, calendar: calendar()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(data: try encoder.encode(snapshot), encoding: .utf8) ?? ""

        // What it is for.
        XCTAssertTrue(json.contains("Skid Steer"))
        XCTAssertTrue(json.contains("Scissor Lift"))

        // What it must never grow a field for. "vendor" is absent as a substring too, which is
        // what makes `contactVendor` spelled out in the JSON a deliberate exception below.
        for forbidden in [
            "Cedar Ridge", "jobsite", "jobSite", "agreement", "invoiceNumber",
            "confirmationNumber", "serial", "notes", "address", "latitude", "longitude",
        ] {
            XCTAssertFalse(
                json.lowercased().contains(forbidden.lowercased()),
                "the widget snapshot must not be able to carry \(forbidden)"
            )
        }
    }

    /// A rental company's name must not reach the snapshot, and there is nowhere to put one.
    ///
    /// Asserted separately from the sweep above because `RentalSummarySnapshot.Row.State.contactVendor`
    /// puts the literal string "contactVendor" in the JSON as a status code. That is a state
    /// name, not a company — so the check that matters is that the *name the user typed* for the
    /// rental company cannot appear, which `SnapshotItemInput` gives no way to pass in.
    func testTheRentalCompanyCannotReachTheSnapshot() throws {
        let snapshot = SnapshotBuilder.build(
            items: [item(.contactVendor, machine: "Excavator")], now: now, calendar: calendar()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(data: try encoder.encode(snapshot), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("Cedar Ridge Rentals"))
        XCTAssertEqual(snapshot.rows.map(\.machine), ["Excavator"])
    }

    // MARK: - Rows

    func testOnlyOpenRentalsGetARow() {
        let snapshot = SnapshotBuilder.build(
            items: [
                item(.active, machine: "A"),
                item(.awaitingPickup, machine: "B"),
                item(.resolved, machine: "C"),
                item(.archived, machine: "D"),
            ],
            now: now, calendar: calendar()
        )
        XCTAssertEqual(Set(snapshot.rows.map(\.machine)), ["A", "B"])
    }

    func testRowsAreRankedByWhatNeedsDoingFirst() {
        let snapshot = SnapshotBuilder.build(
            items: [
                item(.active, machine: "Running"),
                item(.awaitingPickup, machine: "Pickup"),
                item(.invoiceReview, machine: "Invoice", invoiceToReview: true),
                item(.contactVendor, machine: "Call"),
            ],
            now: now, calendar: calendar()
        )
        XCTAssertEqual(snapshot.rows.map(\.machine), ["Invoice", "Call", "Pickup", "Running"])
    }

    func testRowsAreCappedAndTheCountStillTellsTheTruth() {
        let many = (0..<20).map { item(.active, machine: "Machine \($0)") }
        let snapshot = SnapshotBuilder.build(items: many, now: now, calendar: calendar())
        XCTAssertEqual(snapshot.rows.count, RentalSummarySnapshot.maxRows)
        XCTAssertEqual(snapshot.openItemCount, 20)
        XCTAssertEqual(snapshot.hiddenRowCount, 20 - RentalSummarySnapshot.maxRows)
    }

    /// A `$0` beside a machine that has been on rent for five days reads as "this one is free".
    func testARowWithNoUsableRateCarriesNoEstimateRatherThanZero() {
        let noRate = SnapshotItemInput(
            equipmentName: "No rate",
            status: .active,
            terms: RentalTerms(deliveryDate: date(2026, 5, 4, 7), rateCard: RateCard(), billingBasis: .daily)
        )
        let snapshot = SnapshotBuilder.build(items: [noRate], now: now, calendar: calendar())
        XCTAssertEqual(snapshot.rows.count, 1)
        XCTAssertNil(snapshot.rows[0].estimate)
        XCTAssertNil(snapshot.rows[0].daysOnRent)
    }

    func testARowThatIsNotAccruingCarriesNoEstimate() {
        let snapshot = SnapshotBuilder.build(
            items: [item(.awaitingPickup, machine: "Lift")], now: now, calendar: calendar()
        )
        XCTAssertNil(snapshot.rows[0].estimate)
        XCTAssertEqual(snapshot.rows[0].state, .awaitingPickup)
    }

    func testPerRowEstimatesSumToTheAggregate() {
        let snapshot = SnapshotBuilder.build(
            items: [
                item(.active, machine: "One"),
                item(.contactVendor, machine: "Two", daily: "100.00"),
            ],
            now: now, calendar: calendar()
        )
        let rowTotal = snapshot.rows.compactMap(\.estimate).reduce(Decimal.zero, +)
        XCTAssertEqual(rowTotal, snapshot.estimatedRentRunning)
    }

    func testAnUnnamedRentalIsDescribedRatherThanBlank() {
        let snapshot = SnapshotBuilder.build(
            items: [item(.active, machine: "   ")], now: now, calendar: calendar()
        )
        XCTAssertEqual(snapshot.rows[0].machine, "Untitled rental")
    }

    func testAVeryLongMachineNameIsTruncatedInTheSnapshotItself() {
        let long = String(repeating: "Excavator ", count: 20)
        let snapshot = SnapshotBuilder.build(
            items: [item(.active, machine: long)], now: now, calendar: calendar()
        )
        XCTAssertEqual(snapshot.rows[0].machine.count, RentalSummarySnapshot.machineNameLimit)
        XCTAssertTrue(snapshot.rows[0].machine.hasSuffix("\u{2026}"))
    }

    /// Every widget row state has a label. A blank one would render as an empty status.
    func testEveryRowStateHasBothLabels() {
        for state in RentalSummarySnapshot.Row.State.allCases {
            XCTAssertFalse(state.shortLabel.isEmpty, "\(state)")
            XCTAssertFalse(state.spokenLabel.isEmpty, "\(state)")
        }
    }

    func testSnapshotSchemaVersionIsStamped() {
        let snapshot = SnapshotBuilder.build(items: [], now: now, calendar: calendar())
        XCTAssertEqual(snapshot.schemaVersion, RentalSummarySnapshot.currentSchemaVersion)
    }
}
