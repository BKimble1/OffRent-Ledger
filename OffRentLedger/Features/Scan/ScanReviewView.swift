import PhotosUI
import SwiftUI
import UIKit

/// The review screen every scan passes through.
///
/// There is no path from a scan to a saved record that does not stop here. The commit button is
/// the only caller of `acceptedValues()`, and dismissing this sheet — by Cancel, by swipe, by
/// backgrounding — writes nothing at all.
///
/// The screenshot that prompted the rebuild showed a residential lease under the words "Nothing
/// was recognised on this page" and a large orange button reading `Use 0 values`. The button was
/// doing the honest thing — committing nothing — while looking like the way forward, and the way
/// forward was in fact the small grey Cancel above it. A count of zero is not a quantity to
/// offer; it is a different screen, and this has one.
struct ScanReviewView: View {

    @Bindable var model: ScanReviewViewModel
    let onSave: ([SuggestedField: SuggestedValue]) -> Void
    let onCancel: () -> Void
    /// Closes this review and opens the scanner again.
    ///
    /// Separate from `onCancel` because they are different intentions and the words on the
    /// buttons say so. Cancel means "forget this"; Rescan means "that photo was no good, let me
    /// take another" — and a `Rescan` button that merely closed the sheet would be asking the
    /// user to go and find the Scan button themselves.
    var onRescan: (() -> Void)?

    @State private var enlargedPage: Int?
    @Environment(AppDependencies.self) private var dependencies
    /// Guards the auto-fill against firing twice if the phase settles more than once.
    @State private var hasAutoFilled = false
    @State private var showsRecognizedText = false
    @State private var addingPages = false
    @State private var addedPhotos: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .idle, .recognising:
                    progressState

                case let .failed(message):
                    EmptyStateView(
                        symbol: "doc.viewfinder",
                        title: "Could not read that",
                        message: message,
                        actionTitle: ScanReviewCopy.enterManually,
                        action: { onSave([:]) }
                    )
                    .accessibilityIdentifier(A11yID.Scan.nothingFound)

                case .reading where !model.outcome.hasAnything:
                    // The rules found nothing and the on-device model is still reading. Saying
                    // "No rental details found" now would be a verdict delivered before the work
                    // finished — and on a rate table, which is the case the model exists for, it
                    // would be wrong about half a second later.
                    progressState

                case .reviewing, .reading:
                    if model.outcome.hasAnything {
                        reviewForm
                    } else {
                        nothingFoundState
                    }
                }
            }
            .offRentFormBackground()
            // Before the inset, not after. An accessibility modifier applied over a
            // `safeAreaInset` is pushed down into the inset's contents, and `commitBar` holds
            // `scan.saveButton` and `scan.enterManually` — both of which a root identifier
            // sitting further down this chain would replace. `AttachmentEditorView` shipped that
            // mistake and cost two UI tests eight seconds each.
            .accessibilityIdentifier(A11yID.Scan.reviewRoot)
            .safeAreaInset(edge: .bottom) {
                if model.outcome.hasAnything, model.phase == .reviewing || model.phase == .reading {
                    commitBar
                }
            }
            // "Auto scan and fill if you allow it", and only if.
            //
            // The rule is in `ScanSettings.shouldFillAutomatically` rather than here, so it is
            // one sentence in one place and a test can reach it without a view: the setting has
            // to be on, the scan has to have produced at least three high-confidence fields, and
            // nothing may have been read at medium confidence. That last condition is the one
            // that matters — a scan that is part confident and part uncertain is precisely the
            // one worth looking at, so the shortcut stands down rather than quietly dropping the
            // uncertain half.
            .onChange(of: model.phase) { _, _ in autoFillIfAllowed() }
            .onAppear { autoFillIfAllowed() }
            .navigationTitle("Check what was read")
            .navigationBarTitleDisplayMode(.inline)
            // Replaces what used to be the view model's `deinit`. This is the better hook anyway:
            // it fires when the sheet closes, whichever way the user closed it, rather than
            // whenever the object happens to be released.
            .onDisappear { model.cancel() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.cancel()
                        onCancel()
                    }
                    .accessibilityIdentifier(A11yID.Scan.cancelButton)
                }
            }
            .photosPicker(
                isPresented: $addingPages,
                selection: $addedPhotos,
                maxSelectionCount: 6,
                matching: .images
            )
            .onChange(of: addedPhotos) { _, items in
                guard !items.isEmpty else { return }
                Task { await addPages(items) }
            }
        }
    }

    private func autoFillIfAllowed() {
        guard !hasAutoFilled, model.phase == .reviewing else { return }
        let unticked = model.suggestions.contains { !$0.isPreselected }
        // `acceptedValueCount`, not `selection.count`: the gate is deciding whether this scan is
        // good enough to skip the confirmation screen, so it has to count what will actually be
        // written. A field that is ticked but whose text will not parse is dropped on commit, and
        // skipping review to write two fields while believing four is the shape of mistake this
        // whole screen exists to prevent.
        guard dependencies.scanSettings.shouldFillAutomatically(
            preselectedCount: model.acceptedValueCount,
            hasAnythingUnticked: unticked
        ) else { return }
        hasAutoFilled = true
        onSave(model.acceptedValues())
    }

    // MARK: - States

    private var progressState: some View {
        VStack(spacing: Space.comfortable) {
            ProgressView()
            Text(
                model.phase == .reading
                    ? "Reading the layout on this iPhone…"
                    : "Reading the document on this iPhone…"
            )
            .font(Typography.rowDetail)
            .foregroundStyle(.secondary)
            Text(AppCopy.ocrLocalOnly)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.section)
            // Cancellation, offered rather than only supported. A ten-page PDF is minutes of
            // CPU, and a screen with a spinner and no exit is a screen people force-quit.
            Button("Stop") {
                model.cancel()
                onCancel()
            }
            .buttonStyle(.offRentSecondary)
            .padding(.top, Space.snug)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The honest empty state. Three ways on, and none of them is a button that commits nothing.
    private var nothingFoundState: some View {
        ScrollView {
            VStack(spacing: Space.comfortable) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                    .padding(.top, Space.section)

                Text(ScanReviewCopy.nothingFoundTitle(kind: model.kind))
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(ScanReviewCopy.nothingFoundMessage(kind: model.kind, pageCount: model.pageCount))
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: Space.snug) {
                    Button(ScanReviewCopy.enterManually) { onSave([:]) }
                        .buttonStyle(.offRentPrimary)
                        .accessibilityIdentifier(A11yID.Scan.enterManually)

                    HStack(spacing: Space.snug) {
                        Button(ScanReviewCopy.rescan) {
                            model.cancel()
                            if let onRescan { onRescan() } else { onCancel() }
                        }
                        .buttonStyle(.offRentSecondary)
                        .accessibilityIdentifier(A11yID.Scan.rescan)

                        Button(ScanReviewCopy.addPages) { addingPages = true }
                            .buttonStyle(.offRentSecondary)
                            .accessibilityIdentifier(A11yID.Scan.addPages)
                    }
                }
                .padding(.top, Space.snug)

                if !model.pageImageData.isEmpty { pagePreview }
                recognizedTextDisclosure
            }
            .padding(.horizontal, Space.roomy)
            .padding(.bottom, Space.screenBottom)
        }
        .accessibilityIdentifier(A11yID.Scan.nothingFound)
    }

    /// The commit, and the count of what it will commit.
    private var commitBar: some View {
        StickyActionBar {
            VStack(spacing: Space.snug) {
                // The count of what will be *written*, not of what is ticked. A ticked field
                // whose text will not parse is dropped on commit, so `selection.count` promised
                // five values over a save that wrote four.
                if let title = ScanReviewCopy.useValues(selected: model.acceptedValueCount) {
                    Button { onSave(model.acceptedValues()) } label: { Text(title) }
                        .buttonStyle(.offRentPrimary)
                        .accessibilityIdentifier(A11yID.Scan.saveButton)
                } else {
                    // Everything was unticked. Carrying on by hand is a real outcome and gets its
                    // own words; `Use 0 values` is not a thing this screen can say.
                    Button(ScanReviewCopy.enterManually) { onSave([:]) }
                        .buttonStyle(.offRentPrimary)
                        .accessibilityIdentifier(A11yID.Scan.enterManually)
                }
                // And the ones that will not be written are named, rather than vanishing
                // between the tick and the form.
                if !model.unusableSelections.isEmpty {
                    Text(unusableExplanation)
                        .font(Typography.micro)
                        .foregroundStyle(Palette.attentionText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(A11yID.Scan.unusableSelections)
                }
                Text("Nothing is saved to a rental until you tap this.")
                    .font(Typography.micro)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Names the ticked fields the commit will drop, and why.
    private var unusableExplanation: String {
        let names = model.unusableSelections.map(\.displayName)
        let listed = names.count == 1
            ? names[0]
            : names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        let verb = names.count == 1 ? "is not" : "are not"
        return "\(listed) \(verb) in a form this can save yet. Correct the text or enter "
            + (names.count == 1 ? "it" : "them") + " by hand on the next screen."
    }

    // MARK: - The form

    private var reviewForm: some View {
        Form {
            Section {
                summaryLine
            } footer: {
                Text(AppCopy.scanReviewExplanation)
                    .accessibilityIdentifier(A11yID.Scan.explanation)
            }

            if !confidentSuggestions.isEmpty {
                Section {
                    ForEach(confidentSuggestions) { suggestion in row(for: suggestion) }
                } header: {
                    Text("Read with high confidence")
                } footer: {
                    Text("These are ticked. Untick anything you do not want, and correct anything that is wrong.")
                }
            }

            if !model.lowConfidenceSuggestions.isEmpty {
                Section {
                    ForEach(model.lowConfidenceSuggestions) { suggestion in row(for: suggestion) }
                } header: {
                    Text("Less certain")
                } footer: {
                    Text(AppCopy.lowConfidenceExplanation)
                }
            }

            if !model.pageImageData.isEmpty {
                Section {
                    pagePreview
                    Button(ScanReviewCopy.addPages) { addingPages = true }
                        .accessibilityIdentifier(A11yID.Scan.addPages)
                } header: {
                    Text("What was scanned")
                }
            }

            Section { recognizedTextDisclosure } footer: {
                Text(AppCopy.ocrLocalOnly)
            }
        }
    }

    /// The raw text, folded away.
    ///
    /// It used to be a toggle followed by an inline wall of monospaced OCR, which is why the
    /// review screen was dominated by empty cards: the sections that held it were sized for text
    /// that was usually not shown. A `DisclosureGroup` is one row until somebody wants it.
    private var recognizedTextDisclosure: some View {
        DisclosureGroup(isExpanded: $showsRecognizedText) {
            if let document = model.document {
                Text(document.rawText)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let unmatched = model.result?.unmatchedLines, !unmatched.isEmpty {
                Text("\(unmatched.count) line\(unmatched.count == 1 ? "" : "s") were not interpreted.")
                    .font(Typography.micro)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label(ScanReviewCopy.recognizedText, systemImage: "text.alignleft")
        }
        .accessibilityIdentifier(A11yID.Scan.rawTextToggle)
    }

    /// The pages, as a strip. Reading a value off a screen and checking it against the page it
    /// came from used to mean closing the sheet and reopening the photo.
    private var pagePreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.snug) {
                ForEach(Array(model.pageImageData.enumerated()), id: \.offset) { index, data in
                    if let image = UIImage(data: data) {
                        Button {
                            enlargedPage = index
                        } label: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 68, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.control))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.control)
                                        .strokeBorder(Palette.hairline, lineWidth: Layout.hairline)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Page \(index + 1) of \(model.pageImageData.count)")
                        .accessibilityHint("Double tap to look at it closely.")
                    }
                }
            }
            .padding(.vertical, Space.tight)
        }
        .accessibilityIdentifier(A11yID.Scan.pagePreview)
        .fullScreenCover(item: Binding(
            get: { enlargedPage.map { EnlargedPage(index: $0) } },
            set: { if $0 == nil { enlargedPage = nil } }
        )) { page in
            PageViewer(
                data: model.pageImageData[page.index],
                pageNumber: page.index + 1,
                onClose: { enlargedPage = nil }
            )
        }
    }

    private struct EnlargedPage: Identifiable {
        let index: Int
        var id: Int { index }
    }

    /// What was found, and by what. A user is entitled to know which of these an algorithm
    /// matched on a line and which a model proposed from a table.
    @ViewBuilder
    private var summaryLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ScanReviewCopy.summary(outcome: model.outcome, pageCount: model.pageCount))
                .font(Typography.rowDetail)
                .fixedSize(horizontal: false, vertical: true)

            if model.phase == .reading {
                Label("Still reading the tables on this iPhone…", systemImage: "sparkles")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            } else if model.modelSuggestionCount > 0 {
                Label(
                    "\(model.modelSuggestionCount) came from reading the layout rather than a single line, and none of them is ticked.",
                    systemImage: "sparkles"
                )
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            } else if let reason = model.intelligenceUnavailableReason {
                Text(reason + " Rate tables may not be read.")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var confidentSuggestions: [FieldSuggestion] {
        model.suggestions.filter(\.isPreselected)
    }

    private func row(for suggestion: FieldSuggestion) -> some View {
        let isSelected: Bool = model.selection.contains(suggestion.field)
        return VStack(alignment: .leading, spacing: Space.snug) {
            // A tick rather than a switch. A switch reads as a setting that is on; this is the
            // user saying "yes, that is what the document says", which is a different act — and
            // the row has to show, at a glance, which values are still only suggestions.
            Button {
                model.toggle(suggestion.field)
            } label: {
                HStack(spacing: Space.snug) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 19))
                        .foregroundStyle(isSelected ? Palette.accent : Color.secondary)
                    Text(suggestion.field.displayName)
                        .font(Typography.rowTitle)
                        .foregroundStyle(.primary)
                    Spacer(minLength: Space.snug)
                    Text(isSelected ? "Confirmed" : "Suggested")
                        .font(Typography.micro.weight(.semibold))
                        .foregroundStyle(isSelected ? Palette.settled : .secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(A11yID.Scan.toggle(suggestion.field))
            .accessibilityLabel(suggestion.field.displayName)
            .accessibilityValue(isSelected ? "Confirmed" : "Suggested, not confirmed")
            .accessibilityHint("Double tap to \(isSelected ? "unconfirm" : "confirm") this value.")
            .minimumTapTarget()

            TextField(suggestion.field.displayName, text: model.binding(for: suggestion.field))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(A11yID.Scan.field(suggestion.field))
                .accessibilityLabel("\(suggestion.field.displayName) value")

            provenance(suggestion)
        }
        .padding(.vertical, 2)
    }

    /// Where the value came from: which page, which line, and how sure.
    ///
    /// "Read from: 7 DAY RATE: $985.00, page 2" is the difference between a user trusting a
    /// value and guessing about it — and the page is what makes it checkable on a five-page
    /// invoice where the rate table and the summary are nowhere near each other.
    private func provenance(_ suggestion: FieldSuggestion) -> some View {
        let readFrom = suggestion.provenance.rule == ModelSuggestionValidator.ruleName
            ? "read from the layout of"
            : "read from"
        let page = suggestion.provenance.pageDescription(of: model.pageCount)
        let heading = [suggestion.confidenceDescription, readFrom + ":"].joined(separator: " · ")

        return VStack(alignment: .leading, spacing: 2) {
            Text(page.map { "\(heading.dropLast()) on \($0):" } ?? heading)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(suggestion.provenance.sourceLine)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(suggestion.confidenceDescription). Read from the line: \(suggestion.provenance.sourceLine)"
                + (page.map { ", on \($0)." } ?? ".")
        )
    }

    // MARK: - Adding pages

    private func addPages(_ items: [PhotosPickerItem]) async {
        defer { addedPhotos = [] }
        var data: [Data] = []
        for item in items {
            guard let loaded = try? await item.loadTransferable(type: Data.self) else { continue }
            data.append(loaded)
        }
        guard !data.isEmpty else { return }
        model.addPages(data, source: .photoLibrary)
    }
}
