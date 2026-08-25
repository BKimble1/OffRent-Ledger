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
    @State private var confirmingDelete = false

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
                .offRentScreen()
            }
        }
        .navigationTitle(item?.equipmentName ?? "Rental")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(A11yID.ItemDetail.root)
        // Edit belongs in the navigation bar, where iOS users look for it, as well as beside the
        // terms it most often corrects. Before this it existed only as a link called "Edit
        // terms", four sections down, that reached six of a rental's twenty fields.
        .toolbar {
            if let item {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: RentalDestination.editItem(id: item.id)) {
                        Text("Edit")
                    }
                    .accessibilityIdentifier(A11yID.ItemDetail.edit)
                }
            }
        }
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
        List {
            Section { summary(for: item) }
            nextStepSection(item)
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
            deleteSection(item)
        }
        .listStyle(.insetGrouped)
        .confirmationDialog(
            "Delete this rental?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { delete(item) }
            Button("Keep", role: .cancel) {}
        } message: {
            Text(deletionMessage(item))
        }
        .offRentFormBackground()
    }

    // MARK: - Summary
    //
    // A compact card, not a dark panel. There is one dark panel in this app and it is on Today;
    // repeating it on every rental made the whole product feel like a slide deck.

    private func summary(for item: RentalItem) -> some View {
        let estimate = RentalRateEngine.estimate(
            terms: item.terms, asOf: dependencies.clock.now, calendar: dependencies.clock.calendar
        )
        return VStack(alignment: .leading, spacing: Space.snug) {
            HStack(alignment: .firstTextBaseline) {
                Text(estimate.hasStoppedAccruing ? "Estimated rent" : "Estimated rent running")
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Space.snug)
                StatusChip(status: item.status)
                    .accessibilityIdentifier(A11yID.ItemDetail.status)
            }
            if estimate.isComplete {
                Text(Formatters.currency(estimate.estimatedTotal))
                    .font(Typography.hero)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .accessibilityLabel(
                        "Estimated rent, \(Formatters.currencyAccessible(estimate.estimatedTotal))"
                    )
                    .accessibilityIdentifier(A11yID.ItemDetail.estimate)
            } else {
                Text("Not available")
                    .font(Typography.hero)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier(A11yID.ItemDetail.estimate)
                if let reason = estimate.blockingIssue?.message {
                    Text(reason)
                        .font(Typography.rowDetail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let identity = identityLine(item) {
                Text(identity)
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Space.tight)
    }

    private func identityLine(_ item: RentalItem) -> String? {
        let parts: [String?] = [item.agreement?.vendor?.name, item.agreement?.jobSite?.name]
        let joined: String = parts.compactMap { $0 }.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    // MARK: - Next step

    private func nextStepSection(_ item: RentalItem) -> some View {
        Section {
            nextStepControl(for: item)
        } header: {
            Text("Next step")
        } footer: {
            // One explanation, not two. The mark-done sentence and the status explanation were
            // both on screen, saying nearly the same thing a row apart.
            Text(item.status == .active ? AppCopy.markDoneExplanation : item.status.explanation)
        }
    }

    @ViewBuilder
    private func nextStepControl(for item: RentalItem) -> some View {
        switch item.status {
        case .draft:
            primary("Mark active") { apply(.activate, to: item) }

        case .active:
            // Not "End rental". The button describes what the *user* did — finished with the
            // machine — not something the app can do to a rental agreement.
            primary("Mark equipment done") { apply(.markEquipmentDone, to: item) }
                .accessibilityIdentifier(A11yID.ItemDetail.markDone)
                .accessibilityHint(AppCopy.markDoneExplanation)

        case .contactVendor:
            primary("Record vendor confirmation") {
                router.presentedSheet = .recordConfirmation(itemID: item.id)
            }
            .accessibilityIdentifier(A11yID.ItemDetail.recordConfirmation)

        case .confirmationRecorded:
            primary("Awaiting pickup") { apply(.acknowledgeAwaitingPickup, to: item) }

        case .awaitingPickup:
            primary("Record pickup") { router.presentedSheet = .recordPickup(itemID: item.id) }
                .accessibilityIdentifier(A11yID.ItemDetail.recordPickup)

        case .pickedUp:
            primary("Awaiting invoice") { apply(.beginAwaitingInvoice, to: item) }

        case .awaitingInvoice:
            primary("Attach final invoice") {
                router.presentedSheet = .attachInvoice(itemID: item.id)
            }
            .accessibilityIdentifier(A11yID.ItemDetail.attachInvoice)

        case .invoiceReview, .needsFollowUp:
            if let invoice = latestInvoice(for: item) {
                NavigationLink(value: AuditDestination.invoice(id: invoice.id)) {
                    Label("Review the invoice", systemImage: "list.clipboard")
                }
            }
            Button("Resolve") { resolve(item) }
                .accessibilityIdentifier(A11yID.ItemDetail.resolve)

        case .resolved:
            Button("Archive") { apply(.archive, to: item) }
            reopenButton

        case .archived:
            reopenButton
        }
    }

    /// The one orange control on the screen.
    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.offRentPrimary)
            .listRowInsets(EdgeInsets(top: Space.snug, leading: Space.comfortable,
                                      bottom: Space.snug, trailing: Space.comfortable))
    }

    private var reopenButton: some View {
        Button("Reopen") { showingReopen = true }
            .accessibilityIdentifier(A11yID.ItemDetail.reopen)
    }

    // MARK: - Sections

    /// The way out of a rental you should not have created.
    ///
    /// There was none. From `.active` the only allowed transition is `.contactVendor`, so
    /// removing a rental meant walking the whole workflow — affirming you had telephoned a yard,
    /// recording a confirmation number, a pickup and an invoice — for a machine that was never on
    /// site. On the free tier that made one mistaken rental permanent: the open-item limit was
    /// reached, nothing could clear it, and no second rental could ever be created. It is also
    /// the first wall anyone evaluating the app runs into.
    ///
    /// Deliberately here rather than as a swipe on the Rentals list. A swipe is a gesture people
    /// make by accident while scrolling, and this cascades to the timeline and the photographs.
    private func deleteSection(_ item: RentalItem) -> some View {
        Section {
            Button("Delete this rental", role: .destructive) { confirmingDelete = true }
                .accessibilityIdentifier(A11yID.ItemDetail.delete)
        } footer: {
            Text(AppCopy.deleteRentalExplanation)
        }
    }

    /// Counts what goes, rather than warning in the abstract.
    private func deletionMessage(_ item: RentalItem) -> String {
        let events = (item.events ?? []).count
        let invoices = (item.agreement?.invoices ?? []).count
        let photographs = (item.agreement?.assets ?? []).count
        var parts: [String] = []
        if events > 0 { parts.append("\(events) timeline \(events == 1 ? "entry" : "entries")") }
        if invoices > 0 { parts.append("\(invoices) invoice\(invoices == 1 ? "" : "s")") }
        if photographs > 0 {
            parts.append("\(photographs) photograph\(photographs == 1 ? "" : "s")")
        }
        guard !parts.isEmpty else {
            return "\(item.equipmentName) has nothing else filed under it. This cannot be undone."
        }
        let listed = parts.count == 1
            ? parts[0]
            : parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "")
        return "This also deletes \(listed), and everything they record. This cannot be undone."
    }

    private func delete(_ item: RentalItem) {
        // The agreement goes only when nothing else is on it. One piece of paper can carry two
        // machines, and deleting the excavator must not take the compactor's contract with it.
        let agreement = item.agreement
        let identifier = item.id
        context.delete(item)
        if let agreement, (agreement.items ?? []).allSatisfy({ $0.id == identifier }) {
            context.delete(agreement)
        }
        try? context.save()
        dependencies.derivedStateNeedsRefresh()
        // The photographs and scanned pages are files, and the records that pointed at them have
        // gone. Without this they stay on disk forever — counted by the storage figure on the
        // privacy screen, and reachable from nothing.
        Task {
            let service = ExportService(
                context: context, clock: dependencies.clock, fileStore: dependencies.fileStore
            )
            _ = try? await service.reconcileEvidenceFiles()
        }
        router.rentalsPath = NavigationPath()
    }

    private func contactVendorSection(_ item: RentalItem) -> some View {
        Section {
            OffRentDisclosureBanner(style: .inline, identifier: A11yID.ItemDetail.disclosure)
            ContactVendorActions(item: item)
        } header: {
            Text("Contact the rental company")
        }
    }

    private func estimateSection(_ item: RentalItem) -> some View {
        let estimate = RentalRateEngine.estimate(
            terms: item.terms, asOf: dependencies.clock.now, calendar: dependencies.clock.calendar
        )
        return Section {
            if estimate.isComplete {
                DetailRow(label: "Days on rent", value: Formatters.dayCount(estimate.daysOnRent))
                DetailRow(
                    label: "\(item.terms.billingBasis.displayName) periods",
                    value: "\(estimate.periodsStarted) × \(Formatters.currency(estimate.amountPerPeriod))"
                )
                DetailRow(label: "Calculated", value: Formatters.dateAndTime(estimate.asOf))
            }
            if let next = estimate.nextRolloverDate {
                DetailRow(label: "Next rate change", value: Formatters.dateAndTime(next))
                if let increment = estimate.expectedNextIncrement {
                    DetailRow(
                        label: "Expected to add",
                        value: "\(Formatters.currency(increment)) (estimate)"
                    )
                }
            }
            if estimate.hasStoppedAccruing {
                InlineAlert(
                    message: "Stopped accruing when you marked this done.",
                    kind: .info, symbol: "pause.circle"
                )
            }
            ForEach(estimate.issues.indices, id: \.self) { index in
                InlineAlert(message: estimate.issues[index].message)
            }
        } header: {
            Text("How that was worked out")
        } footer: {
            Text(AppCopy.estimateExplanation)
        }
    }

    private func termsSection(_ item: RentalItem) -> some View {
        Section("Terms you confirmed") {
            DetailRow(label: "Delivered", value: Formatters.mediumDate(item.deliveryDate))
            DetailRow(label: "Billing basis", value: item.terms.billingBasis.displayName)
            DetailRow(label: "Rollover", value: item.terms.rolloverMode.displayName)
            DetailRow(
                label: "Daily rate",
                value: item.dailyRate.map(Formatters.currency) ?? "Not confirmed"
            )
            DetailRow(
                label: "Weekly rate",
                value: item.weeklyRate.map(Formatters.currency) ?? "Not confirmed"
            )
            DetailRow(
                label: "4-week rate",
                value: item.fourWeekRate.map(Formatters.currency) ?? "Not confirmed"
            )
            if let usage = item.includedUsageNotes, !usage.isEmpty {
                VStack(alignment: .leading, spacing: Space.tight) {
                    Text("Included usage")
                        .font(Typography.rowDetail)
                        .foregroundStyle(.secondary)
                    Text(usage)
                        .font(Typography.rowDetail)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Recorded for reference. Excess-hour charges are not calculated.")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            NavigationLink(value: RentalDestination.editItem(id: item.id)) {
                NavigationRow(title: "Edit this rental", symbol: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .minimumTapTarget()
        }
    }

    /// What the vendor said, kept apart from what the yard did.
    ///
    /// The separation is the product: a confirmation number is the user's evidence that they
    /// called and the rental company agreed a stop date. Pickup is a different event, on a
    /// different day, proving a different thing.
    @ViewBuilder
    private func offRentProofSection(_ item: RentalItem) -> some View {
        if let event = latestEvent(of: .vendorConfirmationRecorded, in: item) {
            Section {
                DetailRow(label: "Recorded", value: Formatters.dateAndTime(event.timestamp))
                if let number = event.confirmationNumber {
                    DetailRow(label: "Confirmation number", value: number, valueIsMonospaced: true)
                }
                if let representative = event.vendorRepresentative {
                    DetailRow(label: "Spoke to", value: representative)
                }
                if let method = event.contactMethod {
                    DetailRow(label: "How", value: method.displayName)
                }
                if let detail = event.detail, !detail.isEmpty {
                    DetailRow(label: "Note", value: detail)
                }
            } header: {
                Text("Off-rent confirmation")
            } footer: {
                Text("What the rental company told you.")
            }
        }
    }

    @ViewBuilder
    private func pickupSection(_ item: RentalItem) -> some View {
        if let event = latestEvent(of: .pickupRecorded, in: item) {
            Section {
                DetailRow(label: "Recorded", value: Formatters.dateAndTime(event.timestamp))
                if let detail = event.detail, !detail.isEmpty {
                    DetailRow(label: "Note", value: detail)
                }
                if event.location != nil {
                    DetailRow(label: "Location", value: "Recorded")
                }
            } header: {
                Text("Pickup")
            } footer: {
                Text("When the equipment actually left the site.")
            }
        }
    }

    @ViewBuilder
    private func invoiceSection(_ item: RentalItem) -> some View {
        if let invoice = latestInvoice(for: item) {
            Section("Invoice") {
                DetailRow(label: "Number", value: invoice.invoiceNumber ?? "Not recorded")
                DetailRow(label: "Received", value: Formatters.mediumDate(invoice.receivedDate))
                DetailRow(label: "Total", value: Formatters.currency(invoice.invoiceTotal))
                NavigationLink(value: AuditDestination.invoice(id: invoice.id)) {
                    LabeledContent("Review this invoice") {
                        Text(
                            invoice.openDiscrepancyCount > 0
                                ? "\(invoice.openDiscrepancyCount) open"
                                : "Nothing open"
                        )
                    }
                }
            }
        }
    }

    private func identificationSection(_ item: RentalItem) -> some View {
        Section("Identification") {
            if let vendor = item.agreement?.vendor {
                DetailRow(label: "Rental company", value: vendor.name)
                if let branch = vendor.branch { DetailRow(label: "Branch", value: branch) }
            }
            if let site = item.agreement?.jobSite {
                DetailRow(label: "Jobsite", value: site.name)
            }
            if let number = item.agreement?.agreementNumber {
                DetailRow(label: "Agreement number", value: number, valueIsMonospaced: true)
            }
            if let identifier = item.vendorEquipmentIdentifier {
                DetailRow(label: "Equipment ID", value: identifier, valueIsMonospaced: true)
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
        return Section("Recent activity") {
            ForEach(Array(recent.enumerated()), id: \.element.id) { index, event in
                TimelineRow(
                    event: event,
                    isFirst: index == 0,
                    isLast: index == recent.count - 1
                )
            }
            NavigationLink(value: RentalDestination.timeline(itemID: item.id)) {
                Text("See the full timeline")
            }
            .accessibilityIdentifier(A11yID.ItemDetail.timeline)
        }
    }

    private func evidenceSection(_ item: RentalItem) -> some View {
        Section("Photos and documents") {
            EvidenceGrid(assets: item.assets ?? [], fileStore: dependencies.fileStore)
            NavigationLink("Add or manage attachments") { EvidenceManagerView(itemID: item.id) }
        }
    }

    private func utilitySection(_ item: RentalItem) -> some View {
        Section {
            Button {
                showingExport = true
            } label: {
                Label("Export evidence packet", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier(A11yID.ItemDetail.exportEvidence)
        } footer: {
            Text("A PDF of this rental's record, to share yourself.")
        }
    }

    // MARK: - Lookups

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
        dependencies.derivedStateNeedsRefresh()
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
            .padding(.bottom, isLast ? 0 : Space.base)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
