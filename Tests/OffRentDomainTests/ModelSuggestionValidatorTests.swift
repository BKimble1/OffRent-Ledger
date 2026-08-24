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
}
