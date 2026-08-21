import XCTest
@testable import OffRentDomain

final class CSVExportTests: XCTestCase {

    private func row(vendor: String = "Cedar Ridge Equipment Rental", notes: String? = nil) -> RentalSummaryRow {
        RentalSummaryRow(
            vendorName: vendor,
            vendorBranch: "Marlin Falls",
            jobSiteName: "Ridgeline, Phase 2",
            agreementNumber: "CR-44821",
            equipmentName: "Skid Steer Loader",
            vendorEquipmentIdentifier: "SS-2214",
            status: .invoiceReview,
            deliveryDate: date(2026, 5, 4, 7),
            billingBasis: .daily,
            dailyRate: money("285.00"),
            weeklyRate: money("985.00"),
            fourWeekRate: money("2450.00"),
            nextRolloverDate: date(2026, 5, 11, 7),
            estimatedRunningCost: money("2280.00"),
            estimateIsComplete: true,
            confirmationNumber: "OR-44921",
            confirmationRecordedAt: date(2026, 5, 11, 9),
            pickupRecordedAt: date(2026, 5, 12, 14),
            invoiceNumber: "INV-88213",
            invoiceTotal: money("2630.48"),
            possibleVariance: .zero,
            openMismatchCount: 0,
            notes: notes
        )
    }

    func testHeaderAndRowHaveMatchingColumnCounts() {
        let csv = CSVExport.makeCSV(rows: [row()], calendar: calendar())
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(columns(lines[0]).count, CSVExport.header.count)
        XCTAssertEqual(columns(lines[1]).count, CSVExport.header.count)
    }

    func testCommasInsideFieldsAreQuotedRatherThanShiftingColumns() {
        let csv = CSVExport.makeCSV(rows: [row()], calendar: calendar())
        let dataLine = csv.components(separatedBy: "\r\n")[1]
        XCTAssertTrue(dataLine.contains("\"Ridgeline, Phase 2\""))
        XCTAssertEqual(columns(dataLine).count, CSVExport.header.count)
    }

    func testEmbeddedQuotesAndNewlinesSurvive() {
        let csv = CSVExport.makeCSV(
            rows: [row(notes: "Dana said \"off rent as of 9am\".\nCalled twice.")],
            calendar: calendar()
        )
        XCTAssertTrue(csv.contains("\"\"off rent as of 9am\"\""))
    }

    func testFormulaInjectionIsNeutralised() {
        // A vendor name typed as `=HYPERLINK(...)` executes on open in Excel and Numbers.
        for dangerous in ["=1+1", "+SUM(A1)", "-2+3", "@SUM(A1)"] {
            let escaped = CSVExport.escape(dangerous)
            XCTAssertTrue(escaped.hasPrefix("'"), dangerous)
        }
        XCTAssertFalse(CSVExport.escape("Cedar Ridge").hasPrefix("'"))
    }

    func testAmountsAreSpreadsheetParseableNumbers() {
        XCTAssertEqual(CSVExport.amount(money("2630.48")), "2630.48")
        XCTAssertEqual(CSVExport.amount(money("1234567.891")), "1234567.89")
        XCTAssertEqual(CSVExport.amount(nil), "")
        let csv = CSVExport.makeCSV(rows: [row()], calendar: calendar())
        XCTAssertFalse(csv.contains("$"), "a currency symbol makes the column text, not numbers")
    }

    func testIncompleteEstimatesExportAsBlankRatherThanZero() {
        var incomplete = row()
        incomplete.estimateIsComplete = false
        incomplete.estimatedRunningCost = .zero
        let csv = CSVExport.makeCSV(rows: [incomplete], calendar: calendar())
        let fields = columns(csv.components(separatedBy: "\r\n")[1])
        let index = CSVExport.header.firstIndex(of: "Estimated Rent (estimate)")!
        XCTAssertEqual(fields[index], "", "a blank is honest; a zero reads as good news")
        XCTAssertEqual(fields[CSVExport.header.firstIndex(of: "Estimate Complete")!], "no")
    }

    func testEstimateColumnIsLabelledAsAnEstimate() {
        XCTAssertTrue(CSVExport.header.contains { $0.lowercased().contains("estimate") })
    }

    func testEmptyExportStillHasAHeader() {
        let csv = CSVExport.makeCSV(rows: [], calendar: calendar())
        XCTAssertTrue(csv.hasPrefix("Vendor,Branch,Jobsite"))
    }

    /// Minimal RFC 4180 splitter, used only to check our own output.
    private func columns(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        var pending: Character?
        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { current.append("\"") } else { inQuotes = false; pending = next }
                    } else { inQuotes = false }
                } else { current.append(character) }
            } else if character == "\"" {
                inQuotes = true
            } else if character == "," {
                fields.append(current); current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current)
        return fields
    }
}

final class BackupArchiveTests: XCTestCase {

    private let vendorID = UUID()
    private let siteID = UUID()
    private let agreementID = UUID()
    private let itemID = UUID()
    private let invoiceID = UUID()

    private func archive(includesFiles: Bool = false) -> BackupArchive {
        BackupArchive(
            generatedAt: date(2026, 5, 20, 9),
            appVersion: "1.0 (1)",
            includesEvidenceFiles: includesFiles,
            vendors: [
                VendorRecord(
                    id: vendorID, name: "Cedar Ridge Equipment Rental", branch: "Marlin Falls",
                    phone: "(940) 555-0148", email: nil, link: nil, standardNotes: nil,
                    createdAt: date(2026, 5, 1), modifiedAt: date(2026, 5, 1)
                )
            ],
            jobSites: [
                JobSiteRecord(
                    id: siteID, name: "Ridgeline Phase 2", projectIdentifier: "RL-2",
                    address: nil, notes: nil,
                    createdAt: date(2026, 5, 1), modifiedAt: date(2026, 5, 1)
                )
            ],
            agreements: [
                AgreementRecord(
                    id: agreementID, vendorID: vendorID, jobSiteID: siteID,
                    agreementNumber: "CR-44821", startDate: date(2026, 5, 4, 7),
                    scheduledEndDate: date(2026, 5, 18, 7), disputeWindowDaysOverride: 15,
                    notes: nil, createdAt: date(2026, 5, 4), modifiedAt: date(2026, 5, 4)
                )
            ],
            items: [
                RentalItemRecord(
                    id: itemID, agreementID: agreementID, equipmentName: "Skid Steer Loader",
                    equipmentClass: "75HP", vendorEquipmentIdentifier: "SS-2214",
                    serialNumber: "A9KT4417732", status: .invoiceReview,
                    terms: .skidSteer(delivered: date(2026, 5, 4, 7)), meterUnit: .hours,
                    notes: nil, createdAt: date(2026, 5, 4), modifiedAt: date(2026, 5, 12)
                )
            ],
            events: [
                RentalEventRecord(
                    id: UUID(), itemID: itemID, type: .vendorConfirmationRecorded,
                    timestamp: date(2026, 5, 11, 9), detail: "Called the Ash Street yard",
                    contactMethod: .phone, vendorRepresentative: "Dana",
                    confirmationNumber: "OR-44921", locationSnapshot: nil,
                    createdAt: date(2026, 5, 11, 9)
                )
            ],
            assets: [
                EvidenceAssetRecord(
                    id: UUID(), ownerKind: .item, ownerID: itemID,
                    relativePath: "Evidence/\(itemID.uuidString)/meter.jpg",
                    mediaType: .image, displayName: "Meter at off-rent",
                    capturedAt: date(2026, 5, 11, 9), coordinate: nil, caption: "214.6 hrs",
                    sha256: String(repeating: "a", count: 64), thumbnailRelativePath: nil
                )
            ],
            invoices: [
                InvoiceRecord(
                    id: invoiceID, agreementID: agreementID,
                    invoice: InvoiceValue(
                        id: invoiceID, invoiceNumber: "INV-88213",
                        receivedDate: date(2026, 5, 18),
                        lines: [InvoiceLineValue(category: .rentalSubtotal, amount: money("2280.00"))],
                        invoiceTotal: money("2280.00")
                    ),
                    attachmentAssetID: nil, attachedAt: date(2026, 5, 18), reviewedAt: nil
                )
            ],
            discrepancies: [
                DiscrepancyRecord(
                    id: UUID(), invoiceID: invoiceID, itemID: itemID,
                    discrepancy: DiscrepancyValue(
                        type: .rentalSubtotalDiffers, expectedAmount: money("2280.00"),
                        invoicedAmount: money("2565.00"), difference: money("285.00"),
                        explanation: "Possible mismatch.", createdAt: date(2026, 5, 18)
                    )
                )
            ]
        )
    }

    // MARK: - Round trip

    func testArchiveRoundTripsExactly() throws {
        let original = archive()
        let data = try BackupArchive.encoder().encode(original)
        let decoded = try BackupArchive.decoder().decode(BackupArchive.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testEncodingIsByteStableSoTwoExportsCanBeDiffed() throws {
        let original = archive()
        let first = try BackupArchive.encoder().encode(original)
        let second = try BackupArchive.encoder().encode(original)
        XCTAssertEqual(first, second)
    }

    func testDecimalsSurviveTheRoundTripWithoutBinaryDrift() throws {
        var original = archive()
        original.invoices[0].invoice.invoiceTotal = money("0.10")
        original.invoices[0].invoice.lines = (0..<10).map { _ in
            InvoiceLineValue(category: .other, amount: money("0.01"))
        }
        let data = try BackupArchive.encoder().encode(original)
        let decoded = try BackupArchive.decoder().decode(BackupArchive.self, from: data)
        XCTAssertEqual(decoded.invoices[0].invoice.lineSum, money("0.10"))
        XCTAssertEqual(decoded.invoices[0].invoice.invoiceTotal, money("0.10"))
    }

    // MARK: - Version gate

    func testANewerFormatVersionIsRefusedWithAnActionableMessage() throws {
        var data = try BackupArchive.encoder().encode(archive())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["formatVersion"] = 99
        data = try JSONSerialization.data(withJSONObject: object)

        guard case let .failure(failure) = BackupImporter.decode(data) else {
            return XCTFail("a newer archive must be refused, not partially read")
        }
        XCTAssertEqual(failure, .unsupportedFormatVersion(found: 99, supported: 1))
        XCTAssertTrue(failure.message.contains("Update the app"))
    }

    func testNonJSONIsRefused() {
        guard case let .failure(failure) = BackupImporter.decode(Data("not json".utf8)) else {
            return XCTFail("must be refused")
        }
        XCTAssertEqual(failure, .notJSON)
    }

    func testJSONWithoutAVersionIsRefused() throws {
        let data = try JSONSerialization.data(withJSONObject: ["hello": "world"])
        guard case let .failure(failure) = BackupImporter.decode(data) else {
            return XCTFail("must be refused")
        }
        XCTAssertEqual(failure, .corrupt("no format version"))
    }

    // MARK: - Preview

    func testPreviewOfAFreshImportCountsEverything() {
        let preview = BackupImporter.preview(archive: archive(), existing: .none)
        XCTAssertEqual(preview.willAdd.vendors, 1)
        XCTAssertEqual(preview.willAdd.jobSites, 1)
        XCTAssertEqual(preview.willAdd.agreements, 1)
        XCTAssertEqual(preview.willAdd.items, 1)
        XCTAssertEqual(preview.willAdd.events, 1)
        XCTAssertEqual(preview.willAdd.invoices, 1)
        XCTAssertEqual(preview.willAdd.discrepancies, 1)
        XCTAssertEqual(preview.willAdd.assets, 1)
        XCTAssertEqual(preview.willSkipExisting.total, 0)
        XCTAssertEqual(preview.willSkipOrphaned.total, 0)
        XCTAssertFalse(preview.isEmpty)
        XCTAssertTrue(preview.summary.hasPrefix("Will add"))
    }

    func testImportIsAdditiveAndNeverOverwritesExistingRecords() {
        // Restoring an old backup must not destroy work done since it was taken.
        let source = archive()
        let existing = ExistingIdentifiers(
            vendors: [vendorID],
            jobSites: [siteID],
            agreements: [agreementID],
            items: [itemID],
            events: Set(source.events.map(\.id)),
            invoices: [invoiceID],
            discrepancies: Set(source.discrepancies.map(\.id)),
            assets: Set(source.assets.map(\.id))
        )
        let preview = BackupImporter.preview(archive: source, existing: existing)
        XCTAssertEqual(preview.willAdd.total, 0)
        XCTAssertEqual(preview.willSkipExisting.total, 8)
        XCTAssertTrue(preview.isEmpty)
        XCTAssertTrue(preview.summary.contains("already here"))
    }

    func testOrphanedChildrenAreSkippedRatherThanImportedDangling() {
        var source = archive()
        source.agreements = []      // items now reference an agreement nobody has
        let preview = BackupImporter.preview(archive: source, existing: .none)
        XCTAssertEqual(preview.willSkipOrphaned.items, 1)
        XCTAssertEqual(preview.willSkipOrphaned.invoices, 1)
        XCTAssertEqual(preview.willAdd.items, 0)
        XCTAssertEqual(preview.willSkipOrphaned.events, 1)
        XCTAssertEqual(preview.willSkipOrphaned.discrepancies, 1)
    }

    func testAnAgreementWhoseVendorIsMissingIsSkipped() {
        var source = archive()
        source.vendors = []
        let preview = BackupImporter.preview(archive: source, existing: .none)
        XCTAssertEqual(preview.willSkipOrphaned.agreements, 1)
    }

    func testAnAgreementWhoseVendorAlreadyExistsIsNotOrphaned() {
        var source = archive()
        source.vendors = []
        let preview = BackupImporter.preview(
            archive: source, existing: ExistingIdentifiers(vendors: [vendorID])
        )
        XCTAssertEqual(preview.willSkipOrphaned.agreements, 0)
        XCTAssertEqual(preview.willAdd.agreements, 1)
    }

    func testMissingEvidenceFilesAreReportedWithoutFailingTheWholeImport() {
        let source = archive(includesFiles: true)
        let preview = BackupImporter.preview(
            archive: source, existing: .none, availableEvidenceFiles: []
        )
        XCTAssertEqual(preview.missingEvidenceFiles.count, 1)
        XCTAssertEqual(preview.willAdd.assets, 1, "the metadata still imports")
    }

    func testPresentEvidenceFilesAreNotReportedMissing() {
        let source = archive(includesFiles: true)
        let preview = BackupImporter.preview(
            archive: source,
            existing: .none,
            availableEvidenceFiles: Set(source.assets.map(\.relativePath))
        )
        XCTAssertTrue(preview.missingEvidenceFiles.isEmpty)
    }

    func testMetadataOnlyBackupDoesNotReportMissingFiles() {
        let preview = BackupImporter.preview(archive: archive(includesFiles: false), existing: .none)
        XCTAssertTrue(preview.missingEvidenceFiles.isEmpty)
        XCTAssertFalse(preview.includesEvidenceFiles)
    }

    func testEvidencePathsAreRelativeNeverAbsolute() {
        for asset in archive().assets {
            XCTAssertFalse(
                asset.relativePath.hasPrefix("/"),
                "an absolute path is invalid the moment iOS reassigns the app container"
            )
        }
    }
}

final class EvidencePacketTests: XCTestCase {

    private func packet(
        confirmation: ConfirmationEvidence? = nil,
        pickup: PickupEvidence? = nil,
        assets: [EvidencePacket.AssetSummary] = [],
        invoice: InvoiceValue? = nil,
        comparison: InvoiceComparison? = nil
    ) -> EvidencePacket {
        let terms = RentalTerms.skidSteer(delivered: date(2026, 5, 4, 7))
        return EvidencePacket(
            generatedAt: date(2026, 5, 20, 9),
            appDisplayName: "OffRent Ledger",
            appVersion: "1.0 (1)",
            companyName: "Idlery Services LLC",
            vendor: .init(
                name: "Cedar Ridge Equipment Rental", branch: "Marlin Falls",
                phone: "(940) 555-0148", email: nil, link: nil
            ),
            jobSite: .init(name: "Ridgeline Phase 2", projectIdentifier: "RL-2", address: nil),
            agreementNumber: "CR-44821",
            agreementStartDate: date(2026, 5, 4, 7),
            agreementScheduledEndDate: date(2026, 5, 18, 7),
            equipmentName: "Skid Steer Loader",
            equipmentClass: "75HP",
            vendorEquipmentIdentifier: "SS-2214",
            serialNumber: "A9KT4417732",
            status: .invoiceReview,
            terms: terms,
            estimate: RentalRateEngine.estimate(
                terms: terms, asOf: date(2026, 5, 11, 9), calendar: calendar()
            ),
            timeline: [
                .init(
                    timestamp: date(2026, 5, 11, 8), title: "Contact attempt recorded",
                    detail: "No answer at the yard", contactMethod: .phone,
                    vendorRepresentative: nil, confirmationNumber: nil, hasLocation: false
                ),
                .init(
                    timestamp: date(2026, 5, 11, 9), title: "Vendor confirmation recorded",
                    detail: nil, contactMethod: .phone, vendorRepresentative: "Dana",
                    confirmationNumber: "OR-44921", hasLocation: true
                ),
            ],
            confirmation: confirmation,
            pickup: pickup,
            meterUnit: .hours,
            selectedAssets: assets,
            invoice: invoice,
            comparison: comparison,
            userNotes: nil,
            disclaimer: EvidencePacketBuilder.disclaimer(
                appName: "OffRent Ledger", companyName: "Idlery Services LLC"
            )
        )
    }

    func testDisclaimerDeniesEveryClaimTheAppMustNotMake() {
        let text = EvidencePacketBuilder.disclaimer(
            appName: "OffRent Ledger", companyName: "Idlery Services LLC"
        )
        for required in [
            "did not contact the rental company",
            "did not end any rental",
            "not legally binding",
            "may be misread",
            "not a chain of custody",
            "not a determination that any charge is incorrect",
            "does not provide \n".trimmingCharacters(in: .whitespacesAndNewlines),
            "rental company's own agreement governs",
        ] {
            XCTAssertTrue(text.contains(required), "disclaimer is missing: \(required)")
        }
    }

    func testDisclaimerContainsNoProhibitedClaim() {
        let text = EvidencePacketBuilder.disclaimer(
            appName: "OffRent Ledger", companyName: "Idlery Services LLC"
        ).lowercased()
        for banned in ["legal proof", "tamper-proof", "guaranteed", "verified overcharge", "proves"] {
            XCTAssertFalse(text.contains(banned), banned)
        }
    }

    func testContactAttemptsAreExtractedFromTheTimeline() {
        XCTAssertEqual(packet().contactAttempts.count, 2)
    }

    func testCompletenessNamesEveryMissingPiece() {
        let missing = EvidencePacketBuilder.completeness(of: packet())
        XCTAssertTrue(missing.contains { $0.contains("No vendor confirmation") })
        XCTAssertTrue(missing.contains { $0.contains("No pickup") })
        XCTAssertTrue(missing.contains { $0.contains("No photos") })
        XCTAssertTrue(missing.contains { $0.contains("No final invoice") })
    }

    func testACompletePacketReportsNothingMissing() {
        let complete = packet(
            confirmation: ConfirmationEvidence(
                confirmationNumber: "OR-44921", contactMethod: .phone,
                confirmedAt: date(2026, 5, 11, 9), userAffirmedContact: true
            ),
            pickup: PickupEvidence(pickedUpAt: date(2026, 5, 12, 14)),
            assets: [
                .init(
                    displayName: "Meter", caption: nil, capturedAt: date(2026, 5, 11, 9),
                    mediaType: .image, relativePath: "Evidence/a/meter.jpg",
                    sha256: nil, hasCoordinate: false
                )
            ],
            invoice: InvoiceValue(receivedDate: date(2026, 5, 18), invoiceTotal: money("2280.00"))
        )
        XCTAssertTrue(EvidencePacketBuilder.completeness(of: complete).isEmpty)
    }

    func testHeadlineIdentifiesTheMachineAndTheVendor() {
        XCTAssertEqual(
            EvidencePacketBuilder.headline(for: packet()),
            "Skid Steer Loader (SS-2214) — Cedar Ridge Equipment Rental · CR-44821"
        )
    }
}
