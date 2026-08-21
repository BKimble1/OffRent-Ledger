import XCTest
@testable import OffRentDomain

final class SnapshotBuilderTests: XCTestCase {

    private let now = date(2026, 5, 9, 10)

    private func item(
        _ status: RentalItemStatus,
        daily: String = "285.00",
        delivered: Date? = nil,
        rollover: Date? = nil,
        invoiceToReview: Bool = false
    ) -> SnapshotItemInput {
        SnapshotItemInput(
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
    /// The snapshot is what renders on a lock screen, where the viewer is not necessarily the
    /// person who unlocked the phone. Encoding it and searching the JSON is a blunt check, but it
    /// is the one that actually fails if somebody adds a `vendorName` field later.
    func testEncodedSnapshotContainsNoIdentifyingDetail() throws {
        let snapshot = SnapshotBuilder.build(
            items: [item(.active), item(.awaitingPickup)], now: now, calendar: calendar()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(data: try encoder.encode(snapshot), encoding: .utf8) ?? ""

        for forbidden in [
            "Cedar Ridge", "vendor", "jobsite", "jobSite", "equipment", "agreement",
            "invoiceNumber", "confirmation", "serial", "notes", "address",
        ] {
            XCTAssertFalse(
                json.lowercased().contains(forbidden.lowercased()),
                "the widget snapshot must not be able to carry \(forbidden)"
            )
        }
    }

    func testSnapshotSchemaVersionIsStamped() {
        let snapshot = SnapshotBuilder.build(items: [], now: now, calendar: calendar())
        XCTAssertEqual(snapshot.schemaVersion, RentalSummarySnapshot.currentSchemaVersion)
    }
}
