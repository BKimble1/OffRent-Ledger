import SwiftData
import SwiftUI

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
    @State private var statusFilter: RentalItemStatus?
    @State private var limitAlert: EntitlementBlock?

    var body: some View {
        List {
            if !activeItems.isEmpty {
                Section("Active") { ForEach(activeItems, content: row) }
            }
            if !completedItems.isEmpty {
                Section("Completed") { ForEach(completedItems, content: row) }
            }
            if !archivedItems.isEmpty {
                Section("Archived") { ForEach(archivedItems, content: row) }
            }
            if filtered.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: hasAnyItems ? "line.3.horizontal.decrease.circle" : "shippingbox",
                        title: hasAnyItems ? "Nothing matches those filters" : "No rentals yet",
                        message: hasAnyItems
                            ? "Clear the filters to see everything."
                            : "Add a machine to start tracking what it is costing.",
                        actionTitle: hasAnyItems ? "Clear filters" : "Add a rental",
                        action: { hasAnyItems ? clearFilters() : addRental() }
                    )
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                NavigationLink("Rental companies", value: RentalDestination.vendors)
                    .minimumTapTarget()
                NavigationLink("Jobsites", value: RentalDestination.jobSites)
                    .minimumTapTarget()
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Rentals")
        .accessibilityIdentifier(A11yID.Rentals.root)
        .searchable(text: $search, prompt: "Equipment, vendor, jobsite or agreement")
        .navigationDestination(for: RentalDestination.self) { destination in
            switch destination {
            case let .item(id): RentalItemDetailView(itemID: id)
            case let .agreement(id): AgreementDetailView(agreementID: id)
            case let .timeline(itemID): RentalTimelineView(itemID: itemID)
            case .vendors: VendorListView()
            case .jobSites: JobSiteListView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: addRental) { Label("Add rental", systemImage: "plus") }
                    .accessibilityIdentifier(A11yID.Rentals.addRental)
            }
            ToolbarItem(placement: .topBarLeading) { filterMenu }
        }
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

    private var filterMenu: some View {
        Menu {
            Picker("Vendor", selection: $vendorFilter) {
                Text("All vendors").tag(UUID?.none)
                ForEach(vendors) { vendor in Text(vendor.name).tag(UUID?.some(vendor.id)) }
            }
            Picker("Jobsite", selection: $jobSiteFilter) {
                Text("All jobsites").tag(UUID?.none)
                ForEach(jobSites) { site in Text(site.name).tag(UUID?.some(site.id)) }
            }
            Picker("Status", selection: $statusFilter) {
                Text("All statuses").tag(RentalItemStatus?.none)
                ForEach(RentalItemStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(RentalItemStatus?.some(status))
                }
            }
            if hasFilters { Divider(); Button("Clear filters", action: clearFilters) }
        } label: {
            Label("Filter", systemImage: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier(A11yID.Rentals.filterMenu)
    }

    private func row(_ item: RentalItem) -> some View {
        NavigationLink(value: RentalDestination.item(id: item.id)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.equipmentName)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    StatusChip(status: item.status, compact: true)
                }
                Text(
                    [item.agreement?.vendor?.name, item.agreement?.jobSite?.name]
                        .compactMap { $0 }.joined(separator: " · ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if item.status.accruesRent, item.cachedEstimateIsComplete,
                   let estimate = item.cachedEstimatedRunningCost {
                    EstimateLabel(amount: estimate, size: .small)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier(A11yID.Rentals.row(item.id))
        .accessibilityHint(item.status.explanation)
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
        statusFilter = nil
        search = ""
    }

    // MARK: - Derived

    private var hasAnyItems: Bool { !items.isEmpty }
    private var hasFilters: Bool {
        vendorFilter != nil || jobSiteFilter != nil || statusFilter != nil || !search.isEmpty
    }

    private var filtered: [RentalItem] {
        items.filter { item in
            if let vendorFilter, item.agreement?.vendor?.id != vendorFilter { return false }
            if let jobSiteFilter, item.agreement?.jobSite?.id != jobSiteFilter { return false }
            if let statusFilter, item.status != statusFilter { return false }
            guard !search.isEmpty else { return true }
            let haystack = [
                item.equipmentName,
                item.equipmentClass,
                item.vendorEquipmentIdentifier,
                item.serialNumber,
                item.agreement?.agreementNumber,
                item.agreement?.vendor?.name,
                item.agreement?.jobSite?.name,
            ].compactMap { $0 }.joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(search)
        }
    }

    private var activeItems: [RentalItem] { filtered.filter { $0.status.isOpen } }
    private var completedItems: [RentalItem] { filtered.filter { $0.status == .resolved } }
    private var archivedItems: [RentalItem] { filtered.filter { $0.status == .archived } }
}

#Preview {
    NavigationStack { RentalsView() }
        .environment(AppDependencies.preview())
        .environment(AppRouter())
        .modelContainer(ModelContainerFactory.makeInMemory())
}
