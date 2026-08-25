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
///
/// **Before deleting anything here as unused, grep the whole repository.** The unit and UI
/// targets are compiled by Xcode and by nothing on this machine, so a property removed because
/// `OffRentLedger/` had no callers is a green local run and a failed CI one twenty minutes
/// later. `intelligenceIsAvailable` below is read only by `ScanIntelligenceTests`, and that is
/// exactly how it went once.
@MainActor
@Observable
final class ScanReviewViewModel {

    enum Phase: Equatable {
        case idle
        case recognising
        /// The rule parser has finished and the on-device model is still reading. The review
        /// screen is already usable in this phase — waiting for the model before showing
        /// anything would make every scan feel slower than the one before it.
        case reading
        case reviewing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var result: ParseResult?
    private(set) var document: RecognizedDocument?

    /// The scanned pages, kept in memory so the review screen can show what it read.
    ///
    /// In memory and nowhere else. This type still cannot write a file — the pages reach disk
    /// only if the user saves the rental they belong to, through the evidence store, which is a
    /// different object entirely.
    private(set) var pageImageData: [Data] = []

    /// The PDF this scan began with, when it began with one.
    ///
    /// Held for the same reason and under the same rule as `pageImageData`: in memory, for the
    /// life of this object, and this type still cannot write a file. `addPages` needs it —
    /// without it, adding a page to an imported PDF threw the PDF away.
    private(set) var sourcePDFData: Data?

    /// Which suggestions the user has ticked. Seeded from `isPreselected`, then owned entirely by
    /// the user.
    var selection: Set<SuggestedField> = []
    /// Edited values, keyed by field. A value the user typed always wins over the parsed one.
    var edits: [SuggestedField: String] = [:]

    let kind: DocumentKind
    private let recognizer: any DocumentTextRecognizing
    private let intelligence: any DocumentIntelligence
    private let calendar: Calendar

    /// How many suggestions came from the on-device model rather than from a rule. Shown on the
    /// review screen, because a user deserves to know which of these an algorithm matched and
    /// which a model proposed.
    private(set) var modelSuggestionCount = 0

    /// `@ObservationIgnored` because the in-flight task is not UI state — and, more to the point,
    /// because `@Observable` turns an unmarked stored property into a computed one, which cannot
    /// be touched from a `deinit` on a `@MainActor` type.
    @ObservationIgnored private var task: Task<Void, Never>?

    init(
        kind: DocumentKind,
        recognizer: any DocumentTextRecognizing,
        calendar: Calendar,
        intelligence: any DocumentIntelligence = UnavailableDocumentIntelligence()
    ) {
        self.kind = kind
        self.recognizer = recognizer
        self.calendar = calendar
        self.intelligence = intelligence
    }

    /// Whether this device can read tables as well as lines, and why not when it cannot.
    ///
    /// `intelligenceIsAvailable` is read by `ScanIntelligenceTests`, not by a view — which is
    /// exactly why removing it as "unused" cost a CI round. A grep of `OffRentLedger/` is not a
    /// grep of the repository.
    var intelligenceIsAvailable: Bool { intelligence.isAvailable }
    var intelligenceUnavailableReason: String? { intelligence.unavailableReason }

    // No `deinit { task?.cancel() }`. `deinit` is nonisolated, this type is `@MainActor`, and
    // reaching isolated state from there does not compile. `ScanReviewView` cancels in
    // `.onDisappear`, which is also the moment that actually matters: the sheet closing.

    // MARK: - Pipeline

    func recognise(imageData: [Data], source: DocumentSource) {
        sourcePDFData = nil
        pageImageData = imageData
        run { [recognizer] in try await recognizer.recognize(imageData: imageData, source: source) }
    }

    func recognise(pdf data: Data) {
        sourcePDFData = data
        // A rescan replaces what came before it. Leaving the previous scan's page images here
        // would show the review screen's page strip a document that is no longer the one being
        // reviewed.
        pageImageData = []
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
                self.phase = self.intelligence.isAvailable ? .reading : .reviewing

                // The model runs after the rules, on what the rules did not find, and adds only
                // what survives validation against the page. Nothing it returns is ticked, and a
                // failure leaves the screen exactly as the rule parser left it.
                if self.intelligence.isAvailable {
                    let proposals = await self.intelligence.propose(
                        from: document, kind: self.kind
                    )
                    try Task.checkCancellation()
                    let extra = ModelSuggestionValidator.validate(
                        proposals,
                        against: document,
                        existing: parsed.suggestions,
                        calendar: self.calendar
                    )
                    if !extra.isEmpty {
                        var merged = parsed
                        merged.suggestions.append(contentsOf: extra)
                        merged.unmatchedLines = merged.unmatchedLines.filter { line in
                            !extra.contains { $0.provenance.sourceLine == line }
                        }
                        self.result = merged
                        self.modelSuggestionCount = extra.count
                    }
                    self.phase = .reviewing
                }
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

    /// Awaits the in-flight recognition, if there is one.
    ///
    /// The view never needs this: it observes `phase` and redraws when the pipeline finishes.
    /// A test has no observer, so without this it can only sleep for a plausible interval and
    /// hope — and that is exactly how `ScanReviewCommitTests` failed. Six `Task.sleep(200ms)`
    /// calls passed on an idle CI machine and failed on a loaded one, reporting four different
    /// symptoms that were all one thing: the assertion ran before the work finished.
    ///
    /// Awaiting the task is deterministic. It returns when the work is done, however long the
    /// machine takes to do it.
    func awaitPendingWork() async {
        guard let task else { return }
        await task.value
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

    /// The company the letterhead names, whether or not its row was ticked.
    ///
    /// Deliberately outside the tick mechanism, because this is not a value being committed —
    /// the rental needs a reusable `Vendor` record, not a string, and one is never created from
    /// OCR. It is a *search hint*, and it was unreachable in the flow that matters: the vendor
    /// row arrives at 0.54 confidence so it is never pre-ticked, and the ordinary path through
    /// this screen is to glance at the ticked rows and tap the button. So the name was read off
    /// the page, shown on screen, and then thrown away every single time.
    var scannedVendorName: String? {
        suggestion(for: .vendorName)?.value.textValue
    }

    func suggestion(for field: SuggestedField) -> FieldSuggestion? {
        result?.suggestion(for: field)
    }

    var suggestions: [FieldSuggestion] { result?.suggestions ?? [] }

    /// What the scan produced, and therefore what the review screen should offer.
    ///
    /// Counted against the fields this *kind* of document can carry, so an "invoice total"
    /// matched on a rental contract does not make the screen claim it found something useful.
    var outcome: ScanOutcome {
        ScanOutcome.evaluate(suggestions: suggestions, kind: kind)
    }

    var pageCount: Int { document?.pageCount ?? max(pageImageData.count, 1) }

    /// Adds pages to a scan that is already on screen and re-runs the pipeline over all of them.
    ///
    /// The user's edits are deliberately cleared: they were made against a different set of
    /// suggestions, and silently carrying a value the new parse did not produce would put
    /// something on the review screen that nothing on the document says.
    ///
    /// A scan that began as a PDF keeps the PDF. This used to hand the recogniser
    /// `pageImageData + data` and nothing else — and an imported PDF never fills `pageImageData`,
    /// because it is read out of its own text layer rather than photographed. So "Add pages" on
    /// an imported invoice discarded the invoice and reviewed the added photographs on their own:
    /// a review screen describing half the document, with the total and the charge lines gone and
    /// nothing on screen to say they had been.
    func addPages(_ data: [Data], source: DocumentSource) {
        guard !data.isEmpty else { return }
        let combined = pageImageData + data
        pageImageData = combined
        edits = [:]

        guard let pdf = sourcePDFData else {
            run { [recognizer] in
                try await recognizer.recognize(imageData: combined, source: source)
            }
            return
        }

        // Two recognitions joined, because the recogniser has no call that takes both. The PDF
        // comes first: it is the document the user started from, so its pages keep their numbers
        // and the added photographs are numbered after them.
        run { [recognizer] in
            let fromPDF = try await recognizer.recognize(pdf: pdf)
            let fromPages = try await recognizer.recognize(imageData: combined, source: source)
            return fromPDF.appending(fromPages)
        }
    }

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

    /// The ticked fields `acceptedValues()` is going to drop, and the reason it will drop them:
    /// the text on screen cannot be read as the kind of value the field holds.
    ///
    /// Dropping them is right. A daily rate typed as "twelve hundred" must never reach the store
    /// as a number, and the store is where a contractor's case against an invoice lives. What was
    /// wrong was doing it in silence — the row stayed ticked, the button counted it, the sheet
    /// closed, and nothing on the form had changed. The user had every reason to believe their
    /// correction was saved.
    ///
    /// Whoever presents `acceptedValues()` presents this beside it. Sorted so the list a user
    /// reads is stable between redraws rather than reshuffling with the set's hash order.
    var unusableSelections: [SuggestedField] {
        let accepted = acceptedValues()
        return selection
            .filter { accepted[$0] == nil }
            .sorted { $0.rawValue < $1.rawValue }
    }

    /// How many ticked values will actually be written. Never more than `selection.count`.
    ///
    /// The commit button's count belongs here rather than on `selection.count`, which counts
    /// rows the commit is about to drop — "Use 5 suggested values" over a commit that writes
    /// four. A button that overstates what it is about to do is the same defect as a screen that
    /// overstates what it holds.
    var acceptedValueCount: Int { acceptedValues().count }

    /// The values the user ticked, re-parsed from whatever is on screen now.
    ///
    /// Re-parsing rather than returning the original suggestion is deliberate: if the user
    /// corrected "2565.OO" to "2565.00", the corrected value is what gets saved.
    ///
    /// A ticked field whose text will not parse is left out rather than coerced — see
    /// `unusableSelections`, which is how the caller says so.
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
