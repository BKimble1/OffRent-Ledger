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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(model.acceptedValues()) }
                        .accessibilityIdentifier(A11yID.Scan.saveButton)
                        .disabled(model.phase != .reviewing)
                }
            }
        }
    }

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
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { model.selection.contains(suggestion.field) },
                set: { _ in model.toggle(suggestion.field) }
            )) {
                Text(suggestion.field.displayName).font(.subheadline.weight(.medium))
            }
            .accessibilityIdentifier(A11yID.Scan.toggle(suggestion.field))
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
