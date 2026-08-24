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
            LazyVStack(alignment: .leading, spacing: Space.section) {
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
                    .padding(.top, Space.roomy)
                } else {
                    summary
                    if !upcomingRateChanges.isEmpty { upcomingRateChangesSection }
                    if !actionQueue.isEmpty { actionQueueSection }
                    if !awaitingPickup.isEmpty { awaitingPickupSection }
                    if !invoicesToReview.isEmpty { invoicesSection }
                }
            }
            .padding(.horizontal, Space.comfortable)
            .padding(.top, Space.screenTop)
            .padding(.bottom, Space.screenBottom)
        }
        .offRentScreen()
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

    // MARK: - Summary
    //
    // One graphite panel carrying the number the screen is about, with the counts beneath it as
    // tiles. This is the whole answer to "the dashboard looks like a settings screen": the most
    // important fact now has a surface of its own instead of being one more line of text on the
    // same white as everything else.

    private var summary: some View {
        VStack(spacing: Space.base) {
            SummaryPanel(
                eyebrow: "Estimated rent running",
                footnote: AppCopy.estimateExplanation
            ) {
                VStack(alignment: .leading, spacing: Space.tight) {
                    if accruing.isEmpty && totalRunning == 0 {
                        Text(Formatters.currency(0))
                            .font(Typography.hero)
                            .monospacedDigit()
                            .foregroundStyle(Palette.onGraphite)
                        Text("Nothing is accruing right now.")
                            .font(Typography.rowDetail)
                            .foregroundStyle(Palette.onGraphiteSecondary)
                    } else {
                        Text(Formatters.currency(totalRunning))
                            .font(Typography.hero)
                            .monospacedDigit()
                            .foregroundStyle(Palette.onGraphite)
                            .contentTransition(.numericText())
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(AppCopy.estimateQualifier)
                            .font(Typography.caption.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(summaryAccessibilityLabel)
                .accessibilityIdentifier(A11yID.Today.estimatedRentRunning)
            } trailing: {
                Text(accruing.count == 1 ? "1 on rent" : "\(accruing.count) on rent")
                    .font(Typography.micro.weight(.medium))
                    .foregroundStyle(Palette.onGraphite)
                    .padding(.horizontal, Space.snug + 2)
                    .padding(.vertical, Space.tight + 1)
                    .background(Palette.onGraphite.opacity(0.14), in: Capsule())
            }

            if incompleteEstimateCount > 0 {
                InlineAlert(
                    message: incompleteEstimateCount == 1
                        ? "1 rental has no confirmed rate, so it is not included above."
                        : "\(incompleteEstimateCount) rentals have no confirmed rate, so they are not included above."
                )
            }

            HStack(spacing: Space.snug) {
                MetricTile(
                    value: "\(actionQueue.count)", label: "To call",
                    symbol: "phone.arrow.up.right", tint: Palette.attention,
                    identifier: "metric.needACall"
                )
                MetricTile(
                    value: "\(awaitingPickup.count)", label: "To collect",
                    symbol: "truck.box", tint: Palette.waiting,
                    identifier: "metric.awaitingPickup"
                )
                MetricTile(
                    value: "\(invoicesToReview.count)", label: "To review",
                    symbol: "doc.text.magnifyingglass", tint: Palette.review,
                    identifier: "metric.toReview"
                )
            }
        }
    }

    private var summaryAccessibilityLabel: String {
        guard !accruing.isEmpty || totalRunning != 0 else {
            return "Estimated rent running, nothing is accruing right now."
        }
        return "Estimated rent running, \(Formatters.currencyAccessible(totalRunning)). "
            + AppCopy.estimateQualifier
    }

    // MARK: - Sections

    private var upcomingRateChangesSection: some View {
        section(
            title: "Upcoming rate changes",
            subtitle: "Within 48 hours, based on the dates you confirmed.",
            count: upcomingRateChanges.count
        ) {
            ForEach(Array(upcomingRateChanges.enumerated()), id: \.element.item.id) { index, entry in
                NavigationLink(value: RentalDestination.item(id: entry.item.id)) {
                    HStack(alignment: .top, spacing: Space.base) {
                        RowIcon(symbol: "chart.line.uptrend.xyaxis", tint: Palette.accent)
                        VStack(alignment: .leading, spacing: Space.tight) {
                            Text(entry.item.equipmentName).font(Typography.rowTitle)
                            Text(
                                "\(Formatters.shortWeekdayDate(entry.date)) · "
                                    + Formatters.relative(entry.date, from: dependencies.clock.now)
                            )
                            .font(Typography.rowDetail)
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Space.snug)
                        if let increment = entry.increment {
                            VStack(alignment: .trailing, spacing: 0) {
                                Text("+" + Formatters.currency(increment))
                                    .font(Typography.rowTitle)
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.accent)
                                Text("expected")
                                    .font(Typography.micro)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        chevron
                    }
                    .padding(.horizontal, Space.comfortable)
                    .padding(.vertical, Space.base)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .minimumTapTarget()
                if index < upcomingRateChanges.count - 1 { RowDivider() }
            }
        }
        .accessibilityIdentifier(A11yID.Today.upcomingRateChanges)
    }

    private var actionQueueSection: some View {
        section(
            title: "Contact vendor",
            subtitle: AppCopy.offRentDisclosureShort,
            count: actionQueue.count
        ) {
            rows(actionQueue)
        }
        .accessibilityIdentifier(A11yID.Today.actionQueue)
    }

    private var awaitingPickupSection: some View {
        section(
            title: "Awaiting pickup",
            subtitle: "Off-rent recorded. Still on the jobsite.",
            count: awaitingPickup.count
        ) {
            rows(awaitingPickup)
        }
    }

    private var invoicesSection: some View {
        section(
            title: "Invoices to review",
            subtitle: "Compare against the terms you confirmed.",
            count: invoicesToReview.count
        ) {
            ForEach(Array(invoicesToReview.enumerated()), id: \.element.id) { index, invoice in
                NavigationLink(value: AuditDestination.invoice(id: invoice.id)) {
                    HStack(alignment: .top, spacing: Space.base) {
                        RowIcon(symbol: "doc.text.magnifyingglass", tint: Palette.review)
                        VStack(alignment: .leading, spacing: Space.tight) {
                            Text(invoice.invoiceNumber ?? "Invoice")
                                .font(Typography.rowTitle)
                            Text(invoice.agreement?.vendor?.name ?? "Unknown vendor")
                                .font(Typography.rowDetail)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Space.snug)
                        Text(Formatters.currency(invoice.invoiceTotal))
                            .font(Typography.rowTitle)
                            .monospacedDigit()
                        chevron
                    }
                    .padding(.horizontal, Space.comfortable)
                    .padding(.vertical, Space.base)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .minimumTapTarget()
                if index < invoicesToReview.count - 1 { RowDivider() }
            }
        }
    }

    // MARK: - Row plumbing

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(Typography.micro.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.top, 3)
            .accessibilityHidden(true)
    }

    private func section(
        title: String, subtitle: String?, count: Int,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.base) {
            SectionHeader(title: title, subtitle: subtitle, count: count)
            ListGroup { content() }
        }
    }

    /// Rows inside a section that is already grouped by status.
    ///
    /// No chip and no "needs a confirmation number" note: the section header above says both,
    /// and repeating them cost a third of the row's width and pushed the equipment name onto
    /// three wrapped lines at 393pt.
    @ViewBuilder
    private func rows(_ items: [RentalItem]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            NavigationLink(value: RentalDestination.item(id: item.id)) {
                RentalRow(
                    title: item.equipmentName,
                    reference: item.vendorEquipmentIdentifier,
                    vendor: item.agreement?.vendor?.name,
                    status: item.status,
                    amount: item.cachedEstimatedRunningCost,
                    amountIsComplete: item.cachedEstimateIsComplete,
                    showsStatus: false
                )
            }
            .buttonStyle(.plain)
            .minimumTapTarget()
            if index < items.count - 1 { RowDivider() }
        }
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
