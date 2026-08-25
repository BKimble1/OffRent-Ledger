import Foundation
import XCTest
@testable import OffRentDomain

final class MapSearchTests: XCTestCase {

    private let skidSteerID = UUID()
    private let excavatorID = UUID()
    private let ridgelineID = UUID()

    private var records: [MapRecord] {
        [
            MapRecord(
                id: skidSteerID,
                kind: .rental,
                title: "Skid Steer Loader 75HP",
                subtitle: "Cedar Ridge Equipment",
                status: .contactVendor,
                jobSiteID: ridgelineID,
                jobSiteName: "Ridgeline Phase 2",
                address: "212 Quarry Lane, Allamuchy, NJ",
                latitude: 40.9012,
                longitude: -74.8123,
                searchTerms: [
                    "Skid Steer Loader 75HP", "Skid Steer", "SS-2214", "A9KT4417732",
                    "Cedar Ridge Equipment", "Ridgeline Phase 2",
                    "212 Quarry Lane, Allamuchy, NJ", "CR-44821", "PO-90114",
                    "Contact Vendor",
                ]
            ),
            MapRecord(
                id: excavatorID,
                kind: .rental,
                title: "Mini Excavator 3.5T",
                subtitle: "Foundry Tool Supply",
                status: .active,
                jobSiteID: ridgelineID,
                jobSiteName: "Ridgeline Phase 2",
                latitude: 40.9012,
                longitude: -74.8123,
                searchTerms: [
                    "Mini Excavator 3.5T", "Foundry Tool Supply", "Ridgeline Phase 2",
                    "MX-88", "On Rent",
                ]
            ),
            MapRecord(
                id: ridgelineID,
                kind: .jobsite,
                title: "Ridgeline Phase 2",
                subtitle: "212 Quarry Lane, Allamuchy, NJ",
                latitude: 40.9012,
                longitude: -74.8123,
                searchTerms: ["Ridgeline Phase 2", "212 Quarry Lane, Allamuchy, NJ"]
            ),
            MapRecord(
                id: UUID(),
                kind: .rental,
                title: "Air Compressor 185CFM",
                subtitle: "Cedar Ridge Equipment",
                status: .active,
                searchTerms: ["Air Compressor 185CFM", "Cedar Ridge Equipment"]
            ),
        ]
    }

    // MARK: - Searching the user's own data

    func testAnEmptyQueryReturnsEverything() {
        XCTAssertEqual(MapSearch.matches(records, query: "").count, records.count)
        XCTAssertEqual(MapSearch.matches(records, query: "   ").count, records.count)
    }

    func testEquipmentNameMatches() {
        let found = MapSearch.matches(records, query: "skid")
        XCTAssertEqual(found.map(\.id), [skidSteerID])
    }

    func testVendorEquipmentIdentifierMatches() {
        XCTAssertEqual(MapSearch.matches(records, query: "SS-2214").map(\.id), [skidSteerID])
    }

    func testSerialNumberMatches() {
        XCTAssertEqual(MapSearch.matches(records, query: "a9kt441").map(\.id), [skidSteerID])
    }

    func testAgreementNumberMatches() {
        XCTAssertEqual(MapSearch.matches(records, query: "CR-44821").map(\.id), [skidSteerID])
    }

    func testPurchaseOrderMatches() {
        XCTAssertEqual(MapSearch.matches(records, query: "po-90114").map(\.id), [skidSteerID])
    }

    func testStatusMatches() {
        XCTAssertEqual(MapSearch.matches(records, query: "contact vendor").map(\.id), [skidSteerID])
    }

    func testCompanyMatchesEveryRentalFiledUnderIt() {
        XCTAssertEqual(MapSearch.matches(records, query: "Cedar Ridge").count, 2)
    }

    func testJobsiteNameMatchesTheSiteAndTheRentalsOnIt() {
        XCTAssertEqual(MapSearch.matches(records, query: "Ridgeline").count, 3)
    }

    func testAddressMatches() {
        XCTAssertEqual(MapSearch.matches(records, query: "quarry lane").count, 2)
    }

    func testEveryWordMustMatchSoTwoWordsNarrowRatherThanBroaden() {
        // "skid ridgeline" is one machine at one site, not every machine and every site.
        XCTAssertEqual(MapSearch.matches(records, query: "skid ridgeline").map(\.id), [skidSteerID])
    }

    func testSearchIsCaseInsensitive() {
        XCTAssertEqual(
            MapSearch.matches(records, query: "SKID").count,
            MapSearch.matches(records, query: "skid").count
        )
    }

    func testNothingMatchingReturnsNothingRatherThanEverything() {
        XCTAssertTrue(MapSearch.matches(records, query: "backhoe").isEmpty)
    }

    // MARK: - Clustering

    func testRecordsSharingACoordinateBecomeOneMarker() {
        let clusters = MapClustering.cluster(records)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.first?.count, 3)
    }

    func testARecordWithNoCoordinateIsNeverPlacedAtAFakeOne() {
        // The air compressor has no jobsite. It must not appear in any cluster.
        let clusters = MapClustering.cluster(records)
        let placed = clusters.flatMap(\.records).map(\.title)
        XCTAssertFalse(placed.contains("Air Compressor 185CFM"))
        XCTAssertEqual(MapClustering.unplaced(records).map(\.title), ["Air Compressor 185CFM"])
    }

    func testDistinctCoordinatesStayDistinct() {
        var far = records[0]
        far.id = UUID()
        far.latitude = 32.7767
        far.longitude = -96.7970
        XCTAssertEqual(MapClustering.cluster(records + [far]).count, 2)
    }

    func testACoordinateAMetreAwayIsTheSameYard() {
        var nudged = records[0]
        nudged.id = UUID()
        nudged.latitude = 40.901_200_4
        XCTAssertEqual(MapClustering.cluster([records[0], nudged]).count, 1)
    }

    func testTheMostUrgentRentalDecidesTheMarker() {
        // A yard with one machine waiting on a phone call must not read as settled because the
        // other one is merely on rent.
        let cluster = MapClustering.cluster(records).first
        XCTAssertEqual(cluster?.representative?.status, .contactVendor)
    }

    func testAClusterAnnouncesWhatIsInItRatherThanSayingPin() {
        let label = MapClustering.cluster(records).first?.accessibilityLabel ?? ""
        XCTAssertTrue(label.contains("Ridgeline Phase 2"), label)
        XCTAssertTrue(label.contains("Skid Steer Loader 75HP"), label)
        XCTAssertFalse(label.lowercased().contains("pin"), label)
    }

    func testASingleRecordAnnouncesItsEntityAndStatus() {
        let solo = MapClustering.cluster([records[0]]).first
        let label = solo?.accessibilityLabel ?? ""
        XCTAssertTrue(label.contains("Rental"), label)
        XCTAssertTrue(label.contains("Skid Steer Loader 75HP"), label)
        XCTAssertTrue(label.contains("Contact Vendor"), label)
    }

    func testARecordWithNoLocationSaysSo() {
        let orphan = records.first { !$0.hasCoordinate }
        XCTAssertTrue(orphan?.accessibilityLabel.contains("No location set") ?? false)
    }

    // MARK: - Filters

    func testFiltersPartitionSensibly() {
        XCTAssertEqual(MapFilter.apply(.all, to: records).count, records.count)
        XCTAssertEqual(MapFilter.apply(.jobsites, to: records).map(\.id), [ridgelineID])
        XCTAssertEqual(MapFilter.apply(.onRent, to: records).count, 3)
        XCTAssertTrue(MapFilter.apply(.closed, to: records).isEmpty)
    }

    func testAJobsiteIsNeverCaughtByAStatusFilter() {
        for filter in [MapFilter.onRent, .awaitingPickup, .closed] {
            XCTAssertFalse(
                MapFilter.apply(filter, to: records).contains { $0.kind == .jobsite },
                filter.title
            )
        }
    }

    func testEveryFilterHasATitle() {
        for filter in MapFilter.allCases {
            XCTAssertFalse(filter.title.isEmpty)
        }
    }
}

/// What a marker offers when it is tapped.
final class MapClusterListingTests: XCTestCase {

    private func rental(_ title: String, at coordinate: (Double, Double)?) -> MapRecord {
        MapRecord(
            id: UUID(), kind: .rental, title: title, status: .active,
            latitude: coordinate?.0, longitude: coordinate?.1, searchTerms: [title]
        )
    }

    private func jobsite(_ title: String, at coordinate: (Double, Double)) -> MapRecord {
        MapRecord(
            id: UUID(), kind: .jobsite, title: title,
            latitude: coordinate.0, longitude: coordinate.1, searchTerms: [title]
        )
    }

    private let point = (40.9012, -74.8123)

    func testOneMachineAtAJobsiteOpensTheMachineRatherThanAListOfTwo() {
        // The jobsite is the *place*, and it is already the cluster's title. Listing it beside
        // the one machine on it is a row that says the same thing twice, and it turns a single
        // tap into two.
        let cluster = MapClustering.cluster([
            jobsite("Ridgeline Phase 2", at: point),
            rental("Skid Steer Loader", at: point),
        ]).first
        XCTAssertEqual(cluster?.count, 2, "both records are still on the marker")
        XCTAssertTrue(cluster?.isSingle ?? false, "but only one of them is worth opening")
        XCTAssertEqual(cluster?.listedRecords.map(\.title), ["Skid Steer Loader"])
    }

    func testTheMarkerBadgeCountsWhatTappingItWillShow() {
        // Three records at one point — a site and two machines — but the card that opens lists
        // two. A badge reading 3 over a list of 2 is the map disagreeing with itself, and the
        // record it counts and does not show is the place the badge is already sitting on.
        let cluster = MapClustering.cluster([
            jobsite("Ridgeline Phase 2", at: point),
            rental("Skid Steer Loader", at: point),
            rental("Mini Excavator", at: point),
        ]).first
        XCTAssertEqual(cluster?.count, 3, "all three are still clustered")
        XCTAssertEqual(cluster?.badgeCount, 2, "but the badge counts the rows the tap will show")
        XCTAssertEqual(cluster?.badgeCount, cluster?.listedRecords.count)
    }

    func testAJobsiteOnItsOwnBadgesAsWhatItIs() {
        // The other direction: nothing on rent means the site itself is the row, so the badge
        // must not fall to zero and leave a marker claiming to hold nothing.
        let cluster = MapClustering.cluster([
            jobsite("Quarry Lane Yard", at: point),
            jobsite("Quarry Lane Office", at: point),
        ]).first
        XCTAssertEqual(cluster?.badgeCount, 2)
    }

    func testTwoMachinesAtAJobsiteListBothAndNotTheJobsite() {
        let cluster = MapClustering.cluster([
            jobsite("Ridgeline Phase 2", at: point),
            rental("Skid Steer Loader", at: point),
            rental("Mini Excavator", at: point),
        ]).first
        XCTAssertFalse(cluster?.isSingle ?? true)
        XCTAssertEqual(cluster?.listedRecords.count, 2)
        XCTAssertFalse(cluster?.listedRecords.contains { $0.kind == .jobsite } ?? true)
    }

    func testAJobsiteWithNothingOnRentIsStillReachable() {
        // The case the filter must not swallow: a saved site with no rentals lists itself, so a
        // user can still tap it and fix its location.
        let cluster = MapClustering.cluster([jobsite("Quarry Lane Yard", at: point)]).first
        XCTAssertTrue(cluster?.isSingle ?? false)
        XCTAssertEqual(cluster?.listedRecords.map(\.title), ["Quarry Lane Yard"])
    }

    func testTheMarkerTitleStillNamesThePlaceRatherThanOneMachine() {
        let cluster = MapClustering.cluster([
            jobsite("Ridgeline Phase 2", at: point),
            rental("Skid Steer Loader", at: point),
            rental("Mini Excavator", at: point),
        ]).first
        XCTAssertEqual(cluster?.title, "Ridgeline Phase 2")
    }
}
