import Foundation
import Testing
@testable import OffRentLedger

/// The on-device model, plumbed in.
///
/// The validator itself is covered exhaustively in the portable suite. What these check is the
/// wiring: that a proposal reaches the review screen as an unticked suggestion, that a fabricated
/// one does not reach it at all, and that a device with no model behaves exactly as the app did
/// before there was one.
@MainActor
struct ScanIntelligenceTests {

    private func makeModel(_ intelligence: any DocumentIntelligence) -> ScanReviewViewModel {
        ScanReviewViewModel(
            kind: .rentalContract,
            recognizer: StubTextRecognizer.skidSteerContract,
            calendar: FixedClock(2026, 5, 9, 10).calendar,
            intelligence: intelligence
        )
    }

    private func run(_ intelligence: any DocumentIntelligence) async -> ScanReviewViewModel {
        let model = makeModel(intelligence)
        model.recognise(imageData: [], source: .documentCamera)
        await model.awaitPendingWork()
        return model
    }

    @Test func withNoModelTheScreenIsExactlyWhatTheRuleParserProduced() async {
        let model = await run(UnavailableDocumentIntelligence(unavailableReason: "No model here."))
        #expect(model.phase == .reviewing)
        #expect(model.modelSuggestionCount == 0)
        #expect(model.intelligenceIsAvailable == false)
        #expect(model.intelligenceUnavailableReason == "No model here.")
        #expect(model.suggestions.allSatisfy { $0.provenance.rule != ModelSuggestionValidator.ruleName })
    }

    /// The failure that must never reach a rental record: a fluent figure nobody printed.
    @Test func aFabricatedValueNeverBecomesASuggestion() async {
        let model = await run(
            StubDocumentIntelligence(proposals: [
                ProposedField(
                    field: "dailyRate",
                    value: "999999.00",
                    sourceLine: "A LINE THAT IS NOT ON THIS PAGE"
                ),
            ])
        )
        #expect(model.phase == .reviewing)
        #expect(model.modelSuggestionCount == 0)
        #expect(!model.suggestions.contains { $0.value.moneyValue == Decimal(999_999) })
    }

    /// A value that really is on the page arrives — and arrives unticked, whatever else happens.
    @Test func aValueThatIsOnThePageArrivesUntickedWithItsSourceLine() async throws {
        let document = try await StubTextRecognizer.skidSteerContract
            .recognize(imageData: [], source: .documentCamera)

        // The field has to be one the rule parser did *not* claim on this fixture, or rule 4
        // correctly discards the proposal and the test proves nothing. Chosen by asking the
        // parser rather than by picking one and hoping — which is how the first version of this
        // failed: it named `serialNumber`, which the parser finds on this very contract.
        let baseline = await run(UnavailableDocumentIntelligence())
        let alreadyFound = Set(baseline.suggestions.map(\.field))
        let textFields: [SuggestedField] = [
            .serialNumber, .equipmentIdentifier, .invoiceNumber, .agreementNumber,
        ]
        let candidate = try #require(
            textFields.first { !alreadyFound.contains($0) },
            "the parser claimed every text field; pick a fixture it does not read completely"
        )

        // A token that is genuinely printed, on a line that is genuinely in the document.
        let line = try #require(document.lines.first { $0.split(separator: " ").count > 1 })
        let token = String(line.split(separator: " ")[0])
        try #require(!token.isEmpty)

        let model = await run(
            StubDocumentIntelligence(proposals: [
                ProposedField(field: candidate.rawValue, value: token, sourceLine: line),
            ])
        )

        let added = try #require(
            model.suggestions.first { $0.field == candidate },
            "a value printed on the page, quoted from a real line, must survive validation"
        )
        #expect(added.provenance.rule == ModelSuggestionValidator.ruleName)
        #expect(added.provenance.sourceLine == line)
        #expect(added.isPreselected == false, "nothing a model proposed may arrive ticked")
        #expect(!model.selection.contains(candidate))
        #expect(model.modelSuggestionCount == 1)
    }

    @Test func theFactoryAlwaysReturnsSomethingUsable() {
        let intelligence = DocumentIntelligenceFactory.make()
        // Either it can read, or it says why not. Never both empty — that would leave the review
        // screen with nothing to tell the user.
        #expect(intelligence.isAvailable || intelligence.unavailableReason != nil)
    }
}
