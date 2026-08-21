import SwiftData
import SwiftUI

/// What needs doing, and what it is costing.
///
/// The headline figure is "Estimated rent running" — the money that is still accruing right now —
/// not a total-at-risk. That distinction is the product: the number a contractor can act on is
/// the one that stops when they make a phone call.
struct TodayView: View {

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context

    @Query(sort: \RentalItem.modifiedAt, order: .reverse) private var allItems: [RentalItem]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                if openItems.isEmpty {
                    EmptyStateView(
                        symbol: "shippingbox",
                        title: "No open rentals",
                        message: """
                            Add the first machine you have on rent. \(AppConfiguration.displayName) \
                            will estimate what it is costing and remind you to get an off-rent \
                            confirmation number when you are done with it.
                            """,
                        actionTitle: "Add a rental",
                        action: { router.presentedSheet = .addRental },
                        identifier: A11yID.Today.emptyState
                    )
                    .padding(.top, 40)
                } else {
                    runningCostCard
                    if !upcomingRateChanges.isEmpty { upcomingRateChangesSection }
                    if !actionQueue.isEmpty { actionQueueSection }
                    if !awaitingPickup.isEmpty { awaitingPickupSection }
                    if !invoicesToReview.isEmpty { invoicesSection }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .background(Palette.groupedBackground)
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .offRentNavigationDestinations()
        .accessibilityIdentifier(A11yID.Today.root)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.presentedSheet = .addRental
                } label: {
                    Label("Add rental", systemImage: "plus")
                }
                .accessibilityIdentifier(A11yID.Today.addRental)
            }
        }
    }

    // MARK: - Sections

    private var runningCostCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Estimated rent running",
                subtitle: accruing.isEmpty
                    ? "Nothing is accruing right now."
                    : "\(accruing.count) \(accruing.count == 1 ? "machine is" : "machines are") still on rent."
            )
            EstimateLabel(amount: totalRunning, isComplete: !accruing.isEmpty || totalRunning == 0)
                .accessibilityIdentifier(A11yID.Today.estimatedRentRunning)
            Text(AppCopy.estimateExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if incompleteEstimateCount > 0 {
                Label(
                    incompleteEstimateCount == 1
                        ? "1 rental has no confirmed rate, so it is not included."
                        : "\(incompleteEstimateCount) rentals have no confirmed rate, so they are not included.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(Palette.attention)
            }
        }
        .offRentCard()
    }

    private var upcomingRateChangesSection: some View {
        VStack(alignment: .leading, spacing: Layout.itemSpacing) {
            SectionHeader(
                title: "Upcoming rate changes",
                subtitle: "Within 48 hours, based on the dates you confirmed.",
                count: upcomingRateChanges.count
            )
            ForEach(upcomingRateChanges, id: \.item.id) { entry in
                NavigationLink(value: RentalDestination.item(id: entry.item.id)) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.item.equipmentName).font(.subheadline.weight(.medium))
                            Text(
                                "\(Formatters.shortWeekdayDate(entry.date)) · "
                                    + Formatters.relative(entry.date, from: dependencies.clock.now)
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if let increment = entry.increment {
                            EstimateLabel(amount: increment, size: .small)
                        }
                    }
                    .offRentCard(padding: 12)
                }
                .buttonStyle(.plain)
                .minimumTapTarget()
            }
        }
        .accessibilityIdentifier(A11yID.Today.upcomingRateChanges)
    }

    private var actionQueueSection: some View {
        VStack(alignment: .leading, spacing: Layout.itemSpacing) {
            SectionHeader(
                title: "Contact vendor",
                subtitle: AppCopy.offRentDisclosureShort,
                count: actionQueue.count
            )
            ForEach(actionQueue, id: \.id) { item in
                itemRow(item, trailing: "Needs a confirmation number")
            }
        }
        .accessibilityIdentifier(A11yID.Today.actionQueue)
    }

    private var awaitingPickupSection: some View {
        VStack(alignment: .leading, spacing: Layout.itemSpacing) {
            SectionHeader(
                title: "Awaiting pickup",
                subtitle: "Off-rent recorded. Still on the jobsite.",
                count: awaitingPickup.count
            )
            ForEach(awaitingPickup, id: \.id) { item in
                itemRow(item, trailing: "Record pickup when it leaves")
            }
        }
    }

    private var invoicesSection: some View {
        VStack(alignment: .leading, spacing: Layout.itemSpacing) {
            SectionHeader(
                title: "Invoices to review",
                subtitle: "Compare against the terms you confirmed.",
                count: invoicesToReview.count
            )
            ForEach(invoicesToReview, id: \.id) { invoice in
                NavigationLink(value: AuditDestination.invoice(id: invoice.id)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(invoice.invoiceNumber ?? "Invoice")
                                .font(.subheadline.weight(.medium))
                            Text(invoice.agreement?.vendor?.name ?? "Unknown vendor")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(Formatters.currency(invoice.invoiceTotal))
                            .font(.subheadline)
                            .monospacedDigit()
                    }
                    .offRentCard(padding: 12)
                }
                .buttonStyle(.plain)
                .minimumTapTarget()
            }
        }
    }

    private func itemRow(_ item: RentalItem, trailing: String) -> some View {
        NavigationLink(value: RentalDestination.item(id: item.id)) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.equipmentName).font(.subheadline.weight(.medium))
                    Text(item.agreement?.vendor?.name ?? "Unknown vendor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(trailing).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                StatusChip(status: item.status, compact: true)
            }
            .offRentCard(padding: 12)
        }
        .buttonStyle(.plain)
        .minimumTapTarget()
    }

    // MARK: - Derived

    private var openItems: [RentalItem] { allItems.filter { $0.status.isOpen } }
    private var accruing: [RentalItem] { allItems.filter { $0.status.accruesRent } }

    private var totalRunning: Decimal {
        // Written as an explicit loop with annotated locals rather than a `compactMap` whose
        // closure is a ternary yielding `Decimal?`. The chained form makes the type checker
        // solve for the element type, the closure result, and the `nil` literal's type at
        // once, and it is the same shape that blew up in `invoicesToReview` below.
        var amounts: [Decimal] = []
        for item in accruing {
            guard item.cachedEstimateIsComplete else { continue }
            guard let amount: Decimal = item.cachedEstimatedRunningCost else { continue }
            amounts.append(amount)
        }
        return MoneyMath.sum(amounts)
    }

    private var incompleteEstimateCount: Int {
        accruing.filter { !$0.cachedEstimateIsComplete }.count
    }

    private var actionQueue: [RentalItem] {
        allItems.filter { $0.status == .contactVendor }
    }

    private var awaitingPickup: [RentalItem] {
        allItems.filter { $0.status == .awaitingPickup || $0.status == .confirmationRecorded }
    }

    private var invoicesToReview: [VendorInvoice] {
        // Deliberately an explicit loop. The chained form —
        //
        //     allItems.compactMap(\.agreement)
        //             .flatMap { $0.invoices ?? [] }
        //             .filter { $0.reviewStatus == .notReviewed || $0.reviewStatus == .inReview }
        //
        // fails to compile with "the compiler is unable to type-check this expression in
        // reasonable time". Each link is generic over its element type, the `?? []` forces the
        // empty-array literal to be solved rather than known, and `==` against two leading-dot
        // enum members adds two more unresolved bases — so the solver explores a large space
        // for a chain that reads as trivial. Annotated locals give it nothing to search.
        //
        // The dedupe is part of the same pass: the same agreement is reached once per item on
        // it, so without `seen` the same invoice would be listed several times.
        var seen: Set<UUID> = []
        var result: [VendorInvoice] = []
        for item in allItems {
            guard let agreement: RentalAgreement = item.agreement else { continue }
            guard let invoices: [VendorInvoice] = agreement.invoices else { continue }
            for invoice in invoices {
                let status: InvoiceReviewStatus = invoice.reviewStatus
                guard status == .notReviewed || status == .inReview else { continue }
                guard seen.insert(invoice.id).inserted else { continue }
                result.append(invoice)
            }
        }
        return result
    }

    private struct RolloverEntry {
        let item: RentalItem
        let date: Date
        let increment: Decimal?
    }

    private var upcomingRateChanges: [RolloverEntry] {
        let now = dependencies.clock.now
        let calendar = dependencies.clock.calendar
        return accruing.compactMap { item -> RolloverEntry? in
            guard let rollover = RentalRateEngine.nextRollover(
                terms: item.terms, asOf: now, calendar: calendar
            ) else { return nil }
            let interval = rollover.date.timeIntervalSince(now)
            guard interval >= 0, interval <= AppConfiguration.upcomingRateChangeWindow else {
                return nil
            }
            return RolloverEntry(item: item, date: rollover.date, increment: rollover.expectedIncrement)
        }
        .sorted { $0.date < $1.date }
    }
}

#Preview {
    NavigationStack { TodayView() }
        .environment(AppDependencies.preview())
        .environment(AppRouter())
        .modelContainer(ModelContainerFactory.makeInMemory())
}
