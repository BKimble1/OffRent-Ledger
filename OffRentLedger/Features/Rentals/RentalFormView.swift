import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The rental form, shared by New Rental and Edit Rental.
///
/// One definition of what a rental's fields are. The screens around it differ only in their
/// title, their save action and whether the capture section is offered — everything a user can
/// type is here, which is what makes "edit a rental completely" a property of the code rather
/// than a list somebody has to keep in step.
///
/// Company and jobsite are *selector rows*, not inline forms. Tapping one opens a searchable
/// list whose first row is `Add New`, and that opens the same reusable editor the Rentals plus
/// menu opens. A company created from inside a draft comes back to the draft, selected, with
/// nothing else lost.
struct RentalFormView: View {

    @Bindable var draft: RentalDraft
    /// New Rental offers the scanner; Edit Rental does not — a rental already has its evidence,
    /// and re-scanning over a saved record is a different operation with different consequences.
    var showsCapture: Bool = true
    /// Opens the scanner as the form appears. Set by the Today entry point.
    var startScanning: Bool = false

    @Environment(AppDependencies.self) private var dependencies

    @Query(sort: \Vendor.name) private var companies: [Vendor]
    @Query(sort: \JobSite.name) private var jobSites: [JobSite]

    @State private var choosingCompany = false
    @State private var choosingJobSite = false
    @State private var scanModel: ScanReviewViewModel?
    @State private var showingCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var scanError: String?
    /// Once only. Without the guard the camera reopens every time the form redraws — including
    /// the redraw that happens when the review sheet fills the draft.
    @State private var hasAutoStartedScan = false

    var body: some View {
        Form {
            equipmentSection
            if showsCapture { captureSection }
            partiesSection
            datesSection
            ratesSection
            moreDetailsSection
            rolloverSection
            notesSection
        }
        // A swipe on the form puts the keyboard away, which is what every iOS form does and
        // what this one could not do at all: only the currency fields had a Done button, so on a
        // plain text keyboard the rows below the caret stayed underneath the pinned Save bar
        // with no way to reach them. The UI suite found it by failing to tap the company row.
        .scrollDismissesKeyboard(.interactively)
        .offRentFormBackground()
        .sheet(isPresented: $choosingCompany) {
            CompanyPickerView(
                selection: $draft.companyID,
                initialSearch: draft.companyID == nil ? (draft.scannedCompanyName ?? "") : "",
                // Picking by hand is the user overruling the match, so the row stops claiming
                // the scan chose it.
                onPicked: { _ in draft.companyCameFromScan = false }
            )
        }
        .sheet(isPresented: $choosingJobSite) {
            JobsitePickerView(selection: $draft.jobSiteID)
        }
        .sheet(item: Binding(
            get: { scanModel.map { ScanSession(model: $0) } },
            set: { if $0 == nil { scanModel = nil } }
        )) { session in
            ScanReviewView(
                model: session.model,
                onSave: { values in
                    draft.apply(scanned: values)
                    adoptScannedCompany(named: session.model.scannedVendorName)
                    scanModel = nil
                },
                onCancel: { scanModel = nil },
                onRescan: {
                    // Close the review and put the camera straight back up. Anything else makes
                    // "Rescan" a button that asks the user to go and find the Scan button.
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
            handleFileImport(result)
        }
        .onAppear {
            // Today's scan card lands here. The camera comes up on its own, and on a device
            // without a document camera — a simulator, or an iPhone whose camera is unavailable —
            // it falls back to the PDF importer rather than doing nothing and looking broken.
            guard startScanning, showsCapture, !hasAutoStartedScan else { return }
            hasAutoStartedScan = true
            if DocumentScannerView.isSupported {
                showingCamera = true
            } else {
                showingFileImporter = true
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await handlePhoto(item) }
        }
        .alert(
            "Scan failed",
            isPresented: Binding(get: { scanError != nil }, set: { if !$0 { scanError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text((scanError ?? "") + "\n\nYou can still enter everything by hand.")
        }
    }

    // MARK: - Sections

    private var equipmentSection: some View {
        Section("Equipment") {
            // Deliberately not auto-focused.
            //
            // The old form put the cursor here on appear, which was right when the next thing
            // below was another text field. It is wrong now: the two rows this redesign exists
            // for — Rental company and Jobsite — sit just below the fold, and a keyboard raised
            // on appear puts them behind the pinned Save bar with nothing on screen suggesting
            // they are there. The UI suite found it by being unable to reach the company row at
            // all; a person would have found it by concluding the app could not do it.
            TextField("What is it?", text: $draft.equipmentName)
                .submitLabel(.next)
                .accessibilityIdentifier(A11yID.AddRental.equipmentName)
            TextField("Class or description (optional)", text: $draft.equipmentClass)
                .accessibilityIdentifier(A11yID.AddRental.equipmentClass)
        }
    }

    private var captureSection: some View {
        Section {
            if DocumentScannerView.isSupported {
                Button {
                    showingCamera = true
                } label: {
                    Label("Scan the rental contract", systemImage: "doc.viewfinder")
                }
                .accessibilityIdentifier(A11yID.AddRental.scanButton)

                Menu {
                    photoPickerButton
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Import a PDF", systemImage: "doc")
                    }
                } label: {
                    Label("Use a photo or PDF instead", systemImage: "ellipsis.circle")
                }
            } else {
                photoPickerButton
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Import a PDF", systemImage: "doc")
                }
            }
        } header: {
            Text("Fill this in from a document")
        } footer: {
            Text("Optional. Values are yours to check before anything is saved. \(AppCopy.ocrLocalOnly)")
        }
    }

    private var photoPickerButton: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            Label("Choose a photo of the contract", systemImage: "photo.on.rectangle")
        }
    }

    /// Company and jobsite: two rows, not two embedded forms.
    private var partiesSection: some View {
        Section {
            SelectorRow(
                title: "Rental company",
                value: selectedCompany?.name,
                // The row says where the value came from. A field the app filled in on the
                // user's behalf has to be visibly that, or the first time it matches the wrong
                // yard nobody will know to look.
                detail: companyDetail,
                placeholder: "Choose company",
                symbol: "building.2",
                identifier: A11yID.AddRental.companyRow
            ) {
                choosingCompany = true
            }

            SelectorRow(
                title: "Jobsite",
                value: selectedJobSite?.name,
                detail: selectedJobSite?.locationSummary,
                placeholder: "Choose jobsite",
                symbol: "mappin.and.ellipse",
                identifier: A11yID.AddRental.jobSiteRow
            ) {
                choosingJobSite = true
            }
        } header: {
            Text("Who and where")
        } footer: {
            if let scanned = draft.scannedCompanyName, draft.companyID == nil {
                // The document named a company the user does not have yet. A name read off a
                // letterhead is a string and the rental needs a record, so it is offered rather
                // than created — but the picker opens with it already typed in, so saying yes is
                // one tap and no typing.
                Text("The document said “\(scanned)”. Tap Rental company to add it.")
            } else if draft.companyCameFromScan {
                Text("Matched from the document you scanned. Tap it if that is the wrong yard.")
            } else {
                Text("Both are reusable. Pick them once and they are there for the next rental.")
            }
        }
    }

    private var companyDetail: String? {
        guard let selectedCompany else { return nil }
        if draft.companyCameFromScan {
            return selectedCompany.branch.map { "\($0) · from the scan" } ?? "From the scan"
        }
        return selectedCompany.branch
    }

    private var datesSection: some View {
        Section("Dates") {
            DatePicker(
                "Delivered",
                selection: $draft.deliveryDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier(A11yID.AddRental.deliveryDate)

            OptionalDatePicker(
                title: "Scheduled end (optional)",
                date: $draft.scheduledEndDate,
                identifier: A11yID.AddRental.scheduledEnd
            )
        }
    }

    private var ratesSection: some View {
        Section {
            CurrencyField(title: "Daily rate", value: $draft.dailyRate, identifier: A11yID.AddRental.dailyRate)
            CurrencyField(title: "Weekly rate", value: $draft.weeklyRate, identifier: A11yID.AddRental.weeklyRate)
            CurrencyField(title: "4-week rate", value: $draft.fourWeekRate, identifier: A11yID.AddRental.fourWeekRate)
            Picker("Currently billing", selection: $draft.billingBasis) {
                ForEach(BillingBasis.allCases, id: \.self) { basis in
                    Text(basis.displayName).tag(basis)
                }
            }
            .accessibilityIdentifier(A11yID.AddRental.billingBasis)
        } header: {
            Text("Rates from the contract")
        } footer: {
            Text("""
                Enter only the rates your contract actually quotes. \
                \(AppConfiguration.displayName) will not guess the others, and it will not pick a \
                cheaper combination on your behalf.
                """)
        }
    }

    /// The identifiers, folded away. They matter — they are how a rental is found six weeks
    /// later — and none of them is needed to save, so they do not belong above the rates.
    private var moreDetailsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $draft.showsMoreDetails) {
                TextField("Vendor equipment ID", text: $draft.vendorEquipmentIdentifier)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier(A11yID.AddRental.equipmentIdentifier)
                TextField("Serial number", text: $draft.serialNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier(A11yID.AddRental.serialNumber)
                TextField("Agreement or contract number", text: $draft.agreementNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier(A11yID.AddRental.agreementNumber)
                TextField("Your PO or reference", text: $draft.purchaseOrderNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier(A11yID.AddRental.purchaseOrder)
                Picker("Meter", selection: $draft.meterUnit) {
                    ForEach(MeterUnit.allCases, id: \.self) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
            } label: {
                Label("Identifiers and references", systemImage: "number")
            }
            .accessibilityIdentifier(A11yID.AddRental.moreDetails)
        } footer: {
            Text("""
                The vendor's agreement number and your own PO are different strings that both \
                appear on an invoice. Either one finds this rental in search and on the map.
                """)
        }
    }

    private var rolloverSection: some View {
        Section {
            Picker("When rates change", selection: $draft.rolloverMode) {
                ForEach(RolloverMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            Text(draft.rolloverMode.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if draft.rolloverMode == .manual {
                OptionalDatePicker(
                    title: "Next rate change",
                    date: $draft.nextRolloverDate,
                    identifier: A11yID.AddRental.nextRollover
                )
                CurrencyField(
                    title: "Expected to add",
                    value: $draft.expectedNextIncrement,
                    identifier: A11yID.AddRental.expectedIncrement
                )
            }
        } header: {
            Text("Rate changes")
        } footer: {
            Text("""
                Manual is the default because it assumes nothing. If you leave the next change \
                blank, \(AppConfiguration.displayName) simply will not show one.
                """)
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField(
                "Included hours, excess-hour terms, anything else",
                text: $draft.includedUsageNotes,
                axis: .vertical
            )
            .lineLimit(2...6)
            TextField("Your notes", text: $draft.notes, axis: .vertical)
                .lineLimit(2...6)
                .accessibilityIdentifier(A11yID.AddRental.notes)
        }
    }

    // MARK: - Derived

    private var selectedCompany: Vendor? {
        guard let id = draft.companyID else { return nil }
        return companies.first { $0.id == id }
    }

    /// Fills the company in from the letterhead, the only way it honestly can.
    ///
    /// A rental references a reusable `Vendor`; a scan yields a string. So the name is matched
    /// against the yards the user already has, and on a clear single match the row is filled in
    /// for them — which is what "if it finds a company name it should fill that in" means when
    /// the app is not allowed to invent records from OCR.
    ///
    /// With no match, the name is kept as a hint: the row's footer names it, and opening the
    /// picker starts with it typed into the search box, so creating it is one tap and no typing.
    private func adoptScannedCompany(named scanned: String?) {
        guard let scanned, !scanned.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        draft.scannedCompanyName = scanned
        guard draft.companyID == nil else { return }
        let identities = companies.map {
            CompanyIdentity(id: $0.id, name: $0.name, branch: $0.branch)
        }
        if let match = CompanyMatching.bestMatch(forScannedName: scanned, in: identities) {
            draft.companyID = match.identity.id
            draft.companyCameFromScan = true
        }
    }

    private var selectedJobSite: JobSite? {
        guard let id = draft.jobSiteID else { return nil }
        return jobSites.first { $0.id == id }
    }

    // MARK: - Scanning

    private struct ScanSession: Identifiable {
        let model: ScanReviewViewModel
        var id: ObjectIdentifier { ObjectIdentifier(model) }
    }

    private func startScan(_ configure: (ScanReviewViewModel) -> Void) {
        let model = ScanReviewViewModel(
            kind: .rentalContract,
            recognizer: dependencies.textRecognizer,
            calendar: dependencies.clock.calendar,
            intelligence: dependencies.documentIntelligence
        )
        scanModel = model
        configure(model)
    }

    private func handlePhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            scanError = "That photo could not be read."
            return
        }
        startScan { $0.recognise(imageData: [data], source: .photoLibrary) }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            // A security-scoped resource that is not released leaks a file handle for the life of
            // the process; on repeated imports that eventually fails.
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                scanError = "That PDF could not be opened."
                return
            }
            startScan { $0.recognise(pdf: data) }
        case let .failure(error):
            scanError = error.localizedDescription
        }
    }
}

/// A row that stands for a record: what is chosen, or what to choose.
///
/// Tappable across its whole width, which the old `Picker` rows were not — and which is most of
/// why the New Rental screen felt like a wall. A row that shows a name and a chevron is a
/// promise that tapping it goes somewhere.
struct SelectorRow: View {
    let title: String
    let value: String?
    var detail: String?
    let placeholder: String
    var symbol: String?
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.base) {
                if let symbol {
                    RowIcon(symbol: symbol, tint: value == nil ? .secondary : Palette.accent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                    Text(value ?? placeholder)
                        .font(Typography.rowTitle)
                        .foregroundStyle(value == nil ? Color.secondary : .primary)
                        .lineLimit(1)
                    if let detail, value != nil, !detail.isEmpty {
                        Text(detail)
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Space.snug)
                Image(systemName: "chevron.right")
                    .font(Typography.micro.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .minimumTapTarget()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value ?? placeholder)")
        .accessibilityHint("Opens the list to choose or add one.")
        .modifier(OptionalIdentifier(identifier: identifier))
    }
}

/// Applies an accessibility identifier only when there is one, so a row without one keeps
/// whatever the platform gives it rather than being labelled with an empty string.
private struct OptionalIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
