import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Backing up, moving to a new phone, and putting a backup back.
///
/// This used to live three rows down inside "Data and privacy", next to the delete button, which
/// is a strange place to keep the thing that stops you losing everything. Privacy is a statement;
/// this is a tool, and it gets its own screen and its own row in Settings.
///
/// The machinery is unchanged — `ExportService`, `BackupArchive` and the import preview are the
/// same ones that shipped. What is new is that the screen says when you last took a backup, and
/// says so plainly when you never have.
struct BackupAndTransferView: View {

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context

    @Query private var items: [RentalItem]

    /// Recorded on this device only, and only so the screen can tell you it has been a while.
    @AppStorage(BackupAndTransferView.lastBackupKey) private var lastBackupAt: Double = 0

    @State private var exportedCSV: URL?
    @State private var exportedBackup: URL?
    @State private var showingImporter = false
    @State private var pendingImport: (archive: BackupArchive, preview: ImportPreview)?
    @State private var importFailure: String?
    /// Why the last export did not produce a file.
    ///
    /// Shown in the card, not in an alert. There is already an `.alert` on this screen's modifier
    /// chain alongside a `.sheet`, and a second one there is how the import preview stops
    /// presenting. It also stays on screen, which an alert does not — a failed backup is worth
    /// leaving in front of somebody rather than dismissing in a tap.
    @State private var exportFailure: String?
    @State private var storageBytes: Int64 = 0
    @State private var busy = false

    static let lastBackupKey = "com.idlery.offrent.backup.lastExportedAt"

    private var exportService: ExportService {
        ExportService(context: context, clock: dependencies.clock, fileStore: dependencies.fileStore)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                status
                backUp
                moveToANewPhone
            }
            .padding(.horizontal, Space.comfortable)
            .padding(.top, Space.base)
            .padding(.bottom, Space.screenBottom)
        }
        .offRentScreen()
        .navigationTitle("Backup and transfer")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(A11yID.Settings.backupRoot)
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
    }

    // MARK: - Status

    private var status: some View {
        VStack(alignment: .leading, spacing: Space.base) {
            CardHeader(
                title: backupHeadline,
                subtitle: """
                    Your records live on this iPhone and nowhere else. If it is lost, replaced or \
                    wiped, a backup file is the only way any of this comes back.
                    """,
                symbol: backupSymbol,
                tint: backupTint
            )
            VStack(spacing: 0) {
                DetailRow(label: "Rentals stored", value: "\(items.count)")
                RowDivider(inset: 0)
                DetailRow(
                    label: "Photos and documents",
                    value: ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard()
    }

    private var lastBackupDate: Date? {
        lastBackupAt > 0 ? Date(timeIntervalSince1970: lastBackupAt) : nil
    }

    private var backupHeadline: String {
        guard let date = lastBackupDate else { return "No backup taken yet" }
        return "Last backup \(Formatters.dateAndTime(date))"
    }

    private var backupSymbol: String {
        lastBackupDate == nil ? "exclamationmark.triangle" : "checkmark.shield"
    }

    private var backupTint: Color {
        lastBackupDate == nil ? Palette.attention : Palette.settled
    }

    // MARK: - Back up

    private var backUp: some View {
        VStack(alignment: .leading, spacing: Space.base) {
            CardHeader(
                title: "Take a backup",
                subtitle: """
                    The backup is readable JSON. You can open it in any text editor and see \
                    exactly what is in it. Neither export needs a subscription.
                    """
            )

            ListGroup {
                // The subtitle used to end "…, attachments", and the file has never contained a
                // single one. `encodeArchive()` takes `includeEvidenceFiles` and every call site
                // leaves it false, and the archive is one JSON document with nowhere to put the
                // bytes. So a contractor following the three steps below arrived on a new phone
                // with every rental intact and every photograph gone, told nothing.
                ActionRow(
                    title: "Export your records",
                    subtitle: "Rentals, confirmations, pickups, invoices and their details",
                    symbol: "arrow.down.doc",
                    tint: Palette.accent,
                    isEnabled: !busy
                ) { Task { await exportBackup() } }
                    .accessibilityIdentifier(A11yID.Settings.exportBackup)

                // Both share rows are gated on the file being *there*. The state is only set
                // after a write that returned without throwing, and this checks the disk again
                // at the moment the row is drawn: the temporary directory is the system's to
                // empty, and a share sheet over a file that is no longer there is how somebody
                // emails an empty attachment to their accounts department.
                if let exportedBackup, FileManager.default.fileExists(atPath: exportedBackup.path) {
                    RowDivider()
                    ShareLink(item: exportedBackup) {
                        NavigationRow(
                            title: "Share the backup",
                            subtitle: "Send it to iCloud Drive, Files, or another phone",
                            symbol: "square.and.arrow.up"
                        )
                    }
                    .buttonStyle(.plain)
                }

                RowDivider()
                ActionRow(
                    title: "Export a CSV summary",
                    subtitle: "One row per rental, for a spreadsheet",
                    symbol: "tablecells",
                    isEnabled: !busy
                ) { Task { await exportCSV() } }
                    .accessibilityIdentifier(A11yID.Settings.exportCSV)

                if let exportedCSV, FileManager.default.fileExists(atPath: exportedCSV.path) {
                    RowDivider()
                    ShareLink(item: exportedCSV) {
                        NavigationRow(title: "Share the CSV", symbol: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                }
            }

            if let exportFailure {
                InlineAlert(message: exportFailure)
                    .accessibilityIdentifier(A11yID.Failure.backupExport)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard(padding: Space.base)
    }

    // MARK: - Restore

    private var moveToANewPhone: some View {
        VStack(alignment: .leading, spacing: Space.base) {
            CardHeader(title: "Move to a new iPhone")

            VStack(alignment: .leading, spacing: Space.snug) {
                step(1, "Export your records here and share the file somewhere you can reach — iCloud Drive, Files, an email to yourself.")
                step(2, "Install \(AppConfiguration.displayName) on the new iPhone.")
                step(3, "Come back to this screen there and import the file.")
                step(4, "Photographs and scanned documents do not travel in that file. Keep the old iPhone until you have what you need from it, or export the evidence packet for any rental whose photographs matter.")
            }

            ListGroup {
                ActionRow(
                    title: "Import a backup file",
                    subtitle: "You see exactly what will change before anything is written",
                    symbol: "arrow.up.doc",
                    tint: Palette.accent
                ) { showingImporter = true }
                    .accessibilityIdentifier(A11yID.Settings.importBackup)
                    // On the row that starts the import, not on the screen — where it sat beside
                    // `.sheet(item:)` for the import preview. One failed import and the preview
                    // sheet stopped presenting, so the next file the user picked was accepted
                    // with no chance to see what it would change.
                    .alert(
                        "Import failed",
                        isPresented: Binding(
                            get: { importFailure != nil },
                            set: { if !$0 { importFailure = nil } }
                        )
                    ) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(importFailure ?? "")
                    }
            }

            Text("""
                Importing only adds. It never overwrites or deletes what is already here, so \
                anything you have done since the backup is safe.
                """)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard(padding: Space.base)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.base) {
            Text("\(number)")
                .font(Typography.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.onAccent)
                .frame(width: 20, height: 20)
                .background(Palette.accent, in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(text)")
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

        // Every failure below used to be a `try?` and a `return`: the row did nothing, said
        // nothing, and — for the CSV — offered a share sheet over a file the write had just
        // failed to produce. An export that fails in silence is worse than one that fails,
        // because the user walks away believing they have a copy of their records.
        let csv: String
        do {
            csv = try exportService.makeCSVForAllItems()
        } catch {
            exportedCSV = nil
            exportFailure = """
                The CSV could not be built from your records. \(error.localizedDescription) \
                Try again, or export a backup instead.
                """
            return
        }

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OffRentLedger-rentals.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            exportedCSV = nil
            exportFailure = """
                The CSV could not be saved to this iPhone. \(error.localizedDescription) \
                Free up some space and try again.
                """
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            exportedCSV = nil
            exportFailure = "The CSV was not saved to this iPhone. Free up some space and try again."
            return
        }
        exportFailure = nil
        exportedCSV = url
    }

    private func exportBackup() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }

        let data: Data
        do {
            data = try exportService.encodeArchive()
        } catch {
            exportedBackup = nil
            exportFailure = """
                The backup could not be built from your records. \(error.localizedDescription) \
                Try again.
                """
            return
        }

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OffRentLedger-backup.json")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            exportedBackup = nil
            exportFailure = """
                The backup could not be saved to this iPhone. \(error.localizedDescription) \
                Free up some space and try again.
                """
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            exportedBackup = nil
            exportFailure = """
                The backup was not saved to this iPhone. Free up some space and try again.
                """
            return
        }

        exportFailure = nil
        exportedBackup = url
        // Recorded only once the file is actually on disk. A date stamped on the attempt would
        // tell somebody they were covered when they were not.
        lastBackupAt = dependencies.clock.now.timeIntervalSince1970
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
            // The whole store has just been replaced. Every cached estimate, the widget
            // snapshot, the Shortcuts index and every scheduled reminder describes rentals that
            // are no longer there — which on a new phone is the first thing the owner sees.
            dependencies.derivedStateNeedsRefresh()
        } catch {
            importFailure = "The import did not finish. \(error.localizedDescription)"
        }
    }
}
