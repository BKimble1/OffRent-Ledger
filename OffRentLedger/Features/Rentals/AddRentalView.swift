import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Creating a rental.
///
/// The manual path is the primary one and is complete on its own: no camera, no photo access, no
/// network, no account, no purchase. Scanning is an accelerator that fills the same fields, and
/// it always lands in the review sheet before touching anything here.
struct AddRentalView: View {

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(OnboardingState.self) private var onboarding

    @Query(sort: \Vendor.name) private var vendors: [Vendor]
    @Query(sort: \JobSite.name) private var jobSites: [JobSite]

    // Vendor
    @State private var selectedVendorID: UUID?
    @State private var newVendorName = ""
    @State private var newVendorBranch = ""
    @State private var newVendorPhone = ""
    @State private var newVendorEmail = ""

    // Jobsite
    @State private var selectedJobSiteID: UUID?
    @State private var newJobSiteName = ""

    // Agreement
    @State private var agreementNumber = ""
    @State private var deliveryDate = Date()
    @State private var scheduledEndDate: Date?

    // Equipment
    @State private var equipmentName = ""
    @State private var equipmentClass = ""
    @State private var vendorEquipmentIdentifier = ""
    @State private var serialNumber = ""
    @State private var meterUnit: MeterUnit = .hours

    // Terms
    @State private var dailyRate: Decimal?
    @State private var weeklyRate: Decimal?
    @State private var fourWeekRate: Decimal?
    @State private var billingBasis: BillingBasis = .daily
    @State private var rolloverMode: RolloverMode = .manual
    @State private var nextRolloverDate: Date?
    @State private var expectedNextIncrement: Decimal?
    @State private var includedUsageNotes = ""
    @State private var notes = ""

    // Scanning
    @State private var scanModel: ScanReviewViewModel?
    @State private var chosenPlace: ChosenPlace?
    @State private var showingPlaceSearch = false
    @State private var showingCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var scanError: String?
    @State private var isSaving = false
    @FocusState private var equipmentIsFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                // Equipment first. The document accelerator used to be three rows above it, so
                // the first thing on a screen called "New rental" was an optional shortcut and
                // the field you came to fill in was below the fold.
                equipmentSection
                captureSection
                vendorSection
                jobSiteSection
                agreementSection
                ratesSection
                rolloverSection
                notesSection
            }
            .accessibilityIdentifier(A11yID.AddRental.root)
            .offRentFormBackground()
            .safeAreaInset(edge: .bottom) { saveBar }
            .navigationTitle("New rental")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier(A11yID.AddRental.cancel)
                }
            }
            .onAppear {
                deliveryDate = dependencies.clock.now
                // Straight into the first field. The sheet exists to capture an equipment name;
                // making somebody tap once before they can type it is a tap for nothing.
                equipmentIsFocused = true
            }
            .sheet(isPresented: $showingPlaceSearch) {
                PlaceSearchView(initialQuery: newJobSiteName) { place in
                    chosenPlace = place
                    // The place names the site when the user has not. Somebody who searched for
                    // "Ridgeline Business Park" has already told us what to call it.
                    if newJobSiteName.trimmingCharacters(in: .whitespaces).isEmpty {
                        newJobSiteName = place.name
                    }
                }
            }
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
                    onCancel: { scanModel = nil }
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
    }

    /// Save, where the thumb is, on a form eight sections long.
    ///
    /// One primary action rather than a `Save` in the navigation bar: on this form the button is
    /// forty points from the top and the last field is two thousand points from it, and a
    /// disabled toolbar button gives no clue what is missing. This one says.
    private var saveBar: some View {
        StickyActionBar {
            VStack(spacing: Space.snug) {
                Button("Save rental", action: save)
                    .buttonStyle(.offRentPrimary)
                    .accessibilityIdentifier(A11yID.AddRental.save)
                    .disabled(!canSave || isSaving)
                if let missing = missingBeforeSave {
                    Text(missing)
                        .font(Typography.micro)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// What is still needed, named. `nil` once the form can be saved.
    private var missingBeforeSave: String? {
        let hasEquipment: Bool = !equipmentName.trimmingCharacters(in: .whitespaces).isEmpty
        let hasVendor: Bool = selectedVendorID != nil
            || !newVendorName.trimmingCharacters(in: .whitespaces).isEmpty
        switch (hasEquipment, hasVendor) {
        case (true, true): return nil
        case (false, true): return "Add the equipment name to save."
        case (true, false): return "Add the rental company to save."
        case (false, false): return "Add the equipment name and the rental company to save."
        }
    }

    // MARK: - Sections

    private var captureSection: some View {
        Section {
            // One row, not three. The scanner is the fast path when there is a contract in hand;
            // a photo and a PDF are the fallbacks, and a menu is where iOS puts fallbacks.
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
                // No document camera on this device, so the fallbacks are the only paths and
                // hiding them behind a menu would hide everything.
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

    private var vendorSection: some View {
        Section("Rental company") {
            Picker("Company", selection: $selectedVendorID) {
                Text("New rental company").tag(UUID?.none)
                ForEach(vendors, id: \.id) { vendor in Text(vendor.name).tag(UUID?.some(vendor.id)) }
            }
            .accessibilityIdentifier(A11yID.AddRental.vendorPicker)

            if selectedVendorID == nil {
                // Content types so iOS offers what it already knows. A contractor adding the
                // same rental yard for the third time should not be typing its phone number
                // from memory.
                TextField("Company name", text: $newVendorName)
                    .textContentType(.organizationName)
                    .accessibilityIdentifier(A11yID.AddRental.newVendorName)
                TextField("Branch (optional)", text: $newVendorBranch)
                    .textContentType(.sublocality)
                TextField("Phone (optional)", text: $newVendorPhone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                TextField("Email (optional)", text: $newVendorEmail)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    private var jobSiteSection: some View {
        Section("Jobsite") {
            Picker("Site", selection: $selectedJobSiteID) {
                Text("New jobsite").tag(UUID?.none)
                ForEach(jobSites, id: \.id) { site in Text(site.name).tag(UUID?.some(site.id)) }
            }
            .accessibilityIdentifier(A11yID.AddRental.jobSitePicker)

            if selectedJobSiteID == nil {
                TextField("Jobsite name (optional)", text: $newJobSiteName)
                    .accessibilityIdentifier(A11yID.AddRental.newJobSiteName)

                // A place is what puts this rental on the Today map. Optional, like the name:
                // plenty of rentals never leave one yard and never need one.
                if let chosenPlace {
                    LabeledContent("Place") {
                        Text(chosenPlace.singleLine)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Remove the place", role: .destructive) { self.chosenPlace = nil }
                        .accessibilityIdentifier(A11yID.Place.clear)
                } else {
                    Button {
                        showingPlaceSearch = true
                    } label: {
                        Label("Find this site on a map", systemImage: "mappin.and.ellipse")
                    }
                    .accessibilityIdentifier(A11yID.Place.choose)
                }
            }
        }
    }

    private var agreementSection: some View {
        Section("Agreement") {
            TextField("Agreement or contract number", text: $agreementNumber)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityIdentifier(A11yID.AddRental.agreementNumber)

            DatePicker("Delivered", selection: $deliveryDate, displayedComponents: [.date, .hourAndMinute])
                .accessibilityIdentifier(A11yID.AddRental.deliveryDate)

            OptionalDatePicker(title: "Scheduled end (optional)", date: $scheduledEndDate)
        }
    }

    private var equipmentSection: some View {
        Section("Equipment") {
            TextField("Equipment", text: $equipmentName)
                .focused($equipmentIsFocused)
                .submitLabel(.next)
                .accessibilityIdentifier(A11yID.AddRental.equipmentName)
            TextField("Class or description (optional)", text: $equipmentClass)
            TextField("Vendor equipment ID (optional)", text: $vendorEquipmentIdentifier)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            TextField("Serial number (optional)", text: $serialNumber)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Picker("Meter", selection: $meterUnit) {
                ForEach(MeterUnit.allCases, id: \.self) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }
        }
    }

    private var ratesSection: some View {
        Section {
            CurrencyField(title: "Daily rate", value: $dailyRate, identifier: A11yID.AddRental.dailyRate)
            CurrencyField(title: "Weekly rate", value: $weeklyRate, identifier: A11yID.AddRental.weeklyRate)
            CurrencyField(title: "4-week rate", value: $fourWeekRate, identifier: A11yID.AddRental.fourWeekRate)
            Picker("Currently billing", selection: $billingBasis) {
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

    private var rolloverSection: some View {
        Section {
            Picker("When rates change", selection: $rolloverMode) {
                ForEach(RolloverMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            Text(rolloverMode.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if rolloverMode == .manual {
                OptionalDatePicker(
                    title: "Next rate change",
                    date: $nextRolloverDate,
                    identifier: A11yID.AddRental.nextRollover
                )
                CurrencyField(
                    title: "Expected to add",
                    value: $expectedNextIncrement,
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
            TextField("Included hours, excess-hour terms, anything else", text: $includedUsageNotes, axis: .vertical)
                .lineLimit(2...6)
            TextField("Your notes", text: $notes, axis: .vertical)
                .lineLimit(2...6)
        }
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
            calendar: dependencies.clock.calendar
        )
        scanModel = model
        configure(model)
    }

    private func handlePhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        // The picker already hands back encoded data, which is exactly what the recogniser wants.
        // Decoding to a UIImage here only to re-encode downstream was wasted work as well as a
        // non-Sendable value crossing into an actor.
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

    /// Applies the values the user ticked in the review sheet. Fields the user did not tick are
    /// left exactly as they were.
    private func apply(scanned values: [SuggestedField: SuggestedValue]) {
        for (field, value) in values {
            switch (field, value) {
            case let (.vendorName, .text(text)):
                if selectedVendorID == nil { newVendorName = text }
            case let (.agreementNumber, .text(text)): agreementNumber = text
            case let (.equipmentName, .text(text)): equipmentName = text
            case let (.equipmentIdentifier, .text(text)): vendorEquipmentIdentifier = text
            case let (.serialNumber, .text(text)): serialNumber = text
            case let (.startDate, .date(date)): deliveryDate = date
            case let (.scheduledEndDate, .date(date)): scheduledEndDate = date
            case let (.dailyRate, .money(amount)): dailyRate = amount
            case let (.weeklyRate, .money(amount)): weeklyRate = amount
            case let (.fourWeekRate, .money(amount)): fourWeekRate = amount
            default: break
            }
        }
    }

    // MARK: - Saving

    private var canSave: Bool {
        let hasEquipment = !equipmentName.trimmingCharacters(in: .whitespaces).isEmpty
        let hasVendor = selectedVendorID != nil
            || !newVendorName.trimmingCharacters(in: .whitespaces).isEmpty
        return hasEquipment && hasVendor
    }

    private func save() {
        // Guards a double tap. Without it a slow save can insert the rental twice, and the free
        // tier then reports a limit the user did not reach.
        guard !isSaving, canSave else { return }
        isSaving = true
        defer { isSaving = false }

        let now = dependencies.clock.now
        let vendor: Vendor
        if let selectedVendorID, let existing = vendors.first(where: { $0.id == selectedVendorID }) {
            vendor = existing
        } else {
            vendor = Vendor(
                name: newVendorName.trimmingCharacters(in: .whitespaces),
                branch: newVendorBranch.nilIfBlank,
                phone: newVendorPhone.nilIfBlank,
                email: newVendorEmail.nilIfBlank,
                createdAt: now,
                modifiedAt: now
            )
            context.insert(vendor)
        }

        var site: JobSite?
        if let selectedJobSiteID {
            site = jobSites.first { $0.id == selectedJobSiteID }
        } else if let name = newJobSiteName.nilIfBlank ?? chosenPlace?.name {
            let created = JobSite(
                name: name,
                address: chosenPlace?.address.nilIfBlank,
                placeName: chosenPlace?.name,
                latitude: chosenPlace?.latitude,
                longitude: chosenPlace?.longitude,
                createdAt: now,
                modifiedAt: now
            )
            context.insert(created)
            site = created
        }

        let agreement = RentalAgreement(
            agreementNumber: agreementNumber.nilIfBlank,
            startDate: deliveryDate,
            scheduledEndDate: scheduledEndDate,
            notes: nil,
            createdAt: now,
            modifiedAt: now,
            vendor: vendor,
            jobSite: site
        )
        context.insert(agreement)

        let terms = RentalTerms(
            deliveryDate: deliveryDate,
            rateCard: RateCard(daily: dailyRate, weekly: weeklyRate, fourWeek: fourWeekRate),
            billingBasis: billingBasis,
            rolloverMode: rolloverMode,
            nextRolloverDate: nextRolloverDate,
            expectedNextIncrement: expectedNextIncrement,
            includedUsageNotes: includedUsageNotes.nilIfBlank
        )

        let workflow = RentalWorkflowService(context: context, clock: dependencies.clock)
        let created = workflow.createItem(
            equipmentName: equipmentName.trimmingCharacters(in: .whitespaces),
            equipmentClass: equipmentClass.nilIfBlank,
            vendorEquipmentIdentifier: vendorEquipmentIdentifier.nilIfBlank,
            serialNumber: serialNumber.nilIfBlank,
            terms: terms,
            meterUnit: meterUnit,
            notes: notes.nilIfBlank,
            in: agreement
        )

        try? context.save()
        // The walkthrough follows this one from here on, so the bar keeps pointing at the
        // machine the user just made rather than at whatever happens to be newest later.
        onboarding.followGuidedTourItem(created.id)
        dismiss()
    }
}

/// A date picker that can genuinely be empty. `DatePicker` cannot, and defaulting a blank
/// "scheduled end" to today would put a date on the record the user never gave.
struct OptionalDatePicker: View {
    let title: String
    @Binding var date: Date?
    var identifier: String?

    var body: some View {
        VStack(alignment: .leading) {
            Toggle(title, isOn: Binding(
                get: { date != nil },
                set: { date = $0 ? (date ?? Date()) : nil }
            ))
            .minimumTapTarget()

            if date != nil {
                DatePicker(
                    title,
                    selection: Binding(get: { date ?? Date() }, set: { date = $0 }),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .accessibilityIdentifier(identifier ?? "optionalDate.\(title)")
            }
        }
    }
}

extension String {
    /// nil rather than "". A stored empty string reads as "the user entered nothing here", which
    /// is not the same as "the user left it blank" once it reaches an export or a PDF.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
