import PhotosUI
import SwiftData
import SwiftUI

/// The full, un-truncated event history for one item.
struct RentalTimelineView: View {
    let itemID: UUID
    @Query private var items: [RentalItem]

    init(itemID: UUID) {
        self.itemID = itemID
        _items = Query(filter: #Predicate<RentalItem> { $0.id == itemID })
    }

    var body: some View {
        List {
            if let item = items.first {
                ForEach(item.sortedEvents.reversed(), id: \.id) { event in
                    TimelineRow(event: event)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if items.first?.events?.isEmpty ?? true {
                EmptyStateView(
                    symbol: "clock",
                    title: "Nothing recorded yet",
                    message: "Events appear here as you work through the rental."
                )
            }
        }
    }
}

struct AgreementDetailView: View {
    let agreementID: UUID
    @Query private var agreements: [RentalAgreement]

    init(agreementID: UUID) {
        self.agreementID = agreementID
        _agreements = Query(filter: #Predicate<RentalAgreement> { $0.id == agreementID })
    }

    var body: some View {
        List {
            if let agreement = agreements.first {
                Section("Agreement") {
                    DetailRow(label: "Number", value: agreement.agreementNumber ?? "Not recorded")
                    DetailRow(label: "Start", value: Formatters.mediumDate(agreement.startDate))
                    if let end = agreement.scheduledEndDate {
                        DetailRow(label: "Scheduled end", value: Formatters.mediumDate(end))
                    }
                    if let window = agreement.disputeWindowDaysOverride {
                        DetailRow(label: "Review window", value: "\(window) days")
                    }
                }
                Section("Equipment on this agreement") {
                    ForEach(agreement.items ?? [], id: \.id) { item in
                        NavigationLink(value: RentalDestination.item(id: item.id)) {
                            HStack {
                                Text(item.equipmentName)
                                Spacer()
                                StatusChip(status: item.status, compact: true)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Agreement")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct VendorListView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var context
    @Query(sort: \Vendor.name) private var vendors: [Vendor]
    @State private var editing: Vendor?

    var body: some View {
        List {
            ForEach(vendors) { vendor in
                Button { editing = vendor } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(vendor.name).font(.body)
                        if let detail = [vendor.branch, vendor.phone].compactMap({ $0 }).first {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .minimumTapTarget()
            }
            .onDelete { offsets in
                // Deleting a vendor cascades to its agreements and everything under them, so the
                // confirmation says so plainly rather than relying on the user to know.
                for index in offsets { context.delete(vendors[index]) }
                try? context.save()
            }
        }
        .navigationTitle("Rental companies")
        .overlay {
            if vendors.isEmpty {
                EmptyStateView(
                    symbol: "building.2",
                    title: "No rental companies yet",
                    message: "They are created as you add rentals."
                )
            }
        }
        .sheet(item: $editing) { vendor in VendorEditView(vendor: vendor) }
    }
}

struct VendorEditView: View {
    @Bindable var vendor: Vendor
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $vendor.name)
                    TextField("Branch", text: Binding(
                        get: { vendor.branch ?? "" }, set: { vendor.branch = $0.nilIfBlank }
                    ))
                }
                Section {
                    TextField("Phone", text: Binding(
                        get: { vendor.phone ?? "" }, set: { vendor.phone = $0.nilIfBlank }
                    ))
                    .keyboardType(.phonePad)
                    TextField("Email", text: Binding(
                        get: { vendor.email ?? "" }, set: { vendor.email = $0.nilIfBlank }
                    ))
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    TextField("Website or app link", text: Binding(
                        get: { vendor.link ?? "" }, set: { vendor.link = $0.nilIfBlank }
                    ))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                } header: {
                    Text("How you reach them")
                } footer: {
                    Text("""
                        These become the Call, Email and Open-link buttons on the Contact Vendor \
                        step. \(AppConfiguration.displayName) opens them for you — it never sends \
                        anything itself.
                        """)
                }
                Section("Notes") {
                    TextField("Standard notes", text: Binding(
                        get: { vendor.standardNotes ?? "" },
                        set: { vendor.standardNotes = $0.nilIfBlank }
                    ), axis: .vertical)
                    .lineLimit(2...6)
                }
            }
            .navigationTitle("Rental company")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        vendor.modifiedAt = dependencies.clock.now
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct JobSiteListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \JobSite.name) private var jobSites: [JobSite]

    var body: some View {
        List {
            ForEach(jobSites) { site in
                VStack(alignment: .leading, spacing: 3) {
                    Text(site.name)
                    if let project = site.projectIdentifier {
                        Text(project).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                // Nullify, not cascade: deleting a jobsite label must not delete the rentals that
                // happened there. The relationship's delete rule enforces it; this just triggers.
                for index in offsets { context.delete(jobSites[index]) }
                try? context.save()
            }
        }
        .navigationTitle("Jobsites")
        .overlay {
            if jobSites.isEmpty {
                EmptyStateView(
                    symbol: "mappin.and.ellipse",
                    title: "No jobsites yet",
                    message: "They are created as you add rentals."
                )
            }
        }
    }
}

struct EditRentalItemView: View {
    let itemID: UUID

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [RentalItem]

    init(itemID: UUID) {
        self.itemID = itemID
        _items = Query(filter: #Predicate<RentalItem> { $0.id == itemID })
    }

    var body: some View {
        Form {
            if let item = items.first {
                Section("Equipment") {
                    TextField("Equipment", text: Binding(
                        get: { item.equipmentName }, set: { item.equipmentName = $0 }
                    ))
                    TextField("Class", text: Binding(
                        get: { item.equipmentClass ?? "" },
                        set: { item.equipmentClass = $0.nilIfBlank }
                    ))
                }
                Section("Rates") {
                    CurrencyField(title: "Daily", value: Binding(
                        get: { item.dailyRate }, set: { item.dailyRate = $0 }
                    ))
                    CurrencyField(title: "Weekly", value: Binding(
                        get: { item.weeklyRate }, set: { item.weeklyRate = $0 }
                    ))
                    CurrencyField(title: "4-week", value: Binding(
                        get: { item.fourWeekRate }, set: { item.fourWeekRate = $0 }
                    ))
                    Picker("Currently billing", selection: Binding(
                        get: { item.terms.billingBasis },
                        set: { item.billingBasisRaw = $0.rawValue }
                    )) {
                        ForEach(BillingBasis.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                Section("Rate changes") {
                    OptionalDatePicker(title: "Next rate change", date: Binding(
                        get: { item.nextRolloverDate }, set: { item.nextRolloverDate = $0 }
                    ))
                    CurrencyField(title: "Expected to add", value: Binding(
                        get: { item.expectedNextIncrement },
                        set: { item.expectedNextIncrement = $0 }
                    ))
                }
                Section("Notes") {
                    TextField("Included usage", text: Binding(
                        get: { item.includedUsageNotes ?? "" },
                        set: { item.includedUsageNotes = $0.nilIfBlank }
                    ), axis: .vertical)
                    .lineLimit(2...6)
                    TextField("Notes", text: Binding(
                        get: { item.notes ?? "" }, set: { item.notes = $0.nilIfBlank }
                    ), axis: .vertical)
                    .lineLimit(2...6)
                }
            }
        }
        .navigationTitle("Edit terms")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    if let item = items.first {
                        item.modifiedAt = dependencies.clock.now
                        // Editing a rate changes the estimate and can move the next rate change,
                        // so both the cache and the reminders are recomputed rather than left to
                        // drift until the next launch.
                        RentalWorkflowService(context: context, clock: dependencies.clock)
                            .refreshEstimate(for: item)
                    }
                    try? context.save()
                    dismiss()
                }
            }
        }
    }
}

/// A thumbnail strip of attachments.
struct EvidenceGrid: View {
    let assets: [EvidenceAsset]
    let fileStore: any FileStoring

    var body: some View {
        if assets.isEmpty {
            Text("No photos or documents yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(assets, id: \.id) { asset in
                        EvidenceThumbnail(asset: asset, fileStore: fileStore)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct EvidenceThumbnail: View {
    let asset: EvidenceAsset
    let fileStore: any FileStoring
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: asset.mediaType == .pdf ? "doc.richtext" : "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Text(asset.displayName)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 72)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(asset.mediaType.displayName): \(asset.displayName)")
        .task {
            // Thumbnails only. Decoding the full image here is what makes a list of attachments
            // stutter and, with enough of them, get the app jettisoned.
            let path = asset.thumbnailRelativePath ?? asset.relativePath
            guard asset.mediaType == .image else { return }
            let url = fileStore.url(forRelativePath: path)
            let loaded = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return UIImage(data: data)
            }.value
            image = loaded
        }
    }
}

/// Add, caption and remove attachments.
struct EvidenceManagerView: View {
    let itemID: UUID

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var context
    @Query private var items: [RentalItem]

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var isImporting = false

    init(itemID: UUID) {
        self.itemID = itemID
        _items = Query(filter: #Predicate<RentalItem> { $0.id == itemID })
    }

    var body: some View {
        List {
            Section {
                PhotosPicker(selection: $photoItems, matching: .images) {
                    Label("Add photos", systemImage: "photo.on.rectangle")
                }
                .minimumTapTarget()

                if DocumentScannerView.isSupported {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Scan a document", systemImage: "doc.viewfinder")
                    }
                    .minimumTapTarget()
                }
                if isImporting { ProgressView("Saving…") }
            } footer: {
                Text("""
                    Photos are copied into \(AppConfiguration.displayName) and stored on this \
                    iPhone. They are not uploaded anywhere.
                    """)
            }

            if let item = items.first, let assets = item.assets, !assets.isEmpty {
                Section("Attachments") {
                    ForEach(assets, id: \.id) { asset in
                        VStack(alignment: .leading, spacing: 6) {
                            EvidenceThumbnail(asset: asset, fileStore: dependencies.fileStore)
                            TextField("Caption", text: Binding(
                                get: { asset.caption ?? "" },
                                set: { asset.caption = $0.nilIfBlank }
                            ))
                            Text(Formatters.dateAndTime(asset.capturedAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let digest = asset.sha256 {
                                Text("SHA-256 \(digest.prefix(16))…")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(AppCopy.checksumExplanation)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Attachments")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await importPhotos(newItems) }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            DocumentScannerView(
                onFinish: { images in
                    showingCamera = false
                    Task { await save(images: images) }
                },
                onCancel: { showingCamera = false },
                onError: { _ in showingCamera = false }
            )
            .ignoresSafeArea()
        }
    }

    private func importPhotos(_ selected: [PhotosPickerItem]) async {
        isImporting = true
        defer { isImporting = false; photoItems = [] }
        var images: [UIImage] = []
        for item in selected {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            images.append(image)
        }
        await save(images: images)
    }

    private func save(images: [UIImage]) async {
        guard let item = items.first, !images.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }

        for (index, image) in images.enumerated() {
            let basename = "\(Int(dependencies.clock.now.timeIntervalSince1970))-\(index)"
            guard let stored = try? await dependencies.fileStore.writeImage(
                image, ownerFolder: item.id.uuidString, basename: basename
            ) else { continue }

            let asset = EvidenceAsset(
                relativePath: stored.relativePath,
                mediaType: .image,
                displayName: "Photo \((item.assets?.count ?? 0) + 1)",
                capturedAt: dependencies.clock.now,
                sha256: stored.sha256,
                thumbnailRelativePath: stored.thumbnailRelativePath,
                item: item
            )
            context.insert(asset)
        }
        RentalWorkflowService(context: context, clock: dependencies.clock)
            .append(event: .conditionCaptured, to: item, detail: "\(images.count) photo(s) attached.")
        try? context.save()
    }

    private func delete(_ offsets: IndexSet) {
        guard let item = items.first, let assets = item.assets else { return }
        let doomed = offsets.map { assets[$0] }
        let paths = doomed.flatMap { [$0.relativePath, $0.thumbnailRelativePath].compactMap { $0 } }
        for asset in doomed { context.delete(asset) }
        try? context.save()
        // Files are removed after the record, not before: a failed save would otherwise leave a
        // record pointing at a file that is already gone.
        Task { [fileStore = dependencies.fileStore] in
            for path in paths { await fileStore.delete(relativePath: path) }
        }
    }
}
