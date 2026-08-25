import SwiftData
import SwiftUI

/// What is on this iPhone, what the app never does with it, and how to remove all of it.
///
/// Export and import moved to `BackupAndTransferView`. Keeping the thing that saves your records
/// on the same screen as the thing that erases them was a filing decision, not a design one, and
/// it hid the backup from everybody who was not already looking for it.
///
/// The rule this screen still honours: a user can always delete their data, at any entitlement
/// state, without asking anybody.
struct DataAndPrivacyView: View {

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var context

    @Query private var items: [RentalItem]

    @State private var showingDeleteConfirmation = false
    @State private var deleteConfirmationText = ""
    @State private var storageBytes: Int64 = 0
    /// What the delete actually did, read back from the store and the disk afterwards.
    ///
    /// A row in the List rather than a second `.alert`: this screen already has one, and it also
    /// means the sentence stays on screen next to the counts it is talking about.
    @State private var deleteReport: String?
    @State private var deleteLeftSomething = false

    private var exportService: ExportService {
        ExportService(context: context, clock: dependencies.clock, fileStore: dependencies.fileStore)
    }

    var body: some View {
        List {
            if let deleteReport {
                Section {
                    InlineAlert(
                        message: deleteReport,
                        kind: deleteLeftSomething ? .attention : .positive
                    )
                    .accessibilityIdentifier(A11yID.Failure.deleteAllOutcome)
                }
            }

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
                NavigationLink(value: SettingsDestination.backupAndTransfer) {
                    Label("Backup and transfer", systemImage: "arrow.down.doc")
                }
                .accessibilityIdentifier(A11yID.Settings.backupAndTransfer)
            } header: {
                Text("Getting your data out")
            } footer: {
                Text("""
                    Exporting a backup, moving to a new iPhone and importing a file all live \
                    there. Neither export needs a subscription.
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
                privacyPoint("Scanning, text recognition and the on-device model all run on this iPhone only")
                privacyPoint("Location is asked for once, when you tap for it, and never in the background")
            }
        }
        .offRentFormBackground()
        .navigationTitle("Data and privacy")
        .navigationBarTitleDisplayMode(.inline)
        .task { storageBytes = await dependencies.fileStore.totalBytesOnDisk() }
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

    // MARK: - Actions

    /// Deletes everything, then checks whether it did.
    ///
    /// This used to be `try? await exportService.deleteAllData()` followed by `storageBytes = 0`
    /// — the screen reported an empty iPhone whether or not the delete had thrown, and `0` was a
    /// number assigned rather than a number measured. On the one irreversible action in the app,
    /// on the screen that promises there is no server copy, that is the wrong way round: the
    /// only honest report is the one taken from the store and the disk afterwards.
    private func deleteAll() async {
        deleteConfirmationText = ""
        deleteReport = nil

        var failure: String?
        do {
            try await exportService.deleteAllData()
        } catch {
            failure = error.localizedDescription
        }

        await dependencies.notifications.cancelAll()
        dependencies.snapshotPublisher.clear()

        let remaining = try? remainingRecordCount()
        let remainingBytes = await dependencies.fileStore.totalBytesOnDisk()
        storageBytes = remainingBytes

        if failure == nil, remaining == 0, remainingBytes == 0 {
            deleteLeftSomething = false
            deleteReport = "Everything has been removed from this iPhone."
        } else {
            deleteLeftSomething = true
            deleteReport = Self.incompleteDeletionReport(
                records: remaining, bytes: remainingBytes, failure: failure
            )
        }
    }

    /// Everything the delete was supposed to take. Throws rather than reporting zero, because
    /// "nothing is left" and "I could not look" are different answers.
    private func remainingRecordCount() throws -> Int {
        var total = try context.fetch(StoreQueries.allItems()).count
        total += try context.fetch(StoreQueries.allInvoices()).count
        total += try context.fetch(StoreQueries.allAgreements()).count
        total += try context.fetch(StoreQueries.allJobSites()).count
        total += try context.fetch(StoreQueries.allVendors()).count
        total += try context.fetch(StoreQueries.allAssets()).count
        return total
    }

    /// Says what is still here and what to do about it. Specific, and never alarming.
    private static func incompleteDeletionReport(
        records: Int?, bytes: Int64, failure: String?
    ) -> String {
        var parts: [String] = []
        if let records, records > 0 {
            parts.append(records == 1 ? "1 record" : "\(records) records")
        }
        if bytes > 0 {
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            parts.append("\(size) of photos and documents")
        }

        var message = parts.isEmpty
            ? "The delete did not finish."
            : "The delete did not finish. \(parts.joined(separator: " and ")) are still on this iPhone."
        if records == nil {
            message += " What is left could not be counted."
        }
        if let failure {
            message += " \(failure)"
        }
        message += " Tap Delete all data again, and if it keeps failing, restart \(AppConfiguration.displayName)."
        return message
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
                        .foregroundStyle(Palette.attentionText)
                    } header: {
                        Text("Cannot be imported")
                    }
                }

                if preview.assetsWithoutFiles > 0 {
                    Section {
                        Text("""
                            This file carries records, not photographs. \
                            \(preview.assetsWithoutFiles) attachment\
                            \(preview.assetsWithoutFiles == 1 ? "" : "s") will import as \
                            entries with no image behind them. Anything else in the backup comes \
                            across in full.
                            """)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    } header: {
                        Text("Photographs and documents")
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
