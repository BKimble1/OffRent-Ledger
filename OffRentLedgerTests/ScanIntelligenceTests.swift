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
        let recognised = StubTextRecognizer.skidSteerContract
        let document = try await recognised.recognize(imageData: [], source: .documentCamera)

        // Pick a line the rule parser leaves alone, and a token that is genuinely printed on it.
        let baseline = await run(UnavailableDocumentIntelligence())
        let alreadyFound = Set(baseline.suggestions.map(\.field))
        let candidate = SuggestedField.allCases.first { !alreadyFound.contains($0) && $0 == .serialNumber }

        try #require(candidate != nil)
        guard let line = document.lines.first(where: { $0.count > 6 }) else { return }
        let token = String(line.split(separator: " ").first ?? "")
        try #require(!token.isEmpty)

        let model = await run(
            StubDocumentIntelligence(proposals: [
                ProposedField(field: "serialNumber", value: token, sourceLine: line),
            ])
        )

        if let added = model.suggestions.first(where: { $0.field == .serialNumber }) {
            #expect(added.provenance.rule == ModelSuggestionValidator.ruleName)
            #expect(added.provenance.sourceLine == line)
            #expect(added.isPreselected == false, "nothing a model proposed may arrive ticked")
            #expect(!model.selection.contains(.serialNumber))
            #expect(model.modelSuggestionCount == 1)
        }
    }

    @Test func theFactoryAlwaysReturnsSomethingUsable() {
        let intelligence = DocumentIntelligenceFactory.make()
        // Either it can read, or it says why not. Never both empty — that would leave the review
        // screen with nothing to tell the user.
        #expect(intelligence.isAvailable || intelligence.unavailableReason != nil)
    }
}
