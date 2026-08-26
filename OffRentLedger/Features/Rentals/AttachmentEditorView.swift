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

    @Query private var assets: [EvidenceAsset]

    @State private var name = ""
    @State private var caption = ""
    @State private var hasLoaded = false
    @State private var isSaving = false
    @State private var saveFailure: String?
    @State private var confirmingDelete = false
    @State private var showingPreview = false
    @State private var fullSize: Data?

    init(assetID: UUID) {
        self.assetID = assetID
        _assets = Query(filter: #Predicate<EvidenceAsset> { $0.id == assetID })
    }

    private var asset: EvidenceAsset? { assets.first }

    /// A name is the only thing here that cannot be blank: it is what a reader of the evidence
    /// packet sees against the photograph, and "" against a photograph is worse than a generated
    /// name nobody chose.
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty && !isSaving }

    var body: some View {
        Group {
            if let asset {
                content(for: asset)
            } else {
                // Deleted from under this screen — from the list behind it, or by deleting the
                // rental. Saying so beats an empty form that saves into nothing.
                EmptyStateView(
                    symbol: "paperclip",
                    title: "This attachment is no longer here",
                    message: "It was removed. Nothing else on the rental was changed.",
                    actionTitle: "Back to the rental",
                    action: { dismiss() }
                )
            }
        }
        .offRentFormBackground()
        .navigationTitle("Attachment")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(A11yID.Attachment.root)
        .onAppear(perform: load)
    }

    // MARK: - Content

    private func content(for asset: EvidenceAsset) -> some View {
        Form {
            Section {
                Button {
                    showingPreview = true
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
        .sheet(isPresented: $showingPreview) {
            if let fullSize {
                PageViewer(data: fullSize, pageNumber: 1) { showingPreview = false }
            }
        }
        .task(id: showingPreview) {
            guard showingPreview, fullSize == nil else { return }
            let store = dependencies.fileStore
            let path = asset.relativePath
            let url = store.url(forRelativePath: path)
            fullSize = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: url)
            }.value
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

    private func load() {
        guard !hasLoaded, let asset else { return }
        hasLoaded = true
        name = asset.displayName
        caption = asset.caption ?? ""
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
