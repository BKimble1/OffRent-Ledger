import SwiftUI

/// The review screen every scan passes through.
///
/// There is no path from a scan to a saved record that does not stop here. The Save button is the
/// only caller of `acceptedValues()`, and dismissing this sheet — by Cancel, by swipe, by
/// backgrounding — writes nothing at all.
struct ScanReviewView: View {

    @Bindable var model: ScanReviewViewModel
    let onSave: ([SuggestedField: SuggestedValue]) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .idle, .recognising:
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Reading the document on this iPhone…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(AppCopy.ocrLocalOnly)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case let .failed(message):
                    EmptyStateView(
                        symbol: "doc.viewfinder",
                        title: "Could not read that",
                        message: message,
                        actionTitle: "Enter it by hand",
                        action: { onSave([:]) }
                    )

                case .reviewing:
                    reviewForm
                }
            }
            .offRentFormBackground()
            .safeAreaInset(edge: .bottom) {
                if model.phase == .reviewing { saveBar }
            }
            .navigationTitle("Check what was read")
            .navigationBarTitleDisplayMode(.inline)
            // Replaces what used to be the view model's `deinit`. This is the better hook anyway:
            // it fires when the sheet closes, whichever way the user closed it, rather than
            // whenever the object happens to be released.
            .onDisappear { model.cancel() }
            .accessibilityIdentifier(A11yID.Scan.reviewRoot)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.cancel()
                        onCancel()
                    }
                    .accessibilityIdentifier(A11yID.Scan.cancelButton)
                }
            }
        }
    }

    /// The commit, and the count of what it will commit.
    ///
    /// A scan review is a list of things the user is agreeing to; the button that ends it should
    /// say how many, because the difference between six and two ticked fields is invisible once
    /// the list is longer than a screen.
    private var saveBar: some View {
        StickyActionBar {
            VStack(spacing: Space.snug) {
                Button {
                    onSave(model.acceptedValues())
                } label: {
                    Text(selectedCount == 1 ? "Use 1 value" : "Use \(selectedCount) values")
                }
                .buttonStyle(.offRentPrimary)
                .accessibilityIdentifier(A11yID.Scan.saveButton)
                .disabled(model.phase != .reviewing)
                Text("Nothing is saved to a rental until you tap this.")
                    .font(Typography.micro)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedCount: Int { model.selection.count }

    private var reviewForm: some View {
        Form {
            Section {
                Label(AppCopy.scanReviewExplanation, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .accessibilityIdentifier(A11yID.Scan.explanation)
            }

            if !confidentSuggestions.isEmpty {
                Section {
                    ForEach(confidentSuggestions) { suggestion in
                        row(for: suggestion)
                    }
                } header: {
                    Text("Read with high confidence")
                } footer: {
                    Text("These are ticked. Untick anything you do not want, and correct anything that is wrong.")
                }
            }

            if !model.lowConfidenceSuggestions.isEmpty {
                Section {
                    ForEach(model.lowConfidenceSuggestions) { suggestion in
                        row(for: suggestion)
                    }
                } header: {
                    Text("Less certain")
                } footer: {
                    Text(AppCopy.lowConfidenceExplanation)
                }
            }

            if model.suggestions.isEmpty {
                Section {
                    Text("""
                        Nothing recognisable was found on that document. You can still enter \
                        everything by hand — tap Save to carry on.
                        """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Show the text that was read", isOn: $model.showRawText)
                    .accessibilityIdentifier(A11yID.Scan.rawTextToggle)
                    .minimumTapTarget()
                if model.showRawText, let document = model.document {
                    Text(document.rawText)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.showRawText, let unmatched = model.result?.unmatchedLines, !unmatched.isEmpty {
                    DisclosureGroup("Lines that were not interpreted (\(unmatched.count))") {
                        ForEach(Array(unmatched.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption2.monospaced())
                        }
                    }
                    .font(.footnote)
                }
            } header: {
                Text("What the scanner saw")
            } footer: {
                Text(AppCopy.ocrLocalOnly)
            }
        }
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

            // Provenance, shown rather than hidden. "Read from: 7 DAY RATE: $985.00" is the
            // difference between a user trusting a value and guessing about it.
            VStack(alignment: .leading, spacing: 2) {
                Text("\(suggestion.confidenceDescription) · read from:")
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
            )
        }
        .padding(.vertical, 2)
    }
}
