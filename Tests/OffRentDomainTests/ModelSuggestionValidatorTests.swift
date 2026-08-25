import Foundation
import XCTest
@testable import OffRentDomain

/// The guardrail between a language model and a contractor's rental record.
///
/// Every test here is a way the model could be wrong. The point of the type under test is that
/// none of those ways reaches the store, and that the app never has to say "the model thought".
final class ModelSuggestionValidatorTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// A rate table: labels on one row, figures on the next. This is the case the rule parser
    /// cannot do and the model can, and it is why any of this exists.
    private var tableDocument: RecognizedDocument {
        RecognizedDocument(
            rawText: """
                CEDAR RIDGE EQUIPMENT RENTAL
                AGREEMENT 44-118392
                SKID STEER LOADER 75HP CLOSED CAB
                DAILY        WEEKLY       4-WEEK
                285.00       1,140.00     3,420.00
                DELIVERED 05/04/2026
                """,
            averageRecognitionConfidence: 0.92
        )
    }

    private func validate(_ proposals: [ProposedField], existing: [FieldSuggestion] = []) -> [FieldSuggestion] {
        ModelSuggestionValidator.validate(
            proposals, against: tableDocument, existing: existing, calendar: calendar
        )
    }

    // MARK: - What it lets through

    func testAFigureReadOutOfARateTableIsAccepted() {
        let accepted = validate([
            ProposedField(field: "dailyRate", value: "285.00", sourceLine: "285.00       1,140.00     3,420.00"),
        ])
        XCTAssertEqual(accepted.count, 1)
        XCTAssertEqual(accepted.first?.field, .dailyRate)
        XCTAssertEqual(accepted.first?.value, .money(money("285.00")))
        XCTAssertEqual(accepted.first?.provenance.rule, "on-device model")
    }

    func testTheQuotedLineIsRecordedSoTheUserCanSeeWhereItCameFrom() {
        let accepted = validate([
            ProposedField(field: "weeklyRate", value: "1,140.00", sourceLine: "285.00 1,140.00 3,420.00"),
        ])
        XCTAssertEqual(accepted.first?.provenance.sourceLine, "285.00       1,140.00     3,420.00")
        XCTAssertEqual(accepted.first?.provenance.lineIndex, 4)
    }

    func testTextAndDateFieldsParseIntoTheirOwnKinds() {
        let accepted = validate([
            ProposedField(field: "agreementNumber", value: "44-118392", sourceLine: "AGREEMENT 44-118392"),
            ProposedField(field: "startDate", value: "05/04/2026", sourceLine: "DELIVERED 05/04/2026"),
        ])
        XCTAssertEqual(accepted.count, 2)
        XCTAssertEqual(accepted.first(where: { $0.field == .agreementNumber })?.value, .text("44-118392"))
        XCTAssertNotNil(accepted.first(where: { $0.field == .startDate })?.value.dateValue)
    }

    // MARK: - What it throws away

    /// The failure that matters. A fluent, plausible number that is not on the page.
    func testAValueThatIsNotOnThePageIsDropped() {
        let accepted = validate([
            ProposedField(field: "dailyRate", value: "295.00", sourceLine: "285.00 1,140.00 3,420.00"),
        ])
        XCTAssertTrue(accepted.isEmpty, "a figure nobody printed must never become a suggestion")
    }

    func testAQuotedLineThatIsNotInTheDocumentIsDropped() {
        let accepted = validate([
            ProposedField(field: "dailyRate", value: "285.00", sourceLine: "RATE SCHEDULE B"),
        ])
        XCTAssertTrue(accepted.isEmpty)
    }

    func testAnUnknownFieldNameIsDropped() {
        let accepted = validate([
            ProposedField(field: "operatorName", value: "285.00", sourceLine: "285.00 1,140.00 3,420.00"),
        ])
        XCTAssertTrue(accepted.isEmpty)
    }

    func testAValueThatWillNotParseAsItsTypeIsDropped() {
        let accepted = validate([
            ProposedField(field: "dailyRate", value: "SKID", sourceLine: "SKID STEER LOADER 75HP CLOSED CAB"),
            ProposedField(field: "startDate", value: "CEDAR", sourceLine: "CEDAR RIDGE EQUIPMENT RENTAL"),
        ])
        XCTAssertTrue(accepted.isEmpty)
    }

    func testAWholeSentenceIsNotATextField() {
        let accepted = validate([
            ProposedField(
                field: "vendorName",
                value: String(repeating: "CEDAR RIDGE EQUIPMENT RENTAL ", count: 8),
                sourceLine: "CEDAR RIDGE EQUIPMENT RENTAL"
            ),
        ])
        XCTAssertTrue(accepted.isEmpty)
    }

    func testAnEmptyValueIsDropped() {
        XCTAssertTrue(validate([
            ProposedField(field: "dailyRate", value: "   ", sourceLine: "285.00 1,140.00 3,420.00"),
        ]).isEmpty)
    }

    // MARK: - The rule parser is the floor

    func testARuleBasedSuggestionAlwaysWins() {
        let existing = FieldSuggestion(
            field: .dailyRate,
            value: .money(money("285.00")),
            confidence: 0.95,
            provenance: SuggestionProvenance(
                sourceLine: "RENTAL RATE 285.00/DAY", lineIndex: 0,
                rule: "dailyRate.explicit", recognitionConfidence: 0.95
            )
        )
        let accepted = validate(
            [ProposedField(field: "dailyRate", value: "1,140.00", sourceLine: "285.00 1,140.00 3,420.00")],
            existing: [existing]
        )
        XCTAssertTrue(
            accepted.isEmpty,
            "where the two disagree the app keeps the one whose reasoning it can print"
        )
    }

    func testTheSameFieldProposedTwiceIsOnlyTakenOnce() {
        let accepted = validate([
            ProposedField(field: "dailyRate", value: "285.00", sourceLine: "285.00 1,140.00 3,420.00"),
            ProposedField(field: "dailyRate", value: "1,140.00", sourceLine: "285.00 1,140.00 3,420.00"),
        ])
        XCTAssertEqual(accepted.count, 1)
        XCTAssertEqual(accepted.first?.value, .money(money("285.00")))
    }

    // MARK: - Nothing from a model arrives ticked

    func testAModelSuggestionIsNeverPreselected() {
        let accepted = validate([
            ProposedField(field: "dailyRate", value: "285.00", sourceLine: "285.00 1,140.00 3,420.00"),
        ])
        XCTAssertFalse(
            accepted.first?.isPreselected ?? true,
            "the user has to tick anything a model proposed, whatever its confidence"
        )
        XCTAssertLessThan(
            ModelSuggestionValidator.maximumConfidence, FieldSuggestion.preselectThreshold,
            "the cap has to stay below the threshold or rule 5 stops holding by construction"
        )
    }

    // MARK: - Normalisation

    func testTypographicQuotesAndDashesDoNotDefeatTheMatch() {
        let document = RecognizedDocument(rawText: "TERM \u{2014} 4 WEEK \u{2018}A\u{2019} RATE 3,420.00")
        let accepted = ModelSuggestionValidator.validate(
            [ProposedField(field: "fourWeekRate", value: "3,420.00", sourceLine: "TERM - 4 WEEK 'A' RATE 3,420.00")],
            against: document, existing: [], calendar: calendar
        )
        XCTAssertEqual(accepted.count, 1)
    }

    // MARK: - A quotation is not the page stating something

    /// A rental agreement whose conditions paragraph quotes figures that are not the deal.
    private var documentWithQuotedConditions: RecognizedDocument {
        RecognizedDocument(
            rawText: """
                CEDAR RIDGE EQUIPMENT RENTAL
                AGREEMENT 44-118392
                SKID STEER LOADER 75HP CLOSED CAB
                DAILY        WEEKLY       4-WEEK
                285.00       1,140.00     3,420.00
                DELIVERED 05/04/2026
                CONDITIONS: THE "MINIMUM RENTAL" IS ONE DAY. A RATE SHOWN AS "450.00" IN
                SCHEDULE B APPLIES TO ATTACHMENTS ORDERED SEPARATELY AND IS NOT CHARGED HERE.
                """,
            averageRecognitionConfidence: 0.92
        )
    }

    func testAFigureThatAppearsOnlyInsideQuotationMarksIsDropped() {
        let accepted = ModelSuggestionValidator.validate(
            [ProposedField(
                field: "dailyRate",
                value: "450.00",
                sourceLine: #"CONDITIONS: THE "MINIMUM RENTAL" IS ONE DAY. A RATE SHOWN AS "450.00" IN"#
            )],
            against: documentWithQuotedConditions, existing: [], calendar: calendar
        )
        XCTAssertTrue(
            accepted.isEmpty,
            "a rate the conditions merely quote is not a rate the document charges"
        )
    }

    /// And the same document's real rate is still read, so this is a boundary rather than a
    /// refusal to validate anything on a page that contains a quotation mark.
    func testTheRealRateOnAPageThatQuotesAnotherOneIsStillAccepted() {
        let accepted = ModelSuggestionValidator.validate(
            [ProposedField(
                field: "dailyRate", value: "285.00",
                sourceLine: "285.00       1,140.00     3,420.00"
            )],
            against: documentWithQuotedConditions, existing: [], calendar: calendar
        )
        XCTAssertEqual(accepted.first?.value, .money(money("285.00")))
    }

    /// An unpaired mark is an inches sign, not the start of a quotation.
    ///
    /// Treating it as one would blank the rest of the document, and every value below it would
    /// be dropped as "not on the page" — a scan that silently found nothing on paperwork that
    /// mentions a 48" fork.
    func testAStrayInchesMarkDoesNotBlankTheRestOfThePage() {
        let document = RecognizedDocument(
            rawText: """
                CANYON STATE EQUIPMENT CO.
                FORK EXTENSIONS 48" PAIR
                DELIVERY                          120.00
                """,
            averageRecognitionConfidence: 0.95
        )
        let accepted = ModelSuggestionValidator.validate(
            [ProposedField(
                field: "deliveryCharge", value: "120.00",
                sourceLine: "DELIVERY                          120.00"
            )],
            against: document, existing: [], calendar: calendar
        )
        XCTAssertEqual(accepted.first?.value, .money(money("120.00")))
    }

    // MARK: - A value has to start and end where a value does

    private var chargeDocument: RecognizedDocument {
        RecognizedDocument(
            rawText: """
                CANYON STATE EQUIPMENT CO.
                INVOICE 44821
                ENVIRONMENTAL FEE                   9.90
                DELIVERY                          120.00
                TOTAL DUE                         129.90
                """,
            averageRecognitionConfidence: 0.95
        )
    }

    /// The substring hole. "12" is inside "120.00", so the old check said the page had stated it.
    func testANumberIsNotValidatedByALongerNumberThatMerelyContainsIt() {
        let accepted = ModelSuggestionValidator.validate(
            [ProposedField(
                field: "deliveryCharge", value: "12",
                sourceLine: "DELIVERY                          120.00"
            )],
            against: chargeDocument, existing: [], calendar: calendar
        )
        XCTAssertTrue(
            accepted.isEmpty,
            "a $12 charge was validated by a line that reads $120.00 — a tenth of the figure, "
            + "carrying the page's authority"
        )
    }

    /// The head of a number is no better than its tail.
    func testTheTailOfALongerNumberIsNotAValueEither() {
        let accepted = ModelSuggestionValidator.validate(
            [ProposedField(
                field: "environmentalCharge", value: "9",
                sourceLine: "ENVIRONMENTAL FEE                   9.90"
            )],
            against: chargeDocument, existing: [], calendar: calendar
        )
        XCTAssertTrue(accepted.isEmpty)
    }

    /// The whole figure from the very same line is still accepted.
    func testTheWholeFigureOnThatLineIsStillAccepted() {
        let accepted = ModelSuggestionValidator.validate(
            [ProposedField(
                field: "deliveryCharge", value: "120.00",
                sourceLine: "DELIVERY                          120.00"
            )],
            against: chargeDocument, existing: [], calendar: calendar
        )
        XCTAssertEqual(accepted.first?.value, .money(money("120.00")))
    }

    /// Identifiers have the same failure mode as amounts.
    func testAFragmentOfAnAgreementNumberIsNotValidatedByTheWholeOne() {
        let accepted = validate([
            ProposedField(field: "agreementNumber", value: "118392", sourceLine: "AGREEMENT 44-118392"),
        ])
        XCTAssertTrue(
            accepted.isEmpty,
            "half an agreement number is a different agreement number"
        )
    }

    /// And a hyphen inside a value the page really prints does not stop it being found.
    func testAHyphenatedIdentifierIsStillFoundWhole() {
        let accepted = validate([
            ProposedField(field: "agreementNumber", value: "44-118392", sourceLine: "AGREEMENT 44-118392"),
        ])
        XCTAssertEqual(accepted.first?.value, .text("44-118392"))
    }

    /// Punctuation after a value is punctuation, not more value. A full stop that ends a sentence
    /// must not make the figure in front of it unfindable.
    func testAFigureFollowedByAFullStopIsStillOnThePage() {
        let document = RecognizedDocument(
            rawText: "AMOUNT DUE ON RECEIPT IS 129.90. NO RETAINAGE APPLIES.",
            averageRecognitionConfidence: 0.95
        )
        let accepted = ModelSuggestionValidator.validate(
            [ProposedField(
                field: "invoiceTotal", value: "129.90",
                sourceLine: "AMOUNT DUE ON RECEIPT IS 129.90. NO RETAINAGE APPLIES."
            )],
            against: document, existing: [], calendar: calendar
        )
        XCTAssertEqual(accepted.first?.value, .money(money("129.90")))
    }

    // MARK: - Rates are not amounts

    private var waiverDocument: RecognizedDocument {
        RecognizedDocument(
            rawText: """
                CANYON STATE EQUIPMENT CO.
                INVOICE 44822
                RENTAL SUBTOTAL                   990.00
                RPP (12%)                         118.80
                TOTAL DUE                       1,108.80
                """,
            averageRecognitionConfidence: 0.95
        )
    }

    /// A percentage is a rate the vendor quoted, not a figure it billed.
    ///
    /// No field this validator accepts is a percentage, so a number printed with a percent sign
    /// after it can never be the value. Before the guard, `%` looked like a clean right-hand
    /// boundary — it is neither alphanumeric nor one of the separators — so `12` read straight out
    /// of `RPP (12%)` was accepted as a damage charge of twelve dollars.
    func testAPercentageIsNotValidatedAsAnAmount() {
        let accepted = ModelSuggestionValidator.validate(
            [ProposedField(
                field: "damageCharge", value: "12",
                sourceLine: "RPP (12%)                         118.80"
            )],
            against: waiverDocument, existing: [], calendar: calendar
        )
        XCTAssertTrue(
            accepted.isEmpty,
            "a $12 damage charge was validated by the 12% rate the waiver is calculated at"
        )
    }

    /// A space between the figure and the sign changes nothing.
    func testAPercentageWithASpaceBeforeTheSignIsStillARate() {
        let spaced = RecognizedDocument(
            rawText: """
                RENTAL PROTECTION PLAN AT 14 %    138.60
                """,
            averageRecognitionConfidence: 0.95
        )
        let accepted = ModelSuggestionValidator.validate(
            [ProposedField(
                field: "damageCharge", value: "14",
                sourceLine: "RENTAL PROTECTION PLAN AT 14 %    138.60"
            )],
            against: spaced, existing: [], calendar: calendar
        )
        XCTAssertTrue(accepted.isEmpty)
    }

    /// The amount on the same line is still the amount.
    func testTheWaiverAmountOnThatLineIsStillAccepted() {
        let accepted = ModelSuggestionValidator.validate(
            [ProposedField(
                field: "damageCharge", value: "118.80",
                sourceLine: "RPP (12%)                         118.80"
            )],
            against: waiverDocument, existing: [], calendar: calendar
        )
        XCTAssertEqual(accepted.first?.value, .money(money("118.80")))
    }

    /// An inches mark is not a quotation mark.
    ///
    /// A yard's paperwork carries several — `48" FORKS`, `36" BUCKET` — and two of them used to
    /// count as a matched quotation pair, blanking everything printed between them out of the
    /// check. A correct model suggestion reading a figure from that span was then rejected as not
    /// being on the page at all.
    func testTwoInchesMarksDoNotBlankTheDocumentBetweenThem() {
        let document = RecognizedDocument(
            rawText: """
                48" PALLET FORKS                    UNIT # PF-118
                DELIVERY                          120.00
                36" GRADING BUCKET                  UNIT # GB-204
                """,
            averageRecognitionConfidence: 0.95
        )
        let accepted = ModelSuggestionValidator.validate(
            [ProposedField(
                field: "deliveryCharge", value: "120.00",
                sourceLine: "DELIVERY                          120.00"
            )],
            against: document, existing: [], calendar: calendar
        )
        XCTAssertEqual(
            accepted.count, 1,
            "the delivery charge is printed between two inches marks, not inside a quotation"
        )
    }

    /// A real quoted span is still removed.
    func testAGenuinelyQuotedFigureIsStillNotEvidence() {
        let document = RecognizedDocument(
            rawText: """
                CONDITIONS: the "standard delivery charge of 120.00" applies unless agreed.
                """,
            averageRecognitionConfidence: 0.95
        )
        let accepted = ModelSuggestionValidator.validate(
            [ProposedField(
                field: "deliveryCharge", value: "120.00",
                sourceLine: "CONDITIONS: the \"standard delivery charge of 120.00\" applies unless agreed."
            )],
            against: document, existing: [], calendar: calendar
        )
        XCTAssertTrue(accepted.isEmpty)
    }
}
