import SwiftData
import SwiftUI

/// Everything, filterable.
///
/// Today answers "what needs doing"; this screen answers "where does each machine stand". The
/// difference shows in the filter row: status selection is visible and one tap away rather than
/// buried in a menu, because on this screen it is the primary way people navigate.
struct RentalsView: View {

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context

    @Query(sort: \RentalItem.modifiedAt, order: .reverse) private var items: [RentalItem]
    @Query(sort: \Vendor.name) private var vendors: [Vendor]
    @Query(sort: \JobSite.name) private var jobSites: [JobSite]

    @State private var search = ""
    @State private var vendorFilter: UUID?
    @State private var jobSiteFilter: UUID?
    @State private var bucket: Bucket = .all
    @State private var limitAlert: EntitlementBlock?
    @State private var creatingCompany = false
    @State private var creatingJobSite = false

    var body: some View {
        // A real `List`. The hand-built scroll version reimplemented rows, separators and
        // selection highlighting, and none of the three matched what the platform draws.
        List {
            if filtered.isEmpty {
                Section { emptyState.listRowBackground(Color.clear) }
            } else {
                if !openItems.isEmpty {
                    Section("On rent and in progress") {
                        ForEach(openItems, id: \.id) { row($0) }
                    }
                }
                if !closedItems.isEmpty {
                    Section("Closed") { ForEach(closedItems, id: \.id) { row($0) } }
                }
                if !archivedItems.isEmpty {
                    Section("Archived") { ForEach(archivedItems, id: \.id) { row($0) } }
                }
            }

            Section {
                NavigationLink(value: RentalDestination.vendors) {
                    Label("Rental companies", systemImage: "building.2")
                        .badge(vendors.count)
                }
                .accessibilityIdentifier(A11yID.Rentals.companiesLink)
                NavigationLink(value: RentalDestination.jobSites) {
                    Label("Jobsites", systemImage: "mappin.and.ellipse")
                        .badge(jobSites.count)
                }
                .accessibilityIdentifier(A11yID.Rentals.jobSitesLink)
            } header: {
                Text("Reusable records")
            } footer: {
                Text("""
                    A company or a jobsite you add here is available to every rental, and a \
                    jobsite with a location puts its rentals on the map.
                    """)
            }
        }
        .listStyle(.insetGrouped)
        .offRentFormBackground()
        .accessibilityIdentifier(A11yID.Rentals.root)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !items.isEmpty { filterBar }
        }
        .navigationTitle("Rentals")
        .searchable(text: $search, prompt: "Equipment, company, jobsite, ID or PO")
        // The identifier goes on the searchable container: `.searchable` builds the field
        // itself, so there is no view for the test to address without this.
        .accessibilityIdentifier(A11yID.Rentals.searchField)
        .offRentNavigationDestinations()
        .toolbar {
            ToolbarItem(placement: .primaryAction) { addMenu }
            ToolbarItem(placement: .topBarLeading) { filterMenu }
        }
        .sheet(isPresented: $creatingCompany) { CompanyEditorView(existing: nil) }
        .sheet(isPresented: $creatingJobSite) { JobsiteMapEditor(existing: nil) }
        .alert(
            "Free plan limit",
            isPresented: Binding(get: { limitAlert != nil }, set: { if !$0 { limitAlert = nil } })
        ) {
            Button("See Pro") { router.presentedSheet = .paywall(reason: .openItemLimit) }
            Button("Not now", role: .cancel) {}
        } message: {
            Text(limitAlert?.message ?? "")
        }
    }

    // MARK: - Filtering

    /// The workflow, grouped into the six answers people actually want.
    ///
    /// A partition rather than an overlapping set of tags: every status belongs to exactly one
    /// bucket, so the counts across the row add up to the total and a rental cannot hide in a
    /// bucket the user has not looked in.
    private enum Bucket: String, CaseIterable, Identifiable {
        case all, onRent, toCall, awaitingPickup, awaitingInvoice, toReview, closed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "All"
            case .onRent: "On rent"
            case .toCall: "To call"
            case .awaitingPickup: "Awaiting pickup"
            case .awaitingInvoice: "Awaiting invoice"
            case .toReview: "To review"
            case .closed: "Closed"
            }
        }

        var statuses: [RentalItemStatus] {
            switch self {
            case .all: RentalItemStatus.allCases
            case .onRent: [.draft, .active]
            case .toCall: [.contactVendor]
            case .awaitingPickup: [.confirmationRecorded, .awaitingPickup, .pickedUp]
            case .awaitingInvoice: [.awaitingInvoice]
            case .toReview: [.invoiceReview, .needsFollowUp]
            case .closed: [.resolved, .archived]
            }
        }

        func contains(_ status: RentalItemStatus) -> Bool { statuses.contains(status) }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.snug) {
                ForEach(visibleBuckets) { candidate in
                    FilterChip(
                        title: candidate.title,
                        count: count(for: candidate),
                        isSelected: bucket == candidate
                    ) {
                        withAnimation(Motion.quick) {
                            bucket = bucket == candidate ? .all : candidate
                        }
                    }
                    .accessibilityIdentifier("rentals.filter.\(candidate.rawValue)")
                }
            }
            .padding(.horizontal, Space.comfortable)
            .padding(.vertical, Space.snug)
        }
        .background(Palette.background)
        .accessibilityIdentifier("rentals.filterBar")
    }

    /// "All", plus every bucket that has something in it.
    ///
    /// A row of chips reading zero is a row of chips saying nothing; it also pushes the useful
    /// ones off the right-hand edge on a 393pt screen.
    private var visibleBuckets: [Bucket] {
        Bucket.allCases.filter { candidate in
            candidate == .all || candidate == bucket || count(for: candidate) > 0
        }
    }

    private func count(for candidate: Bucket) -> Int {
        // Counted against everything except the status filter itself, so the numbers on the
        // chips tell you what you would get by tapping one — not what is already on screen.
        withoutStatusFilter.filter { candidate.contains($0.status) }.count
    }

    private var filterMenu: some View {
        Menu {
            Picker("Vendor", selection: $vendorFilter) {
                Text("All vendors").tag(UUID?.none)
                ForEach(vendors, id: \.id) { vendor in Text(vendor.name).tag(UUID?.some(vendor.id)) }
            }
            Picker("Jobsite", selection: $jobSiteFilter) {
                Text("All jobsites").tag(UUID?.none)
                ForEach(jobSites, id: \.id) { site in Text(site.name).tag(UUID?.some(site.id)) }
            }
            if hasFilters { Divider(); Button("Clear filters", action: clearFilters) }
        } label: {
            Label(
                "Filter",
                systemImage: hasFilters
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .accessibilityIdentifier(A11yID.Rentals.filterMenu)
    }

    // MARK: - Rows

    private func row(_ item: RentalItem) -> some View {
        let annotation = annotation(for: item)
        return NavigationLink(value: RentalDestination.item(id: item.id)) {
            RentalRow(
                title: item.equipmentName,
                reference: item.vendorEquipmentIdentifier,
                vendor: item.agreement?.vendor?.name,
                status: item.status,
                amount: item.status.accruesRent ? item.cachedEstimatedRunningCost : nil,
                amountIsComplete: item.cachedEstimateIsComplete,
                note: annotation?.text,
                noteTint: annotation?.tint,
                identifier: A11yID.Rentals.row(item.id)
            )
        }
        .accessibilityHint(item.status.explanation)
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: hasAnyItems ? "line.3.horizontal.decrease.circle" : "shippingbox",
            title: hasAnyItems ? "Nothing matches those filters" : "No rentals yet",
            message: hasAnyItems
                ? "Clear the filters to see everything."
                : "Add a machine to start tracking what it is costing.",
            actionTitle: hasAnyItems ? "Clear filters" : "Add a rental",
            action: { hasAnyItems ? clearFilters() : addRental() }
        )
    }

    // MARK: - The one useful fact per row

    private struct Annotation {
        let text: String
        let tint: Color?
    }

    /// The thing worth knowing about this rental that its status does not already say.
    ///
    /// One line, and only when it earns the width: "Awaiting Pickup" plus "Awaiting pickup" is a
    /// row that says one thing twice. What a reader cannot get from the chip is *how long*, *what
    /// is missing*, and *what changes next*.
    private func annotation(for item: RentalItem) -> Annotation? {
        switch item.status {
        case .draft:
            return Annotation(text: "No rate confirmed yet", tint: nil)

        case .active:
            if !item.cachedEstimateIsComplete {
                return Annotation(text: "No rate confirmed yet", tint: Palette.attention)
            }
            guard let next: Date = item.nextRolloverDate else { return nil }
            let interval: TimeInterval = next.timeIntervalSince(dependencies.clock.now)
            guard interval >= 0, interval <= AppConfiguration.upcomingRateChangeWindow else {
                return nil
            }
            // Weekday alone: inside a 48-hour window "Fri" is unambiguous, and the full
            // "Fri, May 15" is 80pt wider than this row has to spare.
            return Annotation(text: "Rate changes \(Formatters.weekday(next))", tint: Palette.accent)

        case .contactVendor:
            // How long the call has been outstanding — not "off rent N days". Nothing is off rent
            // until the vendor confirms it, and the row must not say otherwise.
            guard let stopped: Date = item.accrualStoppedAt else {
                return Annotation(text: "Needs a confirmation number", tint: Palette.attention)
            }
            return Annotation(
                text: Formatters.relative(stopped, from: dependencies.clock.now),
                tint: Palette.attention
            )

        case .confirmationRecorded, .awaitingPickup, .pickedUp, .awaitingInvoice:
            guard let days: Int = daysOffRent(item) else { return nil }
            return Annotation(text: offRentDuration(days), tint: nil)

        case .invoiceReview:
            guard let invoice: VendorInvoice = item.latestInvoice else { return nil }
            let open: Int = invoice.openDiscrepancyCount
            guard open > 0 else { return Annotation(text: "Invoice attached", tint: nil) }
            return Annotation(
                text: open == 1 ? "1 line to review" : "\(open) lines to review",
                tint: Palette.review
            )

        case .needsFollowUp:
            guard let days: Int = daysOffRent(item) else { return nil }
            return Annotation(text: offRentDuration(days), tint: Palette.attention)

        case .resolved, .archived:
            return nil
        }
    }

    private func offRentDuration(_ days: Int) -> String {
        days == 0 ? "Off rent today" : "Off rent \(Formatters.dayCount(days))"
    }

    /// Whole days since the estimate stopped accruing. `nil` when nothing recorded it.
    private func daysOffRent(_ item: RentalItem) -> Int? {
        guard let stopped: Date = item.accrualStoppedAt else { return nil }
        let calendar: Calendar = dependencies.clock.calendar
        let from: Date = calendar.startOfDay(for: stopped)
        let to: Date = calendar.startOfDay(for: dependencies.clock.now)
        guard let days: Int = calendar.dateComponents([.day], from: from, to: to).day else {
            return nil
        }
        return days >= 0 ? days : nil
    }

    /// The plus button, as a menu.
    ///
    /// It used to go straight into New Rental, which made a rental the only thing this tab could
    /// create — so the two records a rental *needs* could only be made as a side effect of making
    /// one. Adding the yard before the machine is the order people actually work in.
    private var addMenu: some View {
        Menu {
            Button {
                addRental()
            } label: {
                Label("New rental", systemImage: "shippingbox")
            }
            .accessibilityIdentifier(A11yID.Rentals.addRental)

            Button {
                creatingCompany = true
            } label: {
                Label("New rental company", systemImage: "building.2")
            }
            .accessibilityIdentifier(A11yID.Rentals.addCompany)

            Button {
                creatingJobSite = true
            } label: {
                Label("New jobsite", systemImage: "mappin.and.ellipse")
            }
            .accessibilityIdentifier(A11yID.Rentals.addJobSite)
        } label: {
            Label("Add", systemImage: "plus")
        }
        .accessibilityIdentifier(A11yID.Rentals.addMenu)
    }

    // MARK: - Actions

    private func addRental() {
        // The limit is checked before the sheet opens rather than on save. Letting somebody fill
        // in a whole rental and then refusing it is a worse experience than saying so up front.
        let openCount = items.filter { $0.status.isOpen }.count
        switch EntitlementPolicy.canCreateOpenItem(
            currentOpenCount: openCount, entitlement: dependencies.effectiveEntitlement
        ) {
        case .success:
            router.presentedSheet = .addRental
        case let .failure(block):
            limitAlert = block
        }
    }

    private func clearFilters() {
        vendorFilter = nil
        jobSiteFilter = nil
        bucket = .all
        search = ""
    }

    // MARK: - Derived

    private var hasAnyItems: Bool { !items.isEmpty }
    private var hasFilters: Bool {
        vendorFilter != nil || jobSiteFilter != nil || bucket != .all || !search.isEmpty
    }

    /// Everything the vendor, jobsite and search filters allow — the set the chip counts describe.
    private var withoutStatusFilter: [RentalItem] {
        items.filter { item in
            if let vendorFilter, item.agreement?.vendor?.id != vendorFilter { return false }
            if let jobSiteFilter, item.agreement?.jobSite?.id != jobSiteFilter { return false }
            guard !search.isEmpty else { return true }
            // `[String?]` is spelled out. Without it the type checker has to unify seven
            // elements — some `String`, some `String?` — before it can even start on the
            // `compactMap` closure, in an expression nested three closures deep.
            let fields: [String?] = [
                item.equipmentName,
                item.equipmentClass,
                item.vendorEquipmentIdentifier,
                item.serialNumber,
                item.agreement?.agreementNumber,
                item.agreement?.purchaseOrderNumber,
                item.agreement?.vendor?.name,
                item.agreement?.jobSite?.name,
                item.agreement?.jobSite?.address,
            ]
            let haystack: String = fields.compactMap { $0 }.joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(search)
        }
    }

    private var filtered: [RentalItem] {
        let selected: Bucket = bucket
        guard selected != .all else { return withoutStatusFilter }
        return withoutStatusFilter.filter { selected.contains($0.status) }
    }

    private var openItems: [RentalItem] { filtered.filter { $0.status.isOpen } }
    private var closedItems: [RentalItem] { filtered.filter { $0.status == .resolved } }
    private var archivedItems: [RentalItem] { filtered.filter { $0.status == .archived } }
}

#Preview {
    NavigationStack { RentalsView() }
        .environment(AppDependencies.preview())
        .environment(AppRouter())
        .modelContainer(ModelContainerFactory.makeInMemory())
}
