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

    /// Charge-shaped lines the scan read and no rule understood, kept in front of the user
    /// instead of dropped. See `unreadSection`.
    @State private var unreadLines: [UnreadInvoiceLine] = []
    /// Fields the scan produced that this form had nowhere to put, plus the ones the user ticked
    /// whose text could not be read as a value.
    @State private var unreadFieldNames: [String] = []

    @State private var scanModel: ScanReviewViewModel?
    @State private var showingCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var scanError: String?
    @State private var isSaving = false
    /// Set when the store refuses the save, and the reason nothing dismisses.
    @State private var saveFailure: String?

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
        Section {
            TextField("Invoice number", text: $invoiceNumber)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            DatePicker("Received", selection: $receivedDate, displayedComponents: .date)
            OptionalDatePicker(title: "Billed through", date: $billedThroughDate)
            CurrencyField(title: "Invoice total", value: $invoiceTotal, isRequired: true)
        } header: {
            Text("Invoice")
        } footer: {
            RequiredLegend()
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

    /// What the scan read and this form could not use.
    ///
    /// The parser reports the lines it could not interpret, and until now this screen threw them
    /// away. On a vendor invoice that is not a cosmetic loss: a charge no rule recognised simply
    /// never became a line, so the invoice was recorded smaller than the one in the user's hand —
    /// and the comparison they take back to the yard was built from the smaller one.
    ///
    /// Nothing here is added automatically. A line reading `TOTAL DUE $3,214.00` is charge-shaped
    /// and would double-count, and only the person holding the invoice can tell the difference.
    /// So each is shown verbatim, with one tap to put it in Lines above, where it can be
    /// categorised and corrected like any other.
    @ViewBuilder
    private var unreadSection: some View {
        if !unreadLines.isEmpty || !unreadFieldNames.isEmpty {
            Section {
                ForEach(unreadLines) { line in
                    Button {
                        lines.append(
                            DraftLine(category: .other, detail: line.text, amount: line.amount)
                        )
                        unreadLines.removeAll { $0.id == line.id }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(line.text)
                                .font(.caption.monospaced())
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Label("Add this as a line", systemImage: "plus.circle")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.accentText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(A11yID.Failure.unreadInvoiceLine)
                    .accessibilityHint("Double tap to add this line to the invoice.")
                    .minimumTapTarget()
                }

                if !unreadFieldNames.isEmpty {
                    InlineAlert(message: unusableFieldMessage)
                }
            } header: {
                Text("Not read from the scan")
            } footer: {
                Text(unreadFooter)
            }
        }
    }

    private var unusableFieldMessage: String {
        let names = unreadFieldNames.joined(separator: ", ")
        let subject = unreadFieldNames.count == 1 ? "it" : "them"
        return """
            Ticked on the scan but not filled in, because what was on screen could not be read as \
            a value: \(names). Enter \(subject) by hand.
            """
    }

    private var unreadFooter: String {
        guard !unreadLines.isEmpty else {
            return "Everything else the scan read is in the form above."
        }
        let count = unreadLines.count
        let subject = count == 1 ? "1 line" : "\(count) lines"
        let pronoun = count == 1 ? "it is" : "they are"
        return """
            \(subject) on the document carried an amount that no rule understood, so \(pronoun) \
            not in the lines above. Add or ignore each one — until you do, the lines add up to \
            less than the invoice does.
            """
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
                unreadSection
                expectationSection
                notesSection
            }
            .offRentFormBackground()
            .safeAreaInset(edge: .bottom) {
                StickyActionBar {
                    VStack(spacing: Space.snug) {
                        if let saveFailure {
                            InlineAlert(message: saveFailure)
                        }
                        Button("Save invoice", action: save)
                            .buttonStyle(.offRentPrimary)
                            .accessibilityIdentifier(A11yID.Audit.saveInvoice)
                            .disabled(isSaving || linesMissingAnAmount > 0)
                        if let missing = missingAmountExplanation {
                            Text(missing)
                                .font(Typography.micro)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier(A11yID.Audit.lineNeedsAnAmount)
                        }
                    }
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
                        apply(scanned: values, from: session.model)
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
        // Invoice lines are a table. A table needs width, and an iPad form sheet has none spare.
        .offRentRoomySheet()
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

    /// Fills the form from a scan, and keeps whatever it could not use in front of the user.
    ///
    /// Three things used to fall off here without a word, and every one of them made the recorded
    /// invoice smaller than the paper one: a value the user ticked whose text would not parse, a
    /// value with no home on this form, and every charge line the parser could not interpret.
    private func apply(
        scanned values: [SuggestedField: SuggestedValue],
        from model: ScanReviewViewModel
    ) {
        var unused: Set<SuggestedField> = []
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
                } else {
                    unused.insert(field)
                }
            }
        }

        // The fields the review screen dropped for being unparseable are named here too. The
        // user ticked those rows and has no other way to learn that nothing came of it.
        unused.formUnion(model.unusableSelections)
        unreadFieldNames = unused.map(\.displayName).sorted()
        unreadLines = UnreadInvoiceLines.chargeCandidates(in: model.result?.unmatchedLines ?? [])
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

    /// Lines the user has given a description but no figure.
    ///
    /// `save` skips a line with no amount, so before this the description was typed, the line was
    /// on screen, Save was pressed, and the line was gone — with the invoice quietly totalling
    /// less than the paper it was copied from. This is the one screen where that matters most.
    private var linesMissingAnAmount: Int {
        lines.filter { $0.amount == nil && !$0.detail.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    private var missingAmountExplanation: String? {
        let count = linesMissingAnAmount
        guard count > 0 else { return nil }
        return count == 1
            ? "One line still needs an amount. Fill it in, or swipe the line away."
            : "\(count) lines still need an amount. Fill them in, or swipe them away."
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

        // `linesMissingAnAmount` keeps the Save button disabled while any of these exist, so
        // this can no longer discard a line somebody typed a description into. It stays a
        // `continue` rather than a crash because a race between the two is not worth a trap.
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
        // Nothing closes until the record is on disk. The sheet used to dismiss whether or not
        // the save landed and then send the user to a review screen for an invoice that might
        // never have been written — the app reporting a filed invoice it did not have.
        if let failure = PersistentStore.save(context, describing: "This invoice") {
            // Take the insert back before inviting a retry. On a new invoice this has already
            // inserted a `VendorInvoice`, its lines, and a timeline entry; without the rollback a
            // second tap on Save filed the same piece of paper twice, and two invoices against
            // one rental is exactly the confusion this screen exists to prevent.
            context.rollback()
            saveFailure = failure
            return
        }
        saveFailure = nil
        dependencies.derivedStateNeedsRefresh()

        dismiss()
        guard isNew else { return }
        router.presentedSheet = nil
        router.handle(.invoiceReview(invoiceID: invoice.id))
    }
}
