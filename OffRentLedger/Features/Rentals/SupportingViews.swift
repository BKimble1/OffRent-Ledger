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
        ScrollView {
            if let item = items.first {
                let events: [RentalEvent] = Array(item.sortedEvents.reversed())
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        TimelineRow(
                            event: event,
                            isFirst: index == 0,
                            isLast: index == events.count - 1
                        )
                    }
                }
                .padding(.vertical, Space.comfortable)
                .offRentGroup()
                .padding(.horizontal, Space.comfortable)
                .padding(.vertical, Space.base)
            }
        }
        .offRentScreen()
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
        .offRentFormBackground()
        .navigationTitle("Agreement")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct VendorListView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var context
    @Query(sort: \Vendor.name) private var vendors: [Vendor]
    @State private var editing: Vendor?
    @State private var creating = false
    /// The companies a swipe has proposed deleting, held until the user confirms.
    @State private var pendingDeletion: [Vendor] = []
    /// Set when the store refuses the deletion, so the row that is still on screen is explained
    /// rather than left looking like a control that did nothing.
    @State private var deletionFailure: String?

    var body: some View {
        List {
            if let deletionFailure {
                InlineAlert(message: deletionFailure)
                    .accessibilityIdentifier(A11yID.Failure.companyDelete)
            }
            // A `List` rather than the scrolling groups used elsewhere: swipe-to-delete is the
            // reason this screen exists, and it is native here and hand-built anywhere else.
            ForEach(vendors, id: \.id) { vendor in
                Button { editing = vendor } label: {
                    HStack(spacing: Space.base) {
                        RowIcon(symbol: "building.2")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(vendor.name).font(Typography.rowTitle)
                            if let detail = vendorDetail(vendor) {
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
            }
            .onDelete { offsets in
                // Ask first. The comment that used to sit here said the confirmation "says so
                // plainly rather than relying on the user to know" — and there was no
                // confirmation. A vendor cascades to its agreements and through them to every
                // rental, timeline event, invoice and photograph filed under that yard, so one
                // careless swipe on this screen could take a contractor's entire record of a
                // job with it, with no undo and nothing said.
                pendingDeletion = offsets.map { vendors[$0] }
            }
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(
                get: { !pendingDeletion.isEmpty },
                set: { if !$0 { pendingDeletion = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { confirmDeletion() }
            Button("Keep", role: .cancel) { pendingDeletion = [] }
        } message: {
            Text(deletionMessage)
        }
        .offRentFormBackground()
        .navigationTitle("Rental companies")
        .accessibilityIdentifier(A11yID.Company.listRoot)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: {
                    Label("Add a rental company", systemImage: "plus")
                }
                .accessibilityIdentifier(A11yID.Company.listAdd)
            }
        }
        .overlay {
            if vendors.isEmpty {
                EmptyStateView(
                    symbol: "building.2",
                    title: "No rental companies yet",
                    message: "Add the yard you rent from and it is there for every rental after.",
                    actionTitle: "Add a rental company",
                    action: { creating = true }
                )
            }
        }
        .sheet(item: $editing) { vendor in CompanyEditorView(existing: vendor) }
        .sheet(isPresented: $creating) { CompanyEditorView(existing: nil) }
    }

    /// Branch or phone, plus how many rentals are filed under this company.
    private var deletionTitle: String {
        guard let first = pendingDeletion.first else { return "Delete this company?" }
        return pendingDeletion.count == 1
            ? "Delete \(first.name)?"
            : "Delete \(pendingDeletion.count) companies?"
    }

    /// Counts what actually goes, rather than warning in the abstract.
    ///
    /// "This cannot be undone" on its own is a sentence people tap through. "This also deletes 4
    /// rentals, their confirmations, invoices and photos" is a sentence they read.
    private var deletionMessage: String {
        var rentals = 0
        var invoices = 0
        for vendor in pendingDeletion {
            for agreement in vendor.agreements ?? [] {
                rentals += (agreement.items ?? []).count
                invoices += (agreement.invoices ?? []).count
            }
        }
        if rentals == 0, invoices == 0 {
            return "Nothing else is filed under it. This cannot be undone."
        }
        var parts: [String] = []
        if rentals > 0 { parts.append("\(rentals) rental\(rentals == 1 ? "" : "s")") }
        if invoices > 0 { parts.append("\(invoices) invoice\(invoices == 1 ? "" : "s")") }
        return """
            This also deletes \(parts.joined(separator: " and ")), with every confirmation, \
            pickup and photograph filed under them. This cannot be undone.
            """
    }

    private func confirmDeletion() {
        for vendor in pendingDeletion { context.delete(vendor) }
        pendingDeletion = []
        if let failure = PersistentStore.save(context, describing: "The deletion") {
            deletionFailure = failure
            return
        }
        deletionFailure = nil
        // The rentals that just went were on Today, on the map, in the widget and in the
        // reminder schedule. §3.3.
        dependencies.derivedStateNeedsRefresh()
    }

    private func vendorDetail(_ vendor: Vendor) -> String? {
        var parts: [String] = []
        if let first = [vendor.branch, vendor.phone].compactMap({ $0 }).first { parts.append(first) }
        var rentals = 0
        for agreement in vendor.agreements ?? [] { rentals += (agreement.items ?? []).count }
        if rentals > 0 { parts.append(rentals == 1 ? "1 rental" : "\(rentals) rentals") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct JobSiteListView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var context
    @Query(sort: \JobSite.name) private var jobSites: [JobSite]
    @State private var editing: JobSite?
    @State private var creating = false
    @State private var deletionFailure: String?

    var body: some View {
        List {
            if let deletionFailure {
                InlineAlert(message: deletionFailure)
                    .accessibilityIdentifier(A11yID.Failure.jobsiteDelete)
            }
            ForEach(jobSites, id: \.id) { site in
                Button {
                    editing = site
                } label: {
                    HStack(spacing: Space.base) {
                        RowIcon(
                            symbol: site.coordinate == nil
                                ? "mappin.and.ellipse" : "mappin.circle.fill",
                            tint: site.coordinate == nil ? .secondary : Palette.accent
                        )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(site.name)
                                .font(Typography.rowTitle)
                                .foregroundStyle(.primary)
                            // The subtitle says whether this site is on the map, because that is
                            // the one thing about a jobsite the user can now change and the one
                            // thing that decides whether it appears on Today.
                            Text(site.locationSummary)
                                .font(Typography.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(Typography.micro.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(A11yID.Jobsite.row(site.id))
            }
            .onDelete { offsets in
                // Nullify, not cascade: deleting a jobsite label must not delete the rentals that
                // happened there. The relationship's delete rule enforces it; this just triggers.
                // No confirmation, because nothing is lost that the user cannot re-add — but the
                // rentals that were pinned there have just come off the map.
                for index in offsets { context.delete(jobSites[index]) }
                if let failure = PersistentStore.save(context, describing: "The deletion") {
                    deletionFailure = failure
                    return
                }
                deletionFailure = nil
                dependencies.derivedStateNeedsRefresh()
            }
        }
        .offRentFormBackground()
        .navigationTitle("Jobsites")
        .accessibilityIdentifier(A11yID.Jobsite.listRoot)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: {
                    Label("Add a jobsite", systemImage: "plus")
                }
                .accessibilityIdentifier(A11yID.Jobsite.listAdd)
            }
        }
        .overlay {
            if jobSites.isEmpty {
                EmptyStateView(
                    symbol: "mappin.and.ellipse",
                    title: "No jobsites yet",
                    message: "Put a site on the map once and every rental there shows up on it.",
                    actionTitle: "Add a jobsite",
                    action: { creating = true }
                )
            }
        }
        .sheet(item: $editing) { site in
            JobsiteMapEditor(existing: site)
        }
        .sheet(isPresented: $creating) { JobsiteMapEditor(existing: nil) }
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
            // `Data` crosses the boundary, not `UIImage`: UIImage is not Sendable, and the point
            // of going off the main actor here is the file read anyway.
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
            guard let data else { return }
            image = UIImage(data: data)
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
    /// Why the last batch did not all arrive.
    ///
    /// A row in the List rather than an alert: there is a `.fullScreenCover` on this screen's
    /// modifier chain, and it stays on screen next to the attachments it is talking about. A
    /// photograph of damage that was never filed is exactly the thing a user must not find out
    /// about weeks later, in front of a rental yard.
    @State private var attachmentFailure: String?

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
                if let attachmentFailure {
                    InlineAlert(message: attachmentFailure)
                        .accessibilityIdentifier(A11yID.Failure.attachmentSave)
                }
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
        .offRentFormBackground()
        .navigationTitle("Attachments")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await importPhotos(newItems) }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            DocumentScannerView(
                onFinish: { pages in
                    showingCamera = false
                    Task { await save(imageData: pages) }
                },
                onCancel: { showingCamera = false },
                onError: { error in
                    showingCamera = false
                    // The third silent path off this screen: the scanner itself failing closed
                    // the sheet and said nothing, which is indistinguishable from the user
                    // cancelling.
                    attachmentFailure = """
                        The scanner stopped before anything was captured. \
                        \(error.localizedDescription) Try again, or add a photo from your library.
                        """
                }
            )
            .ignoresSafeArea()
        }
    }

    private func importPhotos(_ selected: [PhotosPickerItem]) async {
        isImporting = true
        defer { isImporting = false; photoItems = [] }
        var pages: [Data] = []
        // A picked photograph that will not load is counted, not skipped. It is one of the three
        // ways attaching can fail — this one, the write, and the encode — and all three used to
        // end in `continue`.
        var unreadable = 0
        for item in selected {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                unreadable += 1
                continue
            }
            pages.append(data)
        }
        await save(imageData: pages, unreadable: unreadable)
    }

    /// Takes encoded data, not bitmaps: `AppFileStore` is an actor and `UIImage` is not
    /// `Sendable`. The picker hands back data anyway, so decoding here only to re-encode inside
    /// the store was wasted work as well as an illegal crossing.
    private func save(imageData: [Data], unreadable: Int = 0) async {
        guard let item = items.first else { return }
        guard !imageData.isEmpty || unreadable > 0 else { return }
        isImporting = true
        defer { isImporting = false }

        let alreadyAttached = item.assets?.count ?? 0
        var storedCount = 0
        var failedCount = unreadable

        for data in imageData {
            // A UUID, not a timestamp. `Int(timeIntervalSince1970)` has one-second resolution and
            // the index only disambiguated within a single batch, so two photographs attached in
            // the same second wrote to the same filename: the second one overwrote the first on
            // disk, both records survived, and both then pointed at the surviving image. A user
            // looking at two thumbnails of the same photograph has lost evidence and been told
            // nothing.
            //
            // Nothing anywhere reads meaning out of this name. `AppFileStore` appends `.jpg` and
            // `-thumb.jpg` itself, and its reconcile sweep is the only code that inspects a
            // filename at all — it looks for that `-thumb.jpg` suffix, which is unaffected.
            let basename = UUID().uuidString
            do {
                let stored = try await dependencies.fileStore.writeImage(
                    data, ownerFolder: item.id.uuidString, basename: basename
                )
                let asset = EvidenceAsset(
                    relativePath: stored.relativePath,
                    mediaType: .image,
                    displayName: "Photo \(alreadyAttached + storedCount + 1)",
                    capturedAt: dependencies.clock.now,
                    sha256: stored.sha256,
                    thumbnailRelativePath: stored.thumbnailRelativePath,
                    item: item
                )
                context.insert(asset)
                storedCount += 1
            } catch {
                failedCount += 1
            }
        }

        // The timeline says how many photographs were filed, not how many were picked. The count
        // used to come from the input array, so a batch of six where four failed to write left a
        // permanent record reading "6 photo(s) attached." over four photographs — the ledger
        // overstating its own evidence, which is the one thing it must never do.
        if storedCount > 0 {
            RentalWorkflowService(context: context, clock: dependencies.clock)
                .append(
                    event: .conditionCaptured,
                    to: item,
                    detail: storedCount == 1 ? "1 photo attached." : "\(storedCount) photos attached."
                )
        }

        if let failure = PersistentStore.save(context, describing: "These photos") {
            attachmentFailure = failure
            return
        }

        attachmentFailure = failedCount == 0
            ? nil
            : Self.attachmentFailureMessage(failed: failedCount, stored: storedCount)
    }

    /// Plain, specific, and it never claims a photograph was filed when it was not.
    private static func attachmentFailureMessage(failed: Int, stored: Int) -> String {
        let missing = failed == 1 ? "1 photo" : "\(failed) photos"
        if stored == 0 {
            return """
                \(missing) could not be saved to this iPhone, so nothing was attached. Try again, \
                or pick a different photo.
                """
        }
        let kept = stored == 1 ? "1 photo is" : "\(stored) photos are"
        return "\(missing) could not be saved to this iPhone and \(failed == 1 ? "was" : "were") not attached. \(kept) here."
    }

    private func delete(_ offsets: IndexSet) {
        guard let item = items.first, let assets = item.assets else { return }
        let doomed = offsets.map { assets[$0] }
        let paths = doomed.flatMap { [$0.relativePath, $0.thumbnailRelativePath].compactMap { $0 } }
        for asset in doomed { context.delete(asset) }
        // Files are removed after the record, not before: a failed save would otherwise leave a
        // record pointing at a file that is already gone. Which is why the save's answer is now
        // read rather than discarded — the whole ordering was pointless while nothing could tell
        // whether the save had worked.
        if let failure = PersistentStore.save(context, describing: "That change") {
            attachmentFailure = failure
            return
        }
        attachmentFailure = nil
        Task { [fileStore = dependencies.fileStore] in
            for path in paths { await fileStore.delete(relativePath: path) }
        }
    }
}
