import SwiftData
import SwiftUI

/// One machine: what it is costing, where it is in the workflow, and what to do next.
///
/// The screen is built around a single question — *what do I do about this one?* — so the answer
/// is a card near the top with one primary button in it, rather than a "Next steps" section the
/// reader has to find among eight others. Everything below it is the record: the terms, the proof
/// of the off-rent call, the pickup, the invoice, and the timeline that ties them together.
struct RentalItemDetailView: View {

    let itemID: UUID

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context

    @Query private var items: [RentalItem]
    @State private var rejection: TransitionRejection?
    @State private var showingReopen = false
    @State private var reopenReason = ""
    @State private var reopenTarget: RentalItemStatus = .invoiceReview
    @State private var showingExport = false

    init(itemID: UUID) {
        self.itemID = itemID
        _items = Query(filter: #Predicate<RentalItem> { $0.id == itemID })
    }

    private var item: RentalItem? { items.first }

    var body: some View {
        Group {
            if let item {
                content(for: item)
            } else {
                // Reachable by a deep link to something since deleted. Saying so beats an empty
                // screen the user has to guess about.
                ScrollView {
                    EmptyStateView(
                        symbol: "questionmark.folder",
                        title: "This rental is no longer here",
                        message: "It may have been deleted. Go back to Rentals to see what you have."
                    )
                    .padding(.top, Space.section)
                }
            }
        }
        .offRentScreen()
        .navigationTitle(item?.equipmentName ?? "Rental")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(A11yID.ItemDetail.root)
        .alert(
            "Cannot do that yet",
            isPresented: Binding(get: { rejection != nil }, set: { if !$0 { rejection = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(rejection?.message ?? "")
        }
        .sheet(isPresented: $showingReopen) {
            if let item { reopenSheet(for: item) }
        }
        .sheet(isPresented: $showingExport) {
            if let item { EvidenceExportSheet(itemID: item.id) }
        }
    }

    // MARK: - Content

    private func content(for item: RentalItem) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.section) {
                summary(for: item)
                nextStep(for: item)
                if item.status == .contactVendor { contactVendorSection(item) }
                estimateSection(item)
                termsSection(item)
                offRentProofSection(item)
                pickupSection(item)
                invoiceSection(item)
                identificationSection(item)
                timelineSection(item)
                evidenceSection(item)
                utilitySection(item)
            }
            .padding(.horizontal, Space.comfortable)
            .padding(.top, Space.screenTop)
            .padding(.bottom, Space.screenBottom)
        }
    }

    // MARK: - Summary

    private func summary(for item: RentalItem) -> some View {
        let estimate = RentalRateEngine.estimate(
            terms: item.terms, asOf: dependencies.clock.now, calendar: dependencies.clock.calendar
        )
        return SummaryPanel(
            eyebrow: estimate.hasStoppedAccruing ? "Estimated rent, stopped" : "Estimated rent running",
            subhead: identityLine(item),
            footnote: AppCopy.estimateExplanation
        ) {
            VStack(alignment: .leading, spacing: Space.tight) {
                if estimate.isComplete {
                    Text(Formatters.currency(estimate.estimatedTotal))
                        .font(Typography.hero)
                        .monospacedDigit()
                        .foregroundStyle(Palette.onGraphite)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(AppCopy.estimateQualifier)
                        .font(Typography.micro.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(Palette.accent)
                } else {
                    Text("Not available")
                        .font(Typography.hero)
                        .foregroundStyle(Palette.onGraphiteSecondary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if let reason = estimate.blockingIssue?.message {
                        Text(reason)
                            .font(Typography.rowDetail)
                            .foregroundStyle(Palette.onGraphiteSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summaryLabel(for: item, estimate: estimate))
            .accessibilityIdentifier(A11yID.ItemDetail.estimate)
        } trailing: {
            // The status pill is drawn in the panel's own palette rather than the status tint:
            // slate and green at 14% on graphite are unreadable, and the tint is carried by the
            // symbol beside the word.
            Label {
                Text(item.status.shortName)
                    .font(Typography.micro.weight(.semibold))
            } icon: {
                Image(systemName: item.status.symbolName)
                    .font(Typography.micro.weight(.semibold))
            }
            .foregroundStyle(Palette.onGraphite)
            .padding(.horizontal, Space.snug + 2)
            .padding(.vertical, Space.tight + 1)
            .background(Palette.onGraphite.opacity(0.14), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Status: \(item.status.displayName)")
            .accessibilityHint(item.status.explanation)
            .accessibilityIdentifier(A11yID.ItemDetail.status)
        }
    }

    private func identityLine(_ item: RentalItem) -> String? {
        let parts: [String?] = [item.agreement?.vendor?.name, item.agreement?.jobSite?.name]
        let joined: String = parts.compactMap { $0 }.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    private func summaryLabel(for item: RentalItem, estimate: RunningEstimate) -> String {
        guard estimate.isComplete else {
            return "Estimate not available. " + (estimate.blockingIssue?.message ?? "")
        }
        return "Estimated rent, \(Formatters.currencyAccessible(estimate.estimatedTotal)). "
            + AppCopy.estimateQualifier
    }

    // MARK: - Next step
    //
    // One card, one primary button, and the sentence that says what tapping it does and does not
    // do. The old screen listed every available action as an undifferentiated row, which left the
    // user to work out which of them was the next thing to do.

    @ViewBuilder
    private func nextStep(for item: RentalItem) -> some View {
        VStack(alignment: .leading, spacing: Space.base) {
            CardHeader(
                title: "Next step",
                subtitle: item.status.explanation,
                symbol: "arrow.forward.circle.fill"
            )
            nextStepControl(for: item)
        }
        .offRentCard()
    }

    @ViewBuilder
    private func nextStepControl(for item: RentalItem) -> some View {
        switch item.status {
        case .draft:
            Button("Mark active") { apply(.activate, to: item) }
                .buttonStyle(.offRentPrimary)

        case .active:
            VStack(alignment: .leading, spacing: Space.snug) {
                // Not "End rental". The button describes what the *user* did — finished with
                // the machine — not something the app can do to a rental agreement.
                Button("Mark equipment done") { apply(.markEquipmentDone, to: item) }
                    .buttonStyle(.offRentPrimary)
                    .accessibilityIdentifier(A11yID.ItemDetail.markDone)
                    .accessibilityHint(AppCopy.markDoneExplanation)
                Text(AppCopy.markDoneExplanation)
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .contactVendor:
            Button("Record vendor confirmation") {
                router.presentedSheet = .recordConfirmation(itemID: item.id)
            }
            .buttonStyle(.offRentPrimary)
            .accessibilityIdentifier(A11yID.ItemDetail.recordConfirmation)

        case .confirmationRecorded:
            Button("Awaiting pickup") { apply(.acknowledgeAwaitingPickup, to: item) }
                .buttonStyle(.offRentPrimary)

        case .awaitingPickup:
            Button("Record pickup") { router.presentedSheet = .recordPickup(itemID: item.id) }
                .buttonStyle(.offRentPrimary)
                .accessibilityIdentifier(A11yID.ItemDetail.recordPickup)

        case .pickedUp:
            Button("Awaiting invoice") { apply(.beginAwaitingInvoice, to: item) }
                .buttonStyle(.offRentPrimary)

        case .awaitingInvoice:
            Button("Attach final invoice") {
                router.presentedSheet = .attachInvoice(itemID: item.id)
            }
            .buttonStyle(.offRentPrimary)
            .accessibilityIdentifier(A11yID.ItemDetail.attachInvoice)

        case .invoiceReview, .needsFollowUp:
            VStack(spacing: Space.snug) {
                if let invoice = latestInvoice(for: item) {
                    NavigationLink(value: AuditDestination.invoice(id: invoice.id)) {
                        Text("Review the invoice")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.onAccent)
                            .frame(maxWidth: .infinity, minHeight: Layout.controlHeight)
                            .background(Palette.accent, in: RoundedRectangle(cornerRadius: Radius.control))
                    }
                    .buttonStyle(.plain)
                }
                Button("Resolve") { resolve(item) }
                    .buttonStyle(.offRentSecondary)
                    .accessibilityIdentifier(A11yID.ItemDetail.resolve)
            }

        case .resolved:
            VStack(spacing: Space.snug) {
                Button("Archive") { apply(.archive, to: item) }
                    .buttonStyle(.offRentSecondary)
                reopenButton
            }

        case .archived:
            reopenButton
        }
    }

    private var reopenButton: some View {
        Button("Reopen") { showingReopen = true }
            .buttonStyle(.offRentSecondary)
            .accessibilityIdentifier(A11yID.ItemDetail.reopen)
    }

    // MARK: - Sections

    private func contactVendorSection(_ item: RentalItem) -> some View {
        VStack(alignment: .leading, spacing: Space.base) {
            SectionHeader(title: "Contact the rental company")
            OffRentDisclosureBanner(identifier: A11yID.ItemDetail.disclosure)
            ContactVendorActions(item: item)
        }
    }

    private func estimateSection(_ item: RentalItem) -> some View {
        let estimate = RentalRateEngine.estimate(
            terms: item.terms, asOf: dependencies.clock.now, calendar: dependencies.clock.calendar
        )
        return section(
            title: "How that was worked out",
            subtitle: AppCopy.basedOnConfirmedTerms
        ) {
            if estimate.isComplete {
                DetailRow(label: "Days on rent", value: Formatters.dayCount(estimate.daysOnRent))
                RowDivider(inset: Space.comfortable)
                DetailRow(
                    label: "\(item.terms.billingBasis.displayName) periods",
                    value: "\(estimate.periodsStarted) × \(Formatters.currency(estimate.amountPerPeriod))"
                )
                RowDivider(inset: Space.comfortable)
                DetailRow(label: "Calculated as of", value: Formatters.dateAndTime(estimate.asOf))
            }
            if let next = estimate.nextRolloverDate {
                RowDivider(inset: Space.comfortable)
                DetailRow(label: "Next rate change", value: Formatters.dateAndTime(next))
                if let increment = estimate.expectedNextIncrement {
                    RowDivider(inset: Space.comfortable)
                    DetailRow(
                        label: "Expected to add",
                        value: "\(Formatters.currency(increment)) (estimate)"
                    )
                }
            }
            if estimate.hasStoppedAccruing {
                RowDivider(inset: Space.comfortable)
                noteRow("Stopped accruing when you marked this done.", symbol: "pause.circle")
            }
            ForEach(estimate.issues.indices, id: \.self) { index in
                RowDivider(inset: Space.comfortable)
                noteRow(
                    estimate.issues[index].message,
                    symbol: "exclamationmark.triangle",
                    tint: Palette.attention
                )
            }
        }
    }

    private func termsSection(_ item: RentalItem) -> some View {
        section(title: "Terms you confirmed") {
            DetailRow(label: "Delivered", value: Formatters.mediumDate(item.deliveryDate))
            RowDivider(inset: Space.comfortable)
            DetailRow(label: "Billing basis", value: item.terms.billingBasis.displayName)
            RowDivider(inset: Space.comfortable)
            DetailRow(label: "Rollover mode", value: item.terms.rolloverMode.displayName)
            RowDivider(inset: Space.comfortable)
            DetailRow(
                label: "Daily rate",
                value: item.dailyRate.map(Formatters.currency) ?? "Not confirmed"
            )
            RowDivider(inset: Space.comfortable)
            DetailRow(
                label: "Weekly rate",
                value: item.weeklyRate.map(Formatters.currency) ?? "Not confirmed"
            )
            RowDivider(inset: Space.comfortable)
            DetailRow(
                label: "4-week rate",
                value: item.fourWeekRate.map(Formatters.currency) ?? "Not confirmed"
            )
            if let usage = item.includedUsageNotes, !usage.isEmpty {
                RowDivider(inset: Space.comfortable)
                VStack(alignment: .leading, spacing: Space.tight) {
                    Text("Included usage")
                        .font(Typography.rowDetail)
                        .foregroundStyle(.secondary)
                    Text(usage)
                        .font(Typography.rowDetail)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("""
                        Recorded for your reference. \(AppConfiguration.displayName) does not \
                        calculate excess-hour charges.
                        """)
                        .font(Typography.micro)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.comfortable)
                .padding(.vertical, Space.base)
            }
            RowDivider(inset: Space.comfortable)
            NavigationLink {
                EditRentalItemView(itemID: item.id)
            } label: {
                NavigationRow(title: "Edit terms", symbol: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .minimumTapTarget()
        }
    }

    /// What the vendor said, kept apart from what the yard did.
    ///
    /// The separation is the product: a confirmation number is the user's evidence that they
    /// called and the rental company agreed a stop date. Pickup is a different event, on a
    /// different day, proving a different thing. Merging them into one "off rent" block would
    /// quietly claim the app knows something it does not.
    @ViewBuilder
    private func offRentProofSection(_ item: RentalItem) -> some View {
        if let event = latestEvent(of: .vendorConfirmationRecorded, in: item) {
            section(
                title: "Off-rent confirmation",
                subtitle: "What the rental company told you."
            ) {
                DetailRow(label: "Recorded", value: Formatters.dateAndTime(event.timestamp))
                if let number = event.confirmationNumber {
                    RowDivider(inset: Space.comfortable)
                    DetailRow(
                        label: "Confirmation number", value: number, valueIsMonospaced: true
                    )
                }
                if let representative = event.vendorRepresentative {
                    RowDivider(inset: Space.comfortable)
                    DetailRow(label: "Spoke to", value: representative)
                }
                if let method = event.contactMethod {
                    RowDivider(inset: Space.comfortable)
                    DetailRow(label: "How", value: method.displayName)
                }
                if let detail = event.detail, !detail.isEmpty {
                    RowDivider(inset: Space.comfortable)
                    DetailRow(label: "Note", value: detail)
                }
            }
        }
    }

    @ViewBuilder
    private func pickupSection(_ item: RentalItem) -> some View {
        if let event = latestEvent(of: .pickupRecorded, in: item) {
            section(title: "Pickup", subtitle: "When the equipment actually left the site.") {
                DetailRow(label: "Recorded", value: Formatters.dateAndTime(event.timestamp))
                if let detail = event.detail, !detail.isEmpty {
                    RowDivider(inset: Space.comfortable)
                    DetailRow(label: "Note", value: detail)
                }
                if event.location != nil {
                    RowDivider(inset: Space.comfortable)
                    noteRow("Location recorded with this entry.", symbol: "mappin.and.ellipse")
                }
            }
        }
    }

    @ViewBuilder
    private func invoiceSection(_ item: RentalItem) -> some View {
        if let invoice = latestInvoice(for: item) {
            section(title: "Invoice") {
                DetailRow(label: "Invoice number", value: invoice.invoiceNumber ?? "Not recorded")
                RowDivider(inset: Space.comfortable)
                DetailRow(label: "Received", value: Formatters.mediumDate(invoice.receivedDate))
                RowDivider(inset: Space.comfortable)
                DetailRow(label: "Invoice total", value: Formatters.currency(invoice.invoiceTotal))
                RowDivider(inset: Space.comfortable)
                NavigationLink(value: AuditDestination.invoice(id: invoice.id)) {
                    NavigationRow(
                        title: "Review this invoice",
                        subtitle: invoice.openDiscrepancyCount > 0
                            ? "\(invoice.openDiscrepancyCount) open to look at"
                            : "Nothing open",
                        symbol: "list.clipboard",
                        tint: invoice.openDiscrepancyCount > 0 ? Palette.review : Palette.settled
                    )
                }
                .buttonStyle(.plain)
                .minimumTapTarget()
            }
        }
    }

    private func identificationSection(_ item: RentalItem) -> some View {
        section(title: "Identification") {
            if let vendor = item.agreement?.vendor {
                DetailRow(label: "Rental company", value: vendor.name)
                if let branch = vendor.branch {
                    RowDivider(inset: Space.comfortable)
                    DetailRow(label: "Branch", value: branch)
                }
                RowDivider(inset: Space.comfortable)
            }
            if let site = item.agreement?.jobSite {
                DetailRow(label: "Jobsite", value: site.name)
                RowDivider(inset: Space.comfortable)
            }
            if let number = item.agreement?.agreementNumber {
                DetailRow(label: "Agreement number", value: number, valueIsMonospaced: true)
                RowDivider(inset: Space.comfortable)
            }
            if let identifier = item.vendorEquipmentIdentifier {
                DetailRow(label: "Vendor equipment ID", value: identifier, valueIsMonospaced: true)
                RowDivider(inset: Space.comfortable)
            }
            DetailRow(
                label: "Serial number",
                value: item.serialNumber ?? "Not recorded",
                valueIsMonospaced: item.serialNumber != nil
            )
        }
    }

    private func timelineSection(_ item: RentalItem) -> some View {
        let recent = Array(item.sortedEvents.suffix(4).reversed())
        return VStack(alignment: .leading, spacing: Space.base) {
            SectionHeader(title: "Recent activity", count: item.sortedEvents.count)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, event in
                    TimelineRow(
                        event: event,
                        isFirst: index == 0,
                        isLast: index == recent.count - 1
                    )
                }
                if !recent.isEmpty { RowDivider(inset: 0) }
                NavigationLink(value: RentalDestination.timeline(itemID: item.id)) {
                    NavigationRow(title: "See the full timeline", symbol: "clock.arrow.circlepath")
                }
                .buttonStyle(.plain)
                .minimumTapTarget()
                .accessibilityIdentifier(A11yID.ItemDetail.timeline)
            }
            .padding(.top, recent.isEmpty ? 0 : Space.base)
            .offRentGroup()
        }
    }

    private func evidenceSection(_ item: RentalItem) -> some View {
        VStack(alignment: .leading, spacing: Space.base) {
            SectionHeader(title: "Photos and documents", count: (item.assets ?? []).count)
            VStack(alignment: .leading, spacing: 0) {
                EvidenceGrid(assets: item.assets ?? [], fileStore: dependencies.fileStore)
                    .padding(.horizontal, Space.comfortable)
                    .padding(.vertical, Space.base)
                RowDivider(inset: 0)
                NavigationLink {
                    EvidenceManagerView(itemID: item.id)
                } label: {
                    NavigationRow(title: "Add or manage attachments", symbol: "paperclip")
                }
                .buttonStyle(.plain)
                .minimumTapTarget()
            }
            .offRentGroup()
        }
    }

    private func utilitySection(_ item: RentalItem) -> some View {
        ListGroup {
            ActionRow(
                title: "Export evidence packet",
                subtitle: "A PDF of this rental's record, to share yourself",
                symbol: "square.and.arrow.up"
            ) {
                showingExport = true
            }
            .accessibilityIdentifier(A11yID.ItemDetail.exportEvidence)
        }
    }

    // MARK: - Section plumbing

    private func section(
        title: String, subtitle: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.base) {
            SectionHeader(title: title, subtitle: subtitle)
            ListGroup { content() }
        }
    }

    private func noteRow(_ message: String, symbol: String, tint: Color = .secondary) -> some View {
        Label {
            Text(message)
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .font(Typography.rowDetail)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.comfortable)
        .padding(.vertical, Space.base)
    }

    private func latestEvent(of type: RentalEventType, in item: RentalItem) -> RentalEvent? {
        var latest: RentalEvent?
        for event in item.sortedEvents where event.type == type {
            latest = event
        }
        return latest
    }

    // MARK: - Sheets

    private func reopenSheet(for item: RentalItem) -> some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reopen to", selection: $reopenTarget) {
                        ForEach(
                            StatusTransitionService.reopenTargets
                                .filter { $0.order < item.status.order }
                                .sorted(by: { $0.order < $1.order }),
                            id: \.self
                        ) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    TextField("Why are you reopening this?", text: $reopenReason, axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    Text("The reason is written to the timeline so the record explains itself later.")
                }
            }
            .offRentFormBackground()
            .navigationTitle("Reopen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingReopen = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reopen") {
                        apply(.reopen(to: reopenTarget, reason: reopenReason), to: item)
                        if rejection == nil {
                            showingReopen = false
                            reopenReason = ""
                        }
                    }
                    .disabled(reopenReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func apply(_ intent: TransitionIntent, to item: RentalItem) {
        let workflow = RentalWorkflowService(context: context, clock: dependencies.clock)
        if case let .failure(failure) = workflow.apply(intent, to: item) {
            rejection = failure
            return
        }
        try? context.save()
    }

    private func resolve(_ item: RentalItem) {
        let openCount = latestInvoice(for: item)?.openDiscrepancyCount ?? 0
        apply(.resolve(openDiscrepancyCount: openCount), to: item)
    }

    private func latestInvoice(for item: RentalItem) -> VendorInvoice? {
        item.latestInvoice
    }
}

/// One timeline entry, with the rail that ties it to the entries above and below.
struct TimelineRow: View {
    let event: RentalEvent
    var isFirst = false
    var isLast = false

    private var tint: Color {
        switch event.type {
        case .vendorConfirmationRecorded, .resolved: Palette.settled
        case .mismatchFlagged, .disputeRecorded, .reopened: Palette.attention
        case .invoiceAttached, .mismatchAccepted: Palette.review
        case .pickupRecorded: Palette.waiting
        default: Palette.accent
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.base) {
            // The rail. Without it a stack of events is a stack of paragraphs; with it the eye
            // follows the sequence, which is the whole point of a timeline.
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : Palette.hairline)
                    .frame(width: Layout.hairline, height: Space.snug)
                ZStack {
                    Circle().fill(tint.opacity(0.15)).frame(width: 26, height: 26)
                    Image(systemName: event.type.symbolName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                }
                Rectangle()
                    .fill(isLast ? Color.clear : Palette.hairline)
                    .frame(width: Layout.hairline)
                    .frame(maxHeight: .infinity)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.tight) {
                Text(event.type.displayName).font(Typography.rowTitle)
                Text(Formatters.dateAndTime(event.timestamp))
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                if let number = event.confirmationNumber {
                    Text("Confirmation \(number)")
                        .font(Typography.caption)
                        .fontDesign(.monospaced)
                }
                if let representative = event.vendorRepresentative {
                    Text("Spoke to \(representative)")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
                if let detail = event.detail, !detail.isEmpty {
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if event.location != nil {
                    Label("Location recorded", systemImage: "mappin.and.ellipse")
                        .font(Typography.micro)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, isLast ? 0 : Space.comfortable)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.comfortable)
        .accessibilityElement(children: .combine)
    }
}
