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
                ActionRow(
                    title: "Export a full backup file",
                    subtitle: "Everything: rentals, confirmations, pickups, invoices, attachments",
                    symbol: "arrow.down.doc",
                    tint: Palette.accent,
                    isEnabled: !busy
                ) { Task { await exportBackup() } }
                    .accessibilityIdentifier(A11yID.Settings.exportBackup)

                if let exportedBackup {
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

                if let exportedCSV {
                    RowDivider()
                    ShareLink(item: exportedCSV) {
                        NavigationRow(title: "Share the CSV", symbol: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                }
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
                step(1, "Export a full backup here and share it somewhere you can reach — iCloud Drive, Files, an email to yourself.")
                step(2, "Install \(AppConfiguration.displayName) on the new iPhone.")
                step(3, "Come back to this screen there and import the file.")
            }

            ListGroup {
                ActionRow(
                    title: "Import a backup file",
                    subtitle: "You see exactly what will change before anything is written",
                    symbol: "arrow.up.doc",
                    tint: Palette.accent
                ) { showingImporter = true }
                    .accessibilityIdentifier(A11yID.Settings.importBackup)
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
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
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
