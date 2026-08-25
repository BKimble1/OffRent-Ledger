import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Attaching a final invoice.
///
/// Same rule as the contract scan: OCR fills the form, the user checks it, and nothing is written
/// until Save. Manual entry is complete on its own.
struct AttachInvoiceSheet: View {

    let itemID: UUID
    /// The invoice to correct, or nil to attach a new one.
    ///
    /// Editing exists because of §8: an invoice that cannot be accepted because nothing was
    /// entered on it needs a way back to the form, and "delete it and start again" would take
    /// its attachments with it.
    var editing: UUID?

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var items: [RentalItem]
    @Query private var invoices: [VendorInvoice]

    @State private var invoiceNumber = ""
    @State private var receivedDate = Date()
    @State private var billedThroughDate: Date?
    @State private var invoiceTotal: Decimal?
    @State private var expectedOverride: Decimal?
    @State private var lines: [DraftLine] = []
    @State private var notes = ""

    @State private var scanModel: ScanReviewViewModel?
    @State private var showingCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var scanError: String?
    @State private var isSaving = false

    @State private var hasLoaded = false

    init(itemID: UUID, editing: UUID? = nil) {
        self.itemID = itemID
        self.editing = editing
        _items = Query(filter: #Predicate<RentalItem> { $0.id == itemID })
        // A predicate that can never match when nothing is being edited, rather than a second
        // query fetching every invoice in the store to find one that is not wanted. The item's
        // own identifier is the sentinel: an invoice can never carry it, and it needs no forced
        // unwrap of a string literal.
        let target = editing ?? itemID
        _invoices = Query(filter: #Predicate<VendorInvoice> { $0.id == target })
    }

    private var item: RentalItem? { items.first }
    private var existingInvoice: VendorInvoice? { editing == nil ? nil : invoices.first }

    struct DraftLine: Identifiable, Equatable {
        var id = UUID()
        var category: InvoiceCategory = .other
        var detail = ""
        var amount: Decimal?
        var appearedInContract = false
    }

    // The form's six sections are separate properties rather than one 150-line `body`.
    //
    // A result builder is type-checked as a single expression, so every section's constraints
    // are solved together: this body was the only one in the app still over the 300ms
    // -warn-long-function-bodies threshold, at 534ms. Split, each section is an independent and
    // much smaller problem — and the sections are individually readable, which matters more.

    private var scanSection: some View {
        Section {
            if DocumentScannerView.isSupported {
                Button { showingCamera = true } label: {
                    Label("Scan the invoice", systemImage: "doc.viewfinder")
                }
                .minimumTapTarget()
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose a photo", systemImage: "photo.on.rectangle")
            }
            .minimumTapTarget()
            Button { showingFileImporter = true } label: {
                Label("Import a PDF", systemImage: "doc")
            }
            .minimumTapTarget()
        } header: {
            Text("Start from the invoice (optional)")
        } footer: {
            Text(AppCopy.scanReviewExplanation)
        }
    }

    private var invoiceSection: some View {
        Section("Invoice") {
            TextField("Invoice number", text: $invoiceNumber)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            DatePicker("Received", selection: $receivedDate, displayedComponents: .date)
            OptionalDatePicker(title: "Billed through", date: $billedThroughDate)
            CurrencyField(title: "Invoice total", value: $invoiceTotal)
        }
    }

    private var linesSection: some View {
        Section {
            ForEach($lines) { $line in
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Category", selection: $line.category) {
                        ForEach(InvoiceCategory.allCases, id: \.self) { category in
                            Label(category.displayName, systemImage: category.symbolName)
                                .tag(category)
                        }
                    }
                    // Menu rather than the automatic style. Nine options behind a push means
                    // leaving the form and coming back for every line on an invoice, and the
                    // automatic style's choice between push and menu is not something a test can
                    // rely on either.
                    .pickerStyle(.menu)
                    .accessibilityIdentifier(A11yID.Audit.lineCategory)
                    TextField("Description (optional)", text: $line.detail)
                    CurrencyField(title: "Amount", value: $line.amount)
                    Toggle("This was in the terms I entered", isOn: $line.appearedInContract)
                        .minimumTapTarget()
                }
                .padding(.vertical, 2)
            }
            .onDelete { lines.remove(atOffsets: $0) }

            Button {
                lines.append(DraftLine())
            } label: {
                Label("Add a line", systemImage: "plus")
            }
            .minimumTapTarget()
        } header: {
            Text("Lines")
        } footer: {
            Text("""
                Enter the invoice's own breakdown. \(AppConfiguration.displayName) compares \
                the rental line against the terms you confirmed and asks you to review the \
                rest — it does not judge charges it knows nothing about.
                """)
        }
    }

    private var expectationSection: some View {
        Section {
            CurrencyField(title: "What you expected", value: $expectedOverride)
        } header: {
            Text("Your own expectation (optional)")
        } footer: {
            Text("""
                If you enter an amount here it replaces the one \(AppConfiguration.displayName) \
                derives. You have the contract; the app has what you typed in.
                """)
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...6)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                scanSection
                invoiceSection
                linesSection
                expectationSection
                notesSection
            }
            .offRentFormBackground()
            .safeAreaInset(edge: .bottom) {
                StickyActionBar {
                    Button("Save invoice", action: save)
                        .buttonStyle(.offRentPrimary)
                        .accessibilityIdentifier(A11yID.Audit.saveInvoice)
                        .disabled(isSaving)
                }
            }
            .navigationTitle(editing == nil ? "Attach invoice" : "Edit invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear(perform: load)
            .sheet(item: Binding(
                get: { scanModel.map { ScanSession(model: $0) } },
                set: { if $0 == nil { scanModel = nil } }
            )) { session in
                ScanReviewView(
                    model: session.model,
                    onSave: { values in
                        apply(scanned: values)
                        scanModel = nil
                    },
                    onCancel: { scanModel = nil },
                    onRescan: {
                        scanModel = nil
                        if DocumentScannerView.isSupported {
                            showingCamera = true
                        } else {
                            showingFileImporter = true
                        }
                    }
                )
            }
            .fullScreenCover(isPresented: $showingCamera) {
                DocumentScannerView(
                    onFinish: { pages in
                        showingCamera = false
                        startScan { $0.recognise(imageData: pages, source: .documentCamera) }
                    },
                    onCancel: { showingCamera = false },
                    onError: { error in
                        showingCamera = false
                        scanError = error.localizedDescription
                    }
                )
                .ignoresSafeArea()
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                guard case let .success(urls) = result, let url = urls.first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else {
                    scanError = "That PDF could not be opened."
                    return
                }
                startScan { $0.recognise(pdf: data) }
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    defer { photoItem = nil }
                    guard let data = try? await newItem.loadTransferable(type: Data.self) else {
                        scanError = "That photo could not be read."
                        return
                    }
                    startScan { $0.recognise(imageData: [data], source: .photoLibrary) }
                }
            }
            .alert(
                "Scan failed",
                isPresented: Binding(get: { scanError != nil }, set: { if !$0 { scanError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text((scanError ?? "") + "\n\nYou can still enter the invoice by hand.")
            }
        }
    }

    private struct ScanSession: Identifiable {
        let model: ScanReviewViewModel
        var id: ObjectIdentifier { ObjectIdentifier(model) }
    }

    private func startScan(_ configure: (ScanReviewViewModel) -> Void) {
        let model = ScanReviewViewModel(
            kind: .vendorInvoice,
            recognizer: dependencies.textRecognizer,
            calendar: dependencies.clock.calendar,
            intelligence: dependencies.documentIntelligence
        )
        scanModel = model
        configure(model)
    }

    private func apply(scanned values: [SuggestedField: SuggestedValue]) {
        for (field, value) in values {
            switch (field, value) {
            case let (.invoiceNumber, .text(text)): invoiceNumber = text
            case let (.invoiceTotal, .money(amount)): invoiceTotal = amount
            case let (.billedThroughDate, .date(date)): billedThroughDate = date
            default:
                // Charge categories become draft lines the user can edit or delete before saving.
                if let category = field.invoiceCategory, case let .money(amount) = value {
                    lines.append(
                        DraftLine(category: category, detail: "", amount: amount, appearedInContract: false)
                    )
                }
            }
        }
    }

    /// Fills the form from an invoice being corrected, or stamps today's date on a new one.
    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard let existing = existingInvoice else {
            receivedDate = dependencies.clock.now
            return
        }
        invoiceNumber = existing.invoiceNumber ?? ""
        receivedDate = existing.receivedDate
        billedThroughDate = existing.billedThroughDate
        invoiceTotal = existing.invoiceTotal == .zero ? nil : existing.invoiceTotal
        expectedOverride = existing.expectedRentalSubtotalOverride
        notes = existing.notes ?? ""
        lines = (existing.lines ?? [])
            .sorted { $0.sortIndex < $1.sortIndex }
            .map {
                DraftLine(
                    category: $0.category,
                    detail: $0.detail,
                    amount: $0.amount,
                    appearedInContract: $0.appearedInContract
                )
            }
    }

    private func save() {
        guard !isSaving, let item, let agreement = item.agreement else { return }
        isSaving = true
        defer { isSaving = false }

        let isNew = existingInvoice == nil
        let invoice: VendorInvoice
        if let existing = existingInvoice {
            invoice = existing
            invoice.invoiceNumber = invoiceNumber.nilIfBlank
            invoice.receivedDate = receivedDate
            invoice.billedThroughDate = billedThroughDate
            invoice.invoiceTotal = invoiceTotal ?? .zero
            invoice.notes = notes.nilIfBlank
            invoice.expectedRentalSubtotalOverride = expectedOverride
            // The lines are replaced wholesale. Reconciling them by identity would need a stable
            // key the draft does not carry, and the attachments and discrepancies — the evidence
            // — hang off the invoice, not off its lines, so they are untouched by this.
            for line in invoice.lines ?? [] { context.delete(line) }
        } else {
            invoice = VendorInvoice(
                invoiceNumber: invoiceNumber.nilIfBlank,
                receivedDate: receivedDate,
                billedThroughDate: billedThroughDate,
                invoiceTotal: invoiceTotal ?? .zero,
                reviewStatus: .notReviewed,
                notes: notes.nilIfBlank,
                attachedAt: dependencies.clock.now,
                expectedRentalSubtotalOverride: expectedOverride,
                agreement: agreement,
                primaryItemID: item.id
            )
            context.insert(invoice)
        }

        for (index, line) in lines.enumerated() {
            guard let amount = line.amount else { continue }
            context.insert(
                InvoiceLine(
                    category: line.category,
                    detail: line.detail,
                    amount: amount,
                    appearedInContract: line.appearedInContract,
                    sortIndex: index,
                    invoice: invoice
                )
            )
        }

        if isNew {
            // Only a new invoice moves the rental. Correcting one already under review must not
            // try to transition a rental that is already there — the state machine would refuse,
            // and the refusal would be the user's reward for fixing a typo.
            let workflow = RentalWorkflowService(context: context, clock: dependencies.clock)
            workflow.apply(.attachInvoice, to: item, detail: invoiceNumber.nilIfBlank)
        }
        try? context.save()
        dependencies.derivedStateNeedsRefresh()

        dismiss()
        guard isNew else { return }
        router.presentedSheet = nil
        router.handle(.invoiceReview(invoiceID: invoice.id))
    }
}
