import Foundation
import XCTest
@testable import OffRentDomain

/// The extraction the screenshots demanded: useful on real rental paperwork, silent on anything
/// else, and never confidently wrong about a mis-read digit.
final class ExtractionFixtureTests: XCTestCase {

    private func fixture(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root
                .appendingPathComponent("OffRentLedger/Resources/OCRFixtures")
                .appendingPathComponent(name),
            encoding: .utf8
        )
    }

    private func parse(
        _ name: String, kind: DocumentKind, confidence: Double = 1.0, pages: Int = 1
    ) throws -> ParseResult {
        parseRecognisedText(try fixture(name), kind: kind, confidence: confidence, pages: pages)
    }

    /// The same parse, from text rather than from a file.
    ///
    /// Used where a test needs the *same* document with one line printed the way a different
    /// yard prints it. Retyping the whole invoice per spelling would leave five near-identical
    /// fixtures whose differences nobody could see; swapping the one line that differs keeps the
    /// document real and the difference legible.
    private func parseRecognisedText(
        _ text: String, kind: DocumentKind, confidence: Double = 1.0, pages: Int = 1
    ) -> ParseResult {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // Page attribution built from the fixture's own page marker, so a multipage fixture
        // exercises the page-tracking path rather than only the single-page one.
        var page = 0
        var linePages: [Int] = []
        for line in lines {
            if line.hasPrefix("--- PAGE") { page += 1 }
            linePages.append(page)
        }
        return DocumentTextParser.parse(
            RecognizedDocument(
                rawText: text,
                lines: lines,
                linePages: linePages,
                averageRecognitionConfidence: confidence,
                pageCount: pages
            ),
            kind: kind,
            calendar: calendar()
        )
    }

    // MARK: - The negative test

    /// §12.12. This is the document in the screenshot that produced a `Use 0 values` button.
    func testAResidentialLeaseYieldsNoRentalFields() throws {
        let result = try parse("unrelated_residential_lease.txt", kind: .rentalContract)

        // OCR read it. The extractor found nothing, which is the correct answer.
        XCTAssertFalse(result.rawText.isEmpty, "the text must still be recognised and kept")
        XCTAssertTrue(result.rawText.contains("QUIET ENJOYMENT"))

        for field in [
            SuggestedField.equipmentName, .equipmentIdentifier, .serialNumber,
            .dailyRate, .weeklyRate, .fourWeekRate, .agreementNumber,
        ] {
            XCTAssertNil(
                result.suggestion(for: field),
                "a residential lease produced a \(field.rawValue): \(String(describing: result.suggestion(for: field)?.value))"
            )
        }
    }

    /// And the review screen therefore shows the empty state rather than a count of zero.
    func testTheLeaseProducesTheNothingFoundOutcomeRatherThanUseZeroValues() throws {
        let result = try parse("unrelated_residential_lease.txt", kind: .rentalContract)
        let outcome = ScanOutcome.evaluate(suggestions: result.suggestions, kind: .rentalContract)
        XCTAssertEqual(outcome, .nothingFound)
        XCTAssertNil(ScanReviewCopy.useValues(selected: 0))
    }

    /// A lease has dates and a company-looking letterhead. Neither may become a rental term.
    func testTheLeaseDatesAreNotReadAsRentalDates() throws {
        let result = try parse("unrelated_residential_lease.txt", kind: .rentalContract)
        XCTAssertNil(result.suggestion(for: .startDate))
        XCTAssertNil(result.suggestion(for: .scheduledEndDate))
    }

    // MARK: - A third vendor layout, with labels and values on different lines

    func testATableWithDottedLeadersAndSplitLabelsStillYieldsTheRates() throws {
        let result = try parse("contract_split_labels.txt", kind: .rentalContract)

        XCTAssertEqual(result.suggestion(for: .dailyRate)?.value, .money(money("465.00")))
        XCTAssertEqual(result.suggestion(for: .weeklyRate)?.value, .money(money("1540.00")))
        XCTAssertEqual(result.suggestion(for: .fourWeekRate)?.value, .money(money("4180.00")))
    }

    func testTheSevenDayRateIsNeverReadAsADailyRate() throws {
        // The four-fold error the whole estimate rests on not making.
        let result = try parse("contract_split_labels.txt", kind: .rentalContract)
        XCTAssertNotEqual(result.suggestion(for: .dailyRate)?.value, .money(money("1540.00")))
        XCTAssertNotEqual(result.suggestion(for: .dailyRate)?.value, .money(money("4180.00")))
    }

    func testIdentifiersSurviveALayoutTheParserHasNotSeenBefore() throws {
        let result = try parse("contract_split_labels.txt", kind: .rentalContract)
        XCTAssertEqual(result.suggestion(for: .equipmentIdentifier)?.value, .text("TH-1180"))
        XCTAssertEqual(result.suggestion(for: .serialNumber)?.value, .text("TH55K0092214"))
        XCTAssertEqual(result.suggestion(for: .agreementNumber)?.value, .text("NG-77304"))
    }

    func testAMonthNameDateFormatParses() throws {
        let result = try parse("contract_split_labels.txt", kind: .rentalContract)
        XCTAssertNotNil(result.suggestion(for: .startDate)?.value.dateValue)
        XCTAssertNotNil(result.suggestion(for: .scheduledEndDate)?.value.dateValue)
    }

    func testASplitLayoutStillFindsEnoughToBeWorthOffering() throws {
        let result = try parse("contract_split_labels.txt", kind: .rentalContract)
        guard case let .found(count) = ScanOutcome.evaluate(
            suggestions: result.suggestions, kind: .rentalContract
        ) else {
            return XCTFail("a real rental agreement must produce usable fields")
        }
        XCTAssertGreaterThanOrEqual(count, 6, "found only \(count) fields on a full agreement")
        XCTAssertEqual(ScanReviewCopy.useValues(selected: count), "Use \(count) suggested values")
    }

    // MARK: - Multipage, with the OCR digit confusion

    func testAMultipageInvoiceReportsWhichPageEachValueCameFrom() throws {
        let result = try parse("invoice_multipage_ocr_noise.txt", kind: .vendorInvoice, pages: 2)

        let number = result.suggestion(for: .invoiceNumber)
        XCTAssertEqual(number?.value, .text("NG-90551"))
        XCTAssertEqual(number?.provenance.page, 0, "the invoice number is on the first page")

        let total = result.suggestion(for: .invoiceTotal)
        XCTAssertEqual(total?.provenance.page, 1, "the total is on the second page")
        XCTAssertEqual(total?.provenance.pageDescription(of: 2), "page 2")
    }

    func testAPageIsOnlyNamedWhenThereIsMoreThanOne() throws {
        let single = try parse("invoice_matching.txt", kind: .vendorInvoice)
        let suggestion = try XCTUnwrap(single.suggestion(for: .invoiceTotal))
        XCTAssertNil(suggestion.provenance.pageDescription(of: 1))
    }

    /// `4,18O.00` — a capital O where a zero belongs. The parser must not turn that into a
    /// confident 418.00, which would understate the rental charge by an order of magnitude.
    ///
    /// Asserted unconditionally, not inside an `if let`. A conditional assertion on an optional
    /// that turns out to be nil is a test that passes by not running, which is how the first
    /// version of this one reported success while the parser was reading 418.
    func testALetterOInAnAmountIsNotSilentlyReadAsADifferentNumber() throws {
        let result = try parse("invoice_multipage_ocr_noise.txt", kind: .vendorInvoice, pages: 2)
        let subtotal = result.suggestion(for: .rentalSubtotal)?.value.moneyValue
        XCTAssertNotEqual(
            subtotal, money("418.00"),
            "an OCR letter-O became a confident amount ten times too small"
        )
        XCTAssertNil(
            subtotal,
            "a garbled amount must be refused outright rather than truncated to a plausible one"
        )
    }

    /// The tax line has the same fault — `404.O2` — and must be refused for the same reason.
    func testAGarbledDecimalIsRefusedRatherThanTruncated() throws {
        let result = try parse("invoice_multipage_ocr_noise.txt", kind: .vendorInvoice, pages: 2)
        XCTAssertNotEqual(
            result.suggestion(for: .taxAmount)?.value.moneyValue, money("404.00"),
            "404.O2 was read as 404.00"
        )
    }

    /// And a clean amount at the end of a sentence is still read. The rejection rule is about
    /// letters inside a number, not about punctuation after one.
    func testACleanAmountFollowedByAFullStopStillParses() throws {
        let document = RecognizedDocument(rawText: "TOTAL DUE: $5,292.22.")
        let result = DocumentTextParser.parse(
            document, kind: .vendorInvoice, calendar: calendar()
        )
        XCTAssertEqual(result.suggestion(for: .invoiceTotal)?.value, .money(money("5292.22")))
    }

    func testTheChargeCategoriesOnPageTwoAreEachRecognised() throws {
        let result = try parse("invoice_multipage_ocr_noise.txt", kind: .vendorInvoice, pages: 2)
        XCTAssertEqual(result.suggestion(for: .deliveryCharge)?.value, .money(money("285.00")))
        XCTAssertEqual(result.suggestion(for: .pickupCharge)?.value, .money(money("285.00")))
        XCTAssertNotNil(result.suggestion(for: .environmentalCharge))
    }

    func testEveryProvenanceCarriesTheRangeOfTheValueInItsLine() throws {
        let result = try parse("contract_skidsteer_clean.txt", kind: .rentalContract)
        for suggestion in result.suggestions where suggestion.provenance.valueStart != nil {
            let provenance = suggestion.provenance
            let start = try XCTUnwrap(provenance.valueStart)
            let length = try XCTUnwrap(provenance.valueLength)
            let line = provenance.sourceLine as NSString
            XCTAssertGreaterThanOrEqual(start, 0, provenance.sourceLine)
            XCTAssertLessThanOrEqual(
                start + length, line.length,
                "the recorded range runs past the end of “\(provenance.sourceLine)”"
            )
        }
    }

    // MARK: - Low confidence

    func testAMarginalScanOfARealAgreementStillOffersItsValuesUnticked() throws {
        let result = try parse("contract_split_labels.txt", kind: .rentalContract, confidence: 0.55)
        XCTAssertFalse(result.suggestions.isEmpty, "a marginal scan is not a blank one")
        XCTAssertTrue(
            result.preselected.isEmpty,
            "a marginal scan must tick nothing: the user's job is to check, not to notice"
        )
        XCTAssertTrue(
            ScanOutcome.evaluate(suggestions: result.suggestions, kind: .rentalContract)
                .hasAnything,
            "and the screen must still offer them rather than claiming nothing was found"
        )
    }

    // MARK: - Real rental-yard paperwork

    // The two fixtures below were written from the layout US rental yards actually print —
    // a letterhead, a labelled block, an equipment table with column headings, a rate schedule
    // and a charge list. Running the parser over them found four defects that no amount of
    // reading the rules had shown, two of which were confidently wrong values.

    func testTheTaxLineYieldsTheAmountAndNotTheRate() throws {
        // `SALES TAX 8.25%  130.84` is one line with two numbers on it. The parser used to
        // report $8.25 — the rate — at 0.90 confidence, which is above `preselectThreshold`, so
        // it arrived already ticked. Accepting it would have understated the tax by $122.59 and
        // made the comparison flag a mismatch that was the app's own doing.
        let result = try parse("invoice_yard_realistic.txt", kind: .vendorInvoice)
        let tax = try XCTUnwrap(result.suggestions.first { $0.field == .taxAmount })
        XCTAssertEqual(
            tax.value.moneyValue, Decimal(string: "130.84", locale: Locale(identifier: "en_US_POSIX")),
            "the tax is the amount beside the rate, never the rate"
        )
    }

    func testAPercentageIsNeverReadAsAnAmountAnywhere() throws {
        let result = try parse("invoice_yard_realistic.txt", kind: .vendorInvoice)
        // `RPP (DAMAGE WAIVER) 12%  136.80` is the same shape as the tax line.
        let damage = try XCTUnwrap(result.suggestions.first { $0.field == .damageCharge })
        XCTAssertEqual(damage.value.moneyValue, Decimal(string: "136.80", locale: Locale(identifier: "en_US_POSIX")))
        for suggestion in result.suggestions {
            guard let amount = suggestion.value.moneyValue else { continue }
            XCTAssertNotEqual(
                amount, Decimal(string: "8.25", locale: Locale(identifier: "en_US_POSIX")),
                "\(suggestion.field) took the tax rate as an amount"
            )
            XCTAssertNotEqual(
                amount, Decimal(string: "12", locale: Locale(identifier: "en_US_POSIX")),
                "\(suggestion.field) took the waiver rate as an amount"
            )
        }
    }

    func testAColumnHeadingIsNeverReportedAsAValue() throws {
        // `QTY  EQUIPMENT  UNIT #  SERIAL` is a header row. The unit-number rule matched
        // `UNIT #` and took the next word, so the app reported this machine's identifier as
        // "SERIAL" at 0.90 confidence.
        let result = try parse("contract_yard_realistic.txt", kind: .rentalContract)
        for suggestion in result.suggestions {
            guard let text = suggestion.value.textValue else { continue }
            XCTAssertFalse(
                DocumentTextParser.columnHeadings.contains(text.uppercased()),
                "\(suggestion.field) was filled in with the column heading “\(text)”"
            )
        }
    }

    func testTheEquipmentTableYieldsTheMachineItsUnitNumberAndItsSerial() throws {
        // The machine is the one thing a contract never labels: it is a row under a header.
        // Before the table pass the app asked the user to type in the name of the machine they
        // had just photographed.
        let result = try parse("contract_yard_realistic.txt", kind: .rentalContract)
        func text(_ field: SuggestedField) throws -> String {
            try XCTUnwrap(
                result.suggestions.first { $0.field == field }?.value.textValue,
                "\(field) was not read from the equipment table"
            )
        }
        XCTAssertEqual(try text(.equipmentName), "CAT 259D3 SKID STEER TRACK LOADER")
        XCTAssertEqual(try text(.equipmentIdentifier), "SS-2214")
        XCTAssertEqual(try text(.serialNumber), "CAT0259DKTLM12345")
    }

    func testATableReadArrivesOfferedRatherThanTicked() throws {
        // A labelled field is the document saying what a value is. A table cell is the app
        // inferring it from a layout, and that inference should never be pre-accepted.
        let result = try parse("contract_yard_realistic.txt", kind: .rentalContract)
        for suggestion in result.suggestions
        where suggestion.provenance.rule == "equipment-table-column" {
            XCTAssertFalse(
                suggestion.isPreselected,
                "\(suggestion.field) was read from a layout and must not arrive ticked"
            )
        }
    }

    func testThePurchaseOrderNumberIsReadFromBothDocuments() throws {
        // The identifier a contractor's accounts department files by, and the one field they
        // used to type twice: the agreement has carried it since schema V3 and the form has
        // always offered it, but nothing could read it.
        let contract = try parse("contract_yard_realistic.txt", kind: .rentalContract)
        let invoice = try parse("invoice_yard_realistic.txt", kind: .vendorInvoice)
        for (result, name) in [(contract, "contract"), (invoice, "invoice")] {
            let po = try XCTUnwrap(
                result.suggestions.first { $0.field == .purchaseOrderNumber },
                "no PO number found on the \(name)"
            )
            XCTAssertEqual(po.value.textValue, "JOB-2291")
        }
    }

    func testTheChargesAYardActuallyPrintsAreAllFound() throws {
        let result = try parse("invoice_yard_realistic.txt", kind: .vendorInvoice)
        let byField = Dictionary(
            uniqueKeysWithValues: result.suggestions.map { ($0.field, $0.value.moneyValue) }
        )
        // `PICKUP / HAUL OUT` used to stop the match dead at the slash; `SUBTOTAL` printed on
        // its own was only matched as `RENTAL SUBTOTAL`.
        XCTAssertEqual(byField[.pickupCharge] ?? nil, Decimal(string: "125.00", locale: Locale(identifier: "en_US_POSIX")))
        XCTAssertEqual(byField[.deliveryCharge] ?? nil, Decimal(string: "125.00", locale: Locale(identifier: "en_US_POSIX")))
        XCTAssertEqual(byField[.fuelCharge] ?? nil, Decimal(string: "42.00", locale: Locale(identifier: "en_US_POSIX")))
        XCTAssertEqual(byField[.environmentalCharge] ?? nil, Decimal(string: "17.10", locale: Locale(identifier: "en_US_POSIX")))
        XCTAssertEqual(byField[.rentalSubtotal] ?? nil, Decimal(string: "1585.90", locale: Locale(identifier: "en_US_POSIX")))
        XCTAssertEqual(byField[.invoiceTotal] ?? nil, Decimal(string: "1716.74", locale: Locale(identifier: "en_US_POSIX")))
    }

    func testEstReturnIsReadAsTheScheduledEnd() throws {
        // `EST RETURN` is how it is printed; the rule only knew `estimated return`.
        let result = try parse("contract_yard_realistic.txt", kind: .rentalContract)
        XCTAssertNotNil(
            result.suggestions.first { $0.field == .scheduledEndDate }?.value.dateValue,
            "the date the machine is due back was not read"
        )
    }

    func testTheRealisticContractFillsMostOfTheForm() throws {
        // The owner's bar: "it should be able to fill out all the info it sees". This pins the
        // count so a rule change that quietly stops reading a field fails here.
        let result = try parse("contract_yard_realistic.txt", kind: .rentalContract)
        XCTAssertGreaterThanOrEqual(
            result.suggestions.count, 11,
            "the realistic contract should fill at least eleven fields, found "
            + "\(result.suggestions.map(\.field.rawValue).sorted().joined(separator: ", "))"
        )
    }

    func testARateWithNoAmountBesideItProducesNoCharge() throws {
        // The half of the percentage problem the widened gap does not solve.
        //
        // `FUEL SURCHARGE 10%` on its own line, with the amount elsewhere or not itemised at
        // all, used to become a $10.00 fuel charge — and `ENVIRONMENTAL FEE 3.5%` a $3.50 one —
        // both at 0.88 confidence, above `preselectThreshold`. Money the document never said,
        // pre-ticked, in the right place. The comparison would then flag a mismatch that was
        // the app's own invention.
        let result = try parse("invoice_rates_without_amounts.txt", kind: .vendorInvoice)
        XCTAssertNil(
            result.suggestions.first { $0.field == .fuelCharge },
            "a fuel rate of 10% is not a fuel charge of $10"
        )
        XCTAssertNil(
            result.suggestions.first { $0.field == .environmentalCharge },
            "an environmental rate of 3.5% is not a charge of $3.50"
        )
        // And the real total on the same document is still read, so this is a boundary and not
        // a blanket refusal to read a page with a percentage on it.
        XCTAssertEqual(
            result.suggestions.first { $0.field == .invoiceTotal }?.value.moneyValue,
            Decimal(string: "1200.00", locale: Locale(identifier: "en_US_POSIX"))
        )
    }

    func testARateTablePrintedOnOneLineYieldsAllThreeRates() throws {
        // `RENTAL RATE: DAY 285.00 WEEK 855.00 4WK 2280.00` is the most common way a US yard
        // prints its rates, and on it the app used to lose the daily rate entirely: the daily
        // rule excluded any line containing "week", and this line contains two. The one number
        // the whole running-cost estimate rests on, silently absent, on the commonest layout.
        //
        // The exclusion is scoped to the sixteen characters in front of each amount now, which
        // asks the question that was always meant — is *this* figure qualified by a period that
        // is not mine — rather than looking anywhere in the line.
        let result = try parse("contract_single_line_rate_table.txt", kind: .rentalContract)
        func money(_ field: SuggestedField) throws -> Decimal {
            try XCTUnwrap(
                result.suggestions.first { $0.field == field }?.value.moneyValue,
                "\(field) was not read from the single-line rate table"
            )
        }
        XCTAssertEqual(try money(.dailyRate), Decimal(string: "285.00", locale: Locale(identifier: "en_US_POSIX")))
        XCTAssertEqual(try money(.weeklyRate), Decimal(string: "855.00", locale: Locale(identifier: "en_US_POSIX")))
        XCTAssertEqual(try money(.fourWeekRate), Decimal(string: "2280.00", locale: Locale(identifier: "en_US_POSIX")))
    }

    func testADateAfterAChargeLabelIsNotAnAmount() throws {
        // `DELIVERY 05/04/26` is a label followed by a date. The fragment read `05` as five
        // dollars — plausible, in the right place, and above the threshold that pre-ticks it.
        let result = try parse("contract_single_line_rate_table.txt", kind: .rentalContract)
        XCTAssertNil(
            result.suggestions.first { $0.field == .deliveryCharge },
            "a delivery date is not a delivery charge"
        )
        for suggestion in result.suggestions {
            guard let amount = suggestion.value.moneyValue else { continue }
            XCTAssertNotEqual(
                amount, 5,
                "\(suggestion.field) took the day out of a date as an amount"
            )
        }
    }

    func testASevenDayRateIsStillNotADailyRate() throws {
        // The reason the exclusion exists at all, and the case the narrower scope must not lose:
        // a weekly figure labelled in days is a four-fold error on the estimate.
        let result = try parse("contract_single_line_rate_table.txt", kind: .rentalContract)
        let daily = try XCTUnwrap(result.suggestions.first { $0.field == .dailyRate }?.value.moneyValue)
        XCTAssertNotEqual(
            daily, Decimal(string: "985.00", locale: Locale(identifier: "en_US_POSIX")),
            "the 7 DAY RATE was read as the daily rate"
        )
    }

    // MARK: - The abbreviations rental paperwork actually prints

    // Three defects, all of the same shape: the parser knew the word and the paperwork prints
    // the abbreviation. Each one was a field that simply went missing on a real document, which
    // on a scanning app is indistinguishable from the scan having failed.

    /// `S/N` is how a serial number is written on every plate and nearly every ticket.
    func testASerialWrittenAsSlashNIsRead() throws {
        let result = try parse("contract_abbreviated_serial.txt", kind: .rentalContract)
        XCTAssertEqual(
            result.suggestion(for: .serialNumber)?.value, .text("4TNV88-1234"),
            "the serial is printed as `S/N 4TNV88-1234` and was not read at all"
        )
    }

    /// And the label is never swallowed into the value.
    func testTheSerialLabelIsNotCapturedAsPartOfTheSerial() throws {
        let result = try parse("contract_abbreviated_serial.txt", kind: .rentalContract)
        let serial = try XCTUnwrap(result.suggestion(for: .serialNumber)?.value.textValue)
        XCTAssertFalse(serial.uppercased().contains("S/N"), "the label became part of the value")
        XCTAssertFalse(serial.uppercased().hasPrefix("SN"), "the label became part of the value")
    }

    /// The same contract, with that one line printed the three ways yards print it.
    func testEveryWayAYardAbbreviatesASerialNumberIsRead() throws {
        let template = try fixture("contract_abbreviated_serial.txt")
        let printed: [(line: String, expected: String)] = [
            ("S/N 4TNV88-1234", "4TNV88-1234"),
            ("S/N: 4TNV88", "4TNV88"),
            ("SN 4TNV88", "4TNV88"),
        ]
        for (line, expected) in printed {
            let document = template.replacingOccurrences(of: "S/N 4TNV88-1234", with: line)
            XCTAssertTrue(document.contains(line), "the fixture no longer carries the serial line")
            let result = parseRecognisedText(document, kind: .rentalContract)
            XCTAssertEqual(
                result.suggestion(for: .serialNumber)?.value, .text(expected),
                "a serial printed as `\(line)` was not read"
            )
        }
    }

    /// The rest of the same contract, so the fixture is a document and not a serial-number
    /// delivery mechanism: if the parser stops reading any of this, that is a regression too.
    func testTheAbbreviatedSerialContractStillFillsTheRestOfTheForm() throws {
        let result = try parse("contract_abbreviated_serial.txt", kind: .rentalContract)
        XCTAssertEqual(result.suggestion(for: .agreementNumber)?.value, .text("BV-31408"))
        XCTAssertEqual(result.suggestion(for: .purchaseOrderNumber)?.value, .text("WO-55712"))
        XCTAssertEqual(result.suggestion(for: .equipmentIdentifier)?.value, .text("TB-0417"))
        XCTAssertEqual(
            result.suggestion(for: .equipmentName)?.value,
            .text("TAKEUCHI TB260 COMPACT EXCAVATOR")
        )
        XCTAssertEqual(result.suggestion(for: .dailyRate)?.value, .money(money("340.00")))
        XCTAssertEqual(result.suggestion(for: .weeklyRate)?.value, .money(money("1020.00")))
        XCTAssertEqual(result.suggestion(for: .fourWeekRate)?.value, .money(money("2720.00")))
        XCTAssertNotNil(result.suggestion(for: .startDate)?.value.dateValue)
        XCTAssertNotNil(result.suggestion(for: .scheduledEndDate)?.value.dateValue)
    }

    /// The damage waiver, billed as `RPP (14%) ....... 63.00`, which is a tenth of this invoice.
    func testTheWaiverAbbreviationIsReadAsTheDamageCharge() throws {
        let result = try parse("invoice_waiver_abbreviation.txt", kind: .vendorInvoice)
        XCTAssertEqual(
            result.suggestion(for: .damageCharge)?.value, .money(money("63.00")),
            "an `RPP` line item is the damage waiver and was not read as a charge at all"
        )
    }

    /// `RPP`, `DW`, `LDW`, `CDW` — four ways to bill one thing, all of them the same field.
    func testEveryWaiverAbbreviationMapsToTheDamageCharge() throws {
        let template = try fixture("invoice_waiver_abbreviation.txt")
        let printed: [(line: String, expected: String)] = [
            ("RPP (14%) ............................... 63.00", "63.00"),
            ("LDW ..................................... 63.00", "63.00"),
            ("CDW (14%) ............................... 63.00", "63.00"),
            ("DAMAGE WAIVER (DW) ...................... 63.00", "63.00"),
            ("LDW  87.50", "87.50"),
            ("DW  87.50", "87.50"),
        ]
        for (line, expected) in printed {
            let document = template.replacingOccurrences(
                of: "RPP (14%) ............................... 63.00", with: line
            )
            XCTAssertTrue(document.contains(line), "the fixture no longer carries the waiver line")
            let result = parseRecognisedText(document, kind: .vendorInvoice)
            XCTAssertEqual(
                result.suggestion(for: .damageCharge)?.value, .money(money(expected)),
                "a waiver billed as `\(line)` was not read as the damage charge"
            )
        }
    }

    /// The reason `DW` is matched as a token and not as a substring.
    ///
    /// This invoice bills `MIDWAY YARD RESTOCK ...... 18.00`, which contains the letters of
    /// `DW` in the middle of a word and is not a waiver. Taking the waiver line away must leave
    /// no damage charge at all — an $18 charge invented out of a restocking fee would arrive
    /// above the threshold that pre-ticks it, and the comparison would then flag a mismatch of
    /// the app's own making.
    func testATwoLetterWaiverCodeIsNotReadOutOfTheMiddleOfAWord() throws {
        let template = try fixture("invoice_waiver_abbreviation.txt")
        let withoutWaiver = template.replacingOccurrences(
            of: "RPP (14%) ............................... 63.00", with: ""
        )
        XCTAssertTrue(
            withoutWaiver.contains("MIDWAY YARD RESTOCK"),
            "the word carrying the letters of DW must still be on the page"
        )
        let result = parseRecognisedText(withoutWaiver, kind: .vendorInvoice)
        XCTAssertNil(
            result.suggestion(for: .damageCharge),
            "a restocking fee became a damage waiver because `DW` matched inside `MIDWAY`"
        )
    }

    /// `INVOICE NO 44821` — the separator word without the colon, which is how most of them
    /// print. The number the contractor files the document under used to be missing entirely.
    func testAnInvoiceNumberWithoutAColonIsRead() throws {
        let result = try parse("invoice_waiver_abbreviation.txt", kind: .vendorInvoice)
        XCTAssertEqual(result.suggestion(for: .invoiceNumber)?.value, .text("44821"))
    }

    func testTheThreeUncolonedInvoiceNumberFormsAllParse() throws {
        let template = try fixture("invoice_waiver_abbreviation.txt")
        for line in ["INVOICE NO 44821", "INVOICE NO. 44821", "INVOICE # 44821"] {
            let document = template.replacingOccurrences(of: "INVOICE NO 44821", with: line)
            XCTAssertTrue(document.contains(line), "the fixture no longer carries the header line")
            let result = parseRecognisedText(document, kind: .vendorInvoice)
            XCTAssertEqual(
                result.suggestion(for: .invoiceNumber)?.value, .text("44821"),
                "an invoice numbered `\(line)` was not read"
            )
        }
    }

    /// A date is not a number. `INVOICE DATE 07/06/26` sits two lines below the header on this
    /// fixture, and the looser header rule must not read the day out of it.
    func testTheInvoiceDateLineIsNotReadAsTheInvoiceNumber() throws {
        let result = try parse("invoice_waiver_abbreviation.txt", kind: .vendorInvoice)
        let number = try XCTUnwrap(result.suggestion(for: .invoiceNumber)?.value.textValue)
        XCTAssertFalse(number.contains("/"), "the invoice date was filed as the invoice number")
    }

    /// And the rest of that invoice, for the same reason as the contract above.
    func testTheWaiverInvoiceStillReadsItsOtherCharges() throws {
        let result = try parse("invoice_waiver_abbreviation.txt", kind: .vendorInvoice)
        XCTAssertEqual(result.suggestion(for: .deliveryCharge)?.value, .money(money("110.00")))
        XCTAssertEqual(result.suggestion(for: .pickupCharge)?.value, .money(money("110.00")))
        XCTAssertEqual(result.suggestion(for: .environmentalCharge)?.value, .money(money("9.90")))
        XCTAssertEqual(result.suggestion(for: .rentalSubtotal)?.value, .money(money("760.90")))
        XCTAssertEqual(result.suggestion(for: .taxAmount)?.value, .money(money("65.44")))
        XCTAssertEqual(result.suggestion(for: .invoiceTotal)?.value, .money(money("826.34")))
        XCTAssertEqual(result.suggestion(for: .agreementNumber)?.value, .text("CS-20714"))
        XCTAssertEqual(result.suggestion(for: .purchaseOrderNumber)?.value, .text("PO-8830"))
    }

    /// The waiver rate is not the waiver charge — the same trap the tax line set.
    func testTheWaiverRateIsNeverReadAsTheWaiverAmount() throws {
        let result = try parse("invoice_waiver_abbreviation.txt", kind: .vendorInvoice)
        for suggestion in result.suggestions {
            guard let amount = suggestion.value.moneyValue else { continue }
            XCTAssertNotEqual(
                amount, Decimal(string: "14", locale: Locale(identifier: "en_US_POSIX")),
                "\(suggestion.field) took the waiver rate as an amount"
            )
        }
    }
}
