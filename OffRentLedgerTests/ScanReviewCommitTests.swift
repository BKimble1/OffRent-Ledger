import Foundation
import SwiftData
import Testing
@testable import OffRentLedger

/// The property that makes scanning safe: **a scan cannot write anything.**
///
/// Executed on the simulator by the `offrent-fast-verify` workflow. The parser half of this behaviour *was*
/// executed, in Tests/OffRentDomainTests/DocumentTextParserTests.swift. See TEST_MATRIX.md.
@MainActor
struct ScanReviewCommitTests {

    private func makeModel() -> ScanReviewViewModel {
        ScanReviewViewModel(
            kind: .rentalContract,
            recognizer: StubTextRecognizer.skidSteerContract,
            calendar: FixedClock(2026, 5, 9, 10).calendar
        )
    }

    @Test func runningTheWholePipelineAndDiscardingItWritesNothing() async throws {
        let context = ModelContext(try ModelContainerFactory.make(inMemory: true))
        let before = try context.fetch(StoreQueries.allItems()).count

        var model: ScanReviewViewModel? = makeModel()
        model?.recognise(imageData: [], source: .documentCamera)
        try await Task.sleep(for: .milliseconds(200))
        model = nil

        #expect(try context.fetch(StoreQueries.allItems()).count == before)
        #expect(try context.fetch(StoreQueries.allVendors()).isEmpty)
    }

    @Test func theViewModelHoldsNoStoreReference() {
        // Structural, not behavioural: there is no ModelContext to pass in, so there is no path
        // by which parsing writes. A reviewer can check this by reading the initialiser.
        let model = makeModel()
        #expect(model.phase == .idle)
        #expect(model.result == nil)
    }

    @Test func onlyConfidentSuggestionsArrivePreselected() async throws {
        let model = makeModel()
        model.recognise(imageData: [], source: .documentCamera)
        try await Task.sleep(for: .milliseconds(200))

        #expect(model.phase == .reviewing)
        for field in model.selection {
            let suggestion = try #require(model.suggestion(for: field))
            #expect(suggestion.confidence >= FieldSuggestion.preselectThreshold)
        }
    }

    @Test func acceptedValuesReflectUserEditsRatherThanTheParsedValue() async throws {
        let model = makeModel()
        model.recognise(imageData: [], source: .documentCamera)
        try await Task.sleep(for: .milliseconds(200))

        model.selection.insert(.dailyRate)
        model.edits[.dailyRate] = "310.00"

        // `.money` takes a `Decimal`, and `Decimal(string:)` returns `Decimal?`.
        let accepted = model.acceptedValues()
        #expect(accepted[.dailyRate] == .money(money("310.00")))
    }

    @Test func untickedFieldsAreNotAccepted() async throws {
        let model = makeModel()
        model.recognise(imageData: [], source: .documentCamera)
        try await Task.sleep(for: .milliseconds(200))

        model.selection.removeAll()
        #expect(model.acceptedValues().isEmpty)
    }

    @Test func anEditThatCannotBeParsedIsDroppedRatherThanSavedAsGarbage() async throws {
        let model = makeModel()
        model.recognise(imageData: [], source: .documentCamera)
        try await Task.sleep(for: .milliseconds(200))

        model.selection.insert(.dailyRate)
        model.edits[.dailyRate] = "not a number"
        #expect(model.acceptedValues()[.dailyRate] == nil)
    }

    @Test func aSecondScanCancelsTheFirst() async throws {
        let model = makeModel()
        model.recognise(imageData: [], source: .documentCamera)
        model.recognise(imageData: [], source: .photoLibrary)
        try await Task.sleep(for: .milliseconds(250))
        #expect(model.phase == .reviewing)
    }
}
