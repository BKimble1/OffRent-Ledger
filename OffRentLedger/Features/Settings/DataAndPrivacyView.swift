import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Export, import, and deletion.
///
/// The two rules this screen exists to honour: a user can always take their data out, and a user
/// can always delete it. Neither is behind a subscription, at any entitlement state.
struct DataAndPrivacyView: View {

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context

    @Query private var items: [RentalItem]

    @State private var exportedCSV: URL?
    @State private var exportedBackup: URL?
    @State private var showingImporter = false
    @State private var pendingImport: (archive: BackupArchive, preview: ImportPreview)?
    @State private var importFailure: String?
    @State private var showingDeleteConfirmation = false
    @State private var deleteConfirmationText = ""
    @State private var storageBytes: Int64 = 0
    @State private var busy = false

    private var exportService: ExportService {
        ExportService(context: context, clock: dependencies.clock, fileStore: dependencies.fileStore)
    }

    var body: some View {
        List {
            Section {
                Text(AppCopy.localOnlySummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DetailRow(label: "Rentals stored", value: "\(items.count)")
                DetailRow(
                    label: "Photos and documents",
                    value: ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)
                )
            } header: {
                Text("On this iPhone")
            }

            Section {
                Button {
                    Task { await exportCSV() }
                } label: {
                    Label("Export a CSV summary", systemImage: "tablecells")
                }
                .accessibilityIdentifier(A11yID.Settings.exportCSV)
                .minimumTapTarget()
                if let exportedCSV {
                    ShareLink(item: exportedCSV) { Label("Share the CSV", systemImage: "square.and.arrow.up") }
                        .minimumTapTarget()
                }

                Button {
                    Task { await exportBackup() }
                } label: {
                    Label("Export a full backup file", systemImage: "arrow.down.doc")
                }
                .accessibilityIdentifier(A11yID.Settings.exportBackup)
                .minimumTapTarget()
                if let exportedBackup {
                    ShareLink(item: exportedBackup) { Label("Share the backup", systemImage: "square.and.arrow.up") }
                        .minimumTapTarget()
                }
            } header: {
                Text("Export")
            } footer: {
                Text("""
                    Both are yours to keep and neither needs a subscription. The backup is readable \
                    JSON — you can open it in any text editor and see exactly what is in it.
                    """)
            }

            Section {
                Button {
                    showingImporter = true
                } label: {
                    Label("Import a backup file", systemImage: "arrow.up.doc")
                }
                .accessibilityIdentifier(A11yID.Settings.importBackup)
                .minimumTapTarget()
            } header: {
                Text("Import")
            } footer: {
                Text("""
                    You will see exactly what would be added before anything is written. Importing \
                    only adds — it never overwrites or deletes what you already have.
                    """)
            }

            Section {
                Button("Delete all data", role: .destructive) { showingDeleteConfirmation = true }
                    .accessibilityIdentifier(A11yID.Settings.deleteAllData)
                    .minimumTapTarget()
            } header: {
                Text("Delete")
            } footer: {
                Text("""
                    Removes every rental, photo, document and reminder from this iPhone. There is \
                    no server copy, so this cannot be undone. Export first if you want a record.
                    """)
            }

            Section("What this app never does") {
                privacyPoint("No account and no login")
                privacyPoint("No server — nothing is uploaded")
                privacyPoint("No analytics, advertising or tracking")
                privacyPoint("No third-party crash reporting")
                privacyPoint("Scanning and text recognition run on this iPhone only")
                privacyPoint("Location is asked for once, when you tap for it, and never in the background")
            }
        }
        .offRentFormBackground()
        .navigationTitle("Data and privacy")
        .navigationBarTitleDisplayMode(.inline)
        .task { storageBytes = await dependencies.fileStore.totalBytesOnDisk() }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportSelection(result)
        }
        .sheet(item: Binding(
            get: { pendingImport.map { ImportSession(archive: $0.archive, preview: $0.preview) } },
            set: { if $0 == nil { pendingImport = nil } }
        )) { session in
            ImportPreviewView(
                preview: session.preview,
                onConfirm: {
                    applyImport(session.archive)
                    pendingImport = nil
                },
                onCancel: { pendingImport = nil }
            )
        }
        .alert(
            "Import failed",
            isPresented: Binding(
                get: { importFailure != nil }, set: { if !$0 { importFailure = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importFailure ?? "")
        }
        .alert("Delete all data?", isPresented: $showingDeleteConfirmation) {
            // Typed confirmation, not just a red button. This is the one irreversible action in
            // the app and a mis-tap costs somebody every record they have.
            TextField("Type DELETE", text: $deleteConfirmationText)
                .accessibilityIdentifier(A11yID.Settings.deleteAllConfirm)
            Button("Delete everything", role: .destructive) {
                guard deleteConfirmationText.uppercased() == "DELETE" else { return }
                Task { await deleteAll() }
            }
            Button("Cancel", role: .cancel) { deleteConfirmationText = "" }
        } message: {
            Text("Type DELETE to confirm. Every rental, photo and document on this iPhone will be removed.")
        }
    }

    private func privacyPoint(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.shield")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private struct ImportSession: Identifiable {
        let archive: BackupArchive
        let preview: ImportPreview
        var id: Date { preview.archiveGeneratedAt }
    }

    // MARK: - Actions

    private func exportCSV() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }

        let entitlement = dependencies.effectiveEntitlement
        // The full-history export is Pro; a single rental's CSV is not, and neither is the
        // backup. Nobody is locked out of their own records.
        if !EntitlementPolicy.isAllowed(.fullHistoryExport, entitlement: entitlement),
           items.count > 1 {
            router.presentedSheet = .paywall(reason: .historyExport)
            return
        }

        guard let csv = try? exportService.makeCSVForAllItems() else { return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OffRentLedger-rentals.csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        exportedCSV = url
    }

    private func exportBackup() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        guard let data = try? exportService.encodeArchive() else { return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OffRentLedger-backup.json")
        try? data.write(to: url, options: .atomic)
        exportedBackup = url
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            importFailure = "That file could not be opened."
            return
        }
        guard let outcome = try? exportService.preview(archiveData: data) else {
            importFailure = "That file could not be read."
            return
        }
        switch outcome {
        case let .success(pair): pendingImport = pair
        case let .failure(failure): importFailure = failure.message
        }
    }

    private func applyImport(_ archive: BackupArchive) {
        do {
            try exportService.apply(archive: archive)
        } catch {
            importFailure = "The import did not finish. \(error.localizedDescription)"
        }
    }

    private func deleteAll() async {
        deleteConfirmationText = ""
        try? await exportService.deleteAllData()
        await dependencies.notifications.cancelAll()
        dependencies.snapshotPublisher.clear()
        storageBytes = 0
    }
}

/// Exactly what an import would do, before it does it.
struct ImportPreviewView: View {
    let preview: ImportPreview
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DetailRow(
                        label: "Backup taken",
                        value: Formatters.dateAndTime(preview.archiveGeneratedAt)
                    )
                    DetailRow(label: "Written by", value: preview.archiveAppVersion)
                    DetailRow(label: "Format version", value: "\(preview.formatVersion)")
                } header: {
                    Text("This file")
                }

                Section {
                    Text(preview.summary)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    countRow("Rental companies", preview.willAdd.vendors)
                    countRow("Jobsites", preview.willAdd.jobSites)
                    countRow("Agreements", preview.willAdd.agreements)
                    countRow("Rental items", preview.willAdd.items)
                    countRow("Timeline events", preview.willAdd.events)
                    countRow("Invoices", preview.willAdd.invoices)
                    countRow("Possible mismatches", preview.willAdd.discrepancies)
                    countRow("Attachments", preview.willAdd.assets)
                } header: {
                    Text("Will be added")
                }

                if preview.willSkipExisting.total > 0 {
                    Section {
                        Text("\(preview.willSkipExisting.total) records are already here and will be left alone.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Already here")
                    } footer: {
                        Text("Importing never overwrites. Anything you have done since this backup is safe.")
                    }
                }

                if preview.willSkipOrphaned.total > 0 {
                    Section {
                        Text("""
                            \(preview.willSkipOrphaned.total) records refer to something this file \
                            does not contain and cannot be imported on their own.
                            """)
                        .font(.footnote)
                        .foregroundStyle(Palette.attention)
                    } header: {
                        Text("Cannot be imported")
                    }
                }

                if !preview.missingEvidenceFiles.isEmpty {
                    Section {
                        Text("""
                            \(preview.missingEvidenceFiles.count) attachments are referenced but \
                            their files are not in this backup. The records will import and the \
                            attachments will show as missing.
                            """)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    } header: {
                        Text("Missing files")
                    }
                }
            }
            .offRentFormBackground()
            .navigationTitle("Review this import")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier(A11yID.Settings.importPreview)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: onConfirm).disabled(preview.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func countRow(_ label: String, _ count: Int) -> some View {
        if count > 0 { DetailRow(label: label, value: "\(count)") }
    }
}
