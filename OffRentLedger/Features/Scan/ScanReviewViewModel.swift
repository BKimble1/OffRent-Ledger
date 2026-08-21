import Foundation
import Observation
import SwiftUI

/// Holds the state of a scan review.
///
/// The important property of this type is what it *cannot* do: it has no `ModelContext`, no store
/// and no file handle. Scanning, recognising and parsing all happen here, and none of them can
/// write anything. The only way a scan reaches the store is `acceptedValues()`, which the Save
/// button calls and nothing else does.
///
/// `ScanReviewCommitTests` asserts that running the whole pipeline and discarding this object
/// leaves the store untouched.
@MainActor
@Observable
final class ScanReviewViewModel {

    enum Phase: Equatable {
        case idle
        case recognising
        case reviewing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var result: ParseResult?
    private(set) var document: RecognizedDocument?

    /// Which suggestions the user has ticked. Seeded from `isPreselected`, then owned entirely by
    /// the user.
    var selection: Set<SuggestedField> = []
    /// Edited values, keyed by field. A value the user typed always wins over the parsed one.
    var edits: [SuggestedField: String] = [:]
    var showRawText = false

    let kind: DocumentKind
    private let recognizer: any DocumentTextRecognizing
    private let calendar: Calendar

    /// `@ObservationIgnored` because the in-flight task is not UI state — and, more to the point,
    /// because `@Observable` turns an unmarked stored property into a computed one, which cannot
    /// be touched from a `deinit` on a `@MainActor` type.
    @ObservationIgnored private var task: Task<Void, Never>?

    init(kind: DocumentKind, recognizer: any DocumentTextRecognizing, calendar: Calendar) {
        self.kind = kind
        self.recognizer = recognizer
        self.calendar = calendar
    }

    // No `deinit { task?.cancel() }`. `deinit` is nonisolated, this type is `@MainActor`, and
    // reaching isolated state from there does not compile. `ScanReviewView` cancels in
    // `.onDisappear`, which is also the moment that actually matters: the sheet closing.

    // MARK: - Pipeline

    func recognise(imageData: [Data], source: DocumentSource) {
        run { [recognizer] in try await recognizer.recognize(imageData: imageData, source: source) }
    }

    func recognise(pdf data: Data) {
        run { [recognizer] in try await recognizer.recognize(pdf: data) }
    }

    private func run(_ work: @escaping @Sendable () async throws -> RecognizedDocument) {
        // A second scan cancels the first rather than racing it. Abandoned OCR on a ten-page PDF
        // is minutes of CPU the user is no longer waiting for.
        task?.cancel()
        phase = .recognising
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let document = try await work()
                try Task.checkCancellation()
                let parsed = DocumentTextParser.parse(
                    document, kind: self.kind, calendar: self.calendar
                )
                self.document = document
                self.result = parsed
                // Only the confident ones arrive ticked. Everything else is visible but off.
                self.selection = Set(parsed.preselected.map(\.field))
                self.phase = .reviewing
            } catch is CancellationError {
                // Deliberately silent: the user started another scan.
            } catch {
                self.phase = .failed(Self.message(for: error))
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    private static func message(for error: Error) -> String {
        switch error {
        case TextRecognitionError.noPages:
            "Nothing was scanned. Try again, or enter the details by hand."
        case TextRecognitionError.couldNotRenderPDF:
            "That PDF could not be read. Try a photo of the page instead, or enter the details by hand."
        default:
            "The text could not be read. You can still enter everything by hand."
        }
    }

    // MARK: - Review state

    func suggestion(for field: SuggestedField) -> FieldSuggestion? {
        result?.suggestion(for: field)
    }

    var suggestions: [FieldSuggestion] { result?.suggestions ?? [] }

    var lowConfidenceSuggestions: [FieldSuggestion] {
        suggestions.filter { !$0.isPreselected }
    }

    func displayValue(for field: SuggestedField) -> String {
        if let edit = edits[field] { return edit }
        guard let suggestion = suggestion(for: field) else { return "" }
        switch suggestion.value {
        case let .text(text): return text
        case let .money(amount): return "\(MoneyMath.rounded(amount))"
        case let .date(date): return CSVExport.isoDate(date, calendar: calendar)
        }
    }

    func binding(for field: SuggestedField) -> Binding<String> {
        Binding(
            get: { self.displayValue(for: field) },
            set: { self.edits[field] = $0 }
        )
    }

    func toggle(_ field: SuggestedField) {
        if selection.contains(field) { selection.remove(field) } else { selection.insert(field) }
    }

    var hasAnySelection: Bool { !selection.isEmpty }

    /// The values the user ticked, re-parsed from whatever is on screen now.
    ///
    /// Re-parsing rather than returning the original suggestion is deliberate: if the user
    /// corrected "2565.OO" to "2565.00", the corrected value is what gets saved.
    func acceptedValues() -> [SuggestedField: SuggestedValue] {
        var accepted: [SuggestedField: SuggestedValue] = [:]
        for field in selection {
            let text = displayValue(for: field).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            guard let suggestion = suggestion(for: field) else {
                accepted[field] = .text(text)
                continue
            }
            switch suggestion.value {
            case .money:
                if let amount = MoneyMath.parse(text) { accepted[field] = .money(amount) }
            case .date:
                if let date = DateTextParser.parse(text, calendar: calendar) {
                    accepted[field] = .date(date)
                }
            case .text:
                accepted[field] = .text(text)
            }
        }
        return accepted
    }
}
