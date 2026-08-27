import SwiftData
import SwiftUI

/// One attachment: rename it, caption it, look at it, or remove it.
///
/// The attachments list could technically do two of these already and neither of them worked in
/// a way anybody would find.
///
/// Deleting was `.onDelete` — a swipe, with no visible control, on a row that carried a text
/// field. Swiping a row whose middle is an editable field is a gesture fight, and a destructive
/// action with no button is one a user reasonably concludes does not exist.
///
/// Captioning wrote straight into the model from a `TextField` binding and never saved. SwiftData
/// may autosave and may not, which is the worst of the two: a caption typed into a rental record
/// either persisted or did not, with nothing on screen either way. This screen has a Save that
/// reports what it did, like every other editor in the app.
///
/// The name is editable at all now, which it was not. `displayName` is generated when the file is
/// filed — "Scan 3", "Photo 2026-05-11" — and it is the only thing identifying an attachment in
/// the evidence packet a rental company reads.
struct AttachmentEditorView: View {

    let assetID: UUID

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Fetched once, not observed.
    ///
    /// This was a `@Query` whose `#Predicate` was built in `init`. That is the shape SwiftData
    /// churns on: a `NavigationLink { AttachmentEditorView(...) }` inside a `ForEach` constructs
    /// its destination eagerly and again on every list update, each construction makes a fresh
    /// `FetchDescriptor`, and a descriptor SwiftData cannot recognise as the previous one is a
    /// reason to fetch again and publish again. The view graph then never settles — which is a
    /// spinning main thread, and on a real iPhone a watchdog kill (0x8BADF00D) reported as a
    /// crash when somebody taps an attachment.
    ///
    /// An editor does not need live results. It reads the record once, edits a copy of the two
    /// fields in `@State`, and leaves when it has saved or removed it.
    @State private var asset: EvidenceAsset?
    @State private var hasFetched = false

    @State private var name = ""
    @State private var caption = ""
    @State private var isSaving = false
    @State private var saveFailure: String?
    @State private var confirmingDelete = false
    @State private var showingPreview = false
    @State private var fullSize: Data?
    /// Why the bytes could not be read, when they could not be.
    @State private var previewFailure: String?


    /// A name is the only thing here that cannot be blank: it is what a reader of the evidence
    /// packet sees against the photograph, and "" against a photograph is worse than a generated
    /// name nobody chose.
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty && !isSaving }

    var body: some View {
        Group {
            if let asset {
                content(for: asset)
            } else if hasFetched {
                // Deleted from under this screen — from the list behind it, or by deleting the
                // rental. Saying so beats an empty form that saves into nothing.
                //
                // Only after the fetch has run. Saying it before that would be claiming the
                // attachment is gone when the truth is that nothing has looked for it yet.
                EmptyStateView(
                    symbol: "paperclip",
                    title: "This attachment is no longer here",
                    message: "It was removed. Nothing else on the rental was changed.",
                    actionTitle: "Back to the rental",
                    action: { dismiss() }
                )
                .accessibilityIdentifier(A11yID.Attachment.root)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .offRentFormBackground()
        .navigationTitle("Attachment")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: fetchOnce)
    }

    // MARK: - Content

    private func content(for asset: EvidenceAsset) -> some View {
        Form {
            Section {
                Button {
                    openPreview(for: asset)
                } label: {
                    HStack(spacing: Space.comfortable) {
                        EvidenceThumbnail(asset: asset, fileStore: dependencies.fileStore)
                        VStack(alignment: .leading, spacing: Space.hair) {
                            Text(asset.mediaType.displayName)
                                .font(Typography.rowTitle)
                            Text("Tap to see it full size")
                                .font(Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Space.snug)
                        Image(systemName: "chevron.forward")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(A11yID.Attachment.preview)
                .minimumTapTarget()
            }

            Section {
                HStack(alignment: .firstTextBaseline, spacing: Space.snug) {
                    FieldLabel("Name", isRequired: true)
                    TextField("Name", text: $name)
                        .accessibilityIdentifier(A11yID.Attachment.name)
                }
                TextField("Caption — what this shows", text: $caption, axis: .vertical)
                    .lineLimit(2...6)
                    .accessibilityIdentifier(A11yID.Attachment.caption)
            } header: {
                Text("What this is")
            } footer: {
                Text("""
                    The name and caption are what a reader of the evidence packet sees against \
                    this photograph. Nothing here changes the file itself.
                    """)
            }

            Section("Recorded") {
                LabeledContent("Captured", value: Formatters.dateAndTime(asset.capturedAt))
                if asset.locationLatitude != nil, asset.locationLongitude != nil {
                    LabeledContent("Location", value: "A coordinate was recorded")
                }
                if let digest = asset.sha256 {
                    VStack(alignment: .leading, spacing: Space.hair) {
                        Text("SHA-256")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                        Text(digest)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(AppCopy.checksumExplanation)
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section {
                Button("Remove this attachment", role: .destructive) { confirmingDelete = true }
                    .accessibilityIdentifier(A11yID.Attachment.delete)
                    .minimumTapTarget()
            } footer: {
                Text("""
                    The photograph is deleted from this iPhone as well as from the rental. \
                    Anything already exported keeps the copy it was given.
                    """)
            }

            if let saveFailure {
                Section {
                    InlineAlert(message: saveFailure)
                        .accessibilityIdentifier(A11yID.Failure.attachmentSave)
                }
            }
        }
        // The identifier goes on the form, *before* the inset. `EditRentalView` carries the same
        // note and the same ordering, and it is not a style preference: an accessibility
        // modifier applied over a `safeAreaInset` is pushed down into the inset's contents, so a
        // root identifier on the chain above this line lands on the Save button too and replaces
        // `attachment.save`. It did. The CI dump read
        // `Button, identifier: 'attachment.editor', label: 'Save changes'`, and two tests spent
        // eight seconds each waiting for a button that was on screen, enabled, and renamed.
        // `scripts/verify_repository.py` now fails the build on that ordering.
        .accessibilityIdentifier(A11yID.Attachment.root)
        .safeAreaInset(edge: .bottom) { saveBar }
        // On the destructive button, not the form: an alert beside a sheet on one chain stops
        // the sheet presenting in this app, and the preview below is a sheet.
        .confirmationDialog(
            "Remove this attachment?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { delete(asset) }
                .accessibilityIdentifier(A11yID.Attachment.confirmDelete)
            Button("Keep", role: .cancel) {}
        } message: {
            Text("The file is deleted from this iPhone too. This cannot be undone.")
        }
        // Three states, not one. The sheet presents the instant `showingPreview` becomes true,
        // and the file is read *after* that — so a closure that only draws when the bytes have
        // arrived presents an empty sheet and fills it in a moment later. When the read fails
        // the empty sheet is all there ever is: a preview that opens onto nothing, with no way
        // to tell whether the file is missing or the app is broken.
        .sheet(isPresented: $showingPreview) {
            if let fullSize {
                PageViewer(data: fullSize, pageNumber: 1) { showingPreview = false }
            } else if let previewFailure {
                EmptyStateView(
                    symbol: "exclamationmark.triangle",
                    title: "This file could not be opened",
                    message: previewFailure,
                    actionTitle: "Close",
                    action: { showingPreview = false }
                )
            } else {
                ProgressView("Opening…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var saveBar: some View {
        StickyActionBar {
            VStack(spacing: Space.snug) {
                Button("Save changes") { save() }
                    .buttonStyle(.offRentPrimary)
                    .disabled(!canSave)
                    .accessibilityIdentifier(A11yID.Attachment.save)
                if trimmedName.isEmpty {
                    Text("Give this attachment a name before saving.")
                        .font(Typography.micro)
                        .foregroundStyle(Palette.attentionText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(A11yID.Attachment.missingRequirement)
                }
            }
        }
    }

    // MARK: - Actions

    /// One fetch, on appearance, and the fields are filled from what it found.
    ///
    /// The version this replaces read a `@Query` and filled the fields from a separate
    /// `onAppear`. When the query had not resolved yet that guard fell through *without*
    /// recording that it had run, and `onAppear` does not fire twice — so the name field stayed
    /// empty, Save stayed disabled, and the screen asked for a name for an attachment that
    /// already had one. Fetching and filling in the same place cannot drift apart.
    private func fetchOnce() {
        guard !hasFetched else { return }
        hasFetched = true
        let wanted = assetID
        var descriptor = FetchDescriptor<EvidenceAsset>(
            predicate: #Predicate<EvidenceAsset> { $0.id == wanted }
        )
        descriptor.fetchLimit = 1
        let found = try? context.fetch(descriptor).first
        asset = found
        guard let found else { return }
        name = found.displayName
        caption = found.caption ?? ""
    }

    /// Opens the preview and reads the bytes for it.
    ///
    /// Reading them here rather than in a `task(id: showingPreview)` on the same chain as the
    /// sheet keeps one flag from driving two things at once. The sheet shows progress until the
    /// bytes arrive, and says which of the record and the file is missing when they do not.
    private func openPreview(for asset: EvidenceAsset) {
        showingPreview = true
        guard fullSize == nil else { return }
        previewFailure = nil
        let url = dependencies.fileStore.url(forRelativePath: asset.relativePath)
        Task {
            let data = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: url)
            }.value
            if let data {
                fullSize = data
            } else {
                previewFailure = AppCopy.attachmentFileMissing
            }
        }
    }

    private func save() {
        guard let asset, canSave else { return }
        isSaving = true
        defer { isSaving = false }

        let service = AttachmentEditingService(context: context)
        if let failure = service.rename(asset, to: trimmedName, caption: caption) {
            saveFailure = failure
            return
        }
        saveFailure = nil
        dismiss()
    }

    private func delete(_ asset: EvidenceAsset) {
        // The record first, then the files. A failed save would otherwise leave a record
        // pointing at a photograph that is already gone — a rental claiming evidence it cannot
        // produce, which is the one thing this app must never do. The service does the record
        // and hands back what is now unreferenced.
        switch AttachmentEditingService(context: context).remove(asset) {
        case let .failed(message):
            saveFailure = message
        case let .removed(paths):
            Task { [fileStore = dependencies.fileStore] in
                for path in paths { await fileStore.delete(relativePath: path) }
            }
            dismiss()
        }
    }
}
