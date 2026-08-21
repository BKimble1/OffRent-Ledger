import SwiftData
import SwiftUI

/// One machine: what it is costing, where it is in the workflow, and what to do next.
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
                EmptyStateView(
                    symbol: "questionmark.folder",
                    title: "This rental is no longer here",
                    message: "It may have been deleted. Go back to Rentals to see what you have."
                )
            }
        }
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

    @ViewBuilder
    private func content(for item: RentalItem) -> some View {
        List {
            statusSection(item)
            if item.status == .contactVendor { contactVendorSection(item) }
            estimateSection(item)
            actionsSection(item)
            termsSection(item)
            identificationSection(item)
            timelineSection(item)
            evidenceSection(item)
        }
        .listStyle(.insetGrouped)
    }

    private func statusSection(_ item: RentalItem) -> some View {
        Section {
            HStack {
                StatusChip(status: item.status)
                    .accessibilityIdentifier(A11yID.ItemDetail.status)
                Spacer()
            }
            Text(item.status.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func contactVendorSection(_ item: RentalItem) -> some View {
        Section {
            OffRentDisclosureBanner(identifier: A11yID.ItemDetail.disclosure)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            ContactVendorActions(item: item)
        } header: {
            Text("Contact vendor")
        }
    }

    private func estimateSection(_ item: RentalItem) -> some View {
        let estimate = RentalRateEngine.estimate(
            terms: item.terms, asOf: dependencies.clock.now, calendar: dependencies.clock.calendar
        )
        return Section {
            EstimateLabel(
                amount: estimate.estimatedTotal,
                isComplete: estimate.isComplete,
                unavailableReason: estimate.blockingIssue?.message
            )
            .accessibilityIdentifier(A11yID.ItemDetail.estimate)

            if estimate.isComplete {
                DetailRow(label: "Days on rent", value: Formatters.dayCount(estimate.daysOnRent))
                DetailRow(
                    label: "\(item.terms.billingBasis.displayName) periods",
                    value: "\(estimate.periodsStarted) × \(Formatters.currency(estimate.amountPerPeriod))"
                )
                DetailRow(
                    label: "Calculated as of",
                    value: Formatters.dateAndTime(estimate.asOf)
                )
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
                Label("Stopped accruing when you marked this done.", systemImage: "pause.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(estimate.issues.indices, id: \.self) { index in
                Label(estimate.issues[index].message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Palette.attention)
            }
        } header: {
            Text("Estimated rent")
        } footer: {
            Text(AppCopy.estimateExplanation)
        }
    }

    private func actionsSection(_ item: RentalItem) -> some View {
        Section("Next steps") {
            switch item.status {
            case .draft:
                Button("Mark active") { apply(.activate, to: item) }.minimumTapTarget()

            case .active:
                Button {
                    apply(.markEquipmentDone, to: item)
                } label: {
                    // Not "End rental". The button describes what the *user* did — finished with
                    // the machine — not something the app can do to a rental agreement.
                    Label("Mark equipment done", systemImage: "hand.raised")
                }
                .accessibilityIdentifier(A11yID.ItemDetail.markDone)
                .accessibilityHint(AppCopy.markDoneExplanation)
                .minimumTapTarget()
                Text(AppCopy.markDoneExplanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

            case .contactVendor:
                Button {
                    router.presentedSheet = .recordConfirmation(itemID: item.id)
                } label: {
                    Label("Record vendor confirmation", systemImage: "checkmark.rectangle.stack")
                }
                .accessibilityIdentifier(A11yID.ItemDetail.recordConfirmation)
                .minimumTapTarget()

            case .confirmationRecorded:
                Button("Awaiting pickup") { apply(.acknowledgeAwaitingPickup, to: item) }
                    .minimumTapTarget()

            case .awaitingPickup:
                Button {
                    router.presentedSheet = .recordPickup(itemID: item.id)
                } label: {
                    Label("Record pickup", systemImage: "truck.box")
                }
                .accessibilityIdentifier(A11yID.ItemDetail.recordPickup)
                .minimumTapTarget()

            case .pickedUp:
                Button("Awaiting invoice") { apply(.beginAwaitingInvoice, to: item) }
                    .minimumTapTarget()

            case .awaitingInvoice:
                Button {
                    router.presentedSheet = .attachInvoice(itemID: item.id)
                } label: {
                    Label("Attach final invoice", systemImage: "doc.badge.plus")
                }
                .accessibilityIdentifier(A11yID.ItemDetail.attachInvoice)
                .minimumTapTarget()

            case .invoiceReview, .needsFollowUp:
                if let invoice = latestInvoice(for: item) {
                    NavigationLink(value: AuditDestination.invoice(id: invoice.id)) {
                        Label("Review the invoice", systemImage: "list.clipboard")
                    }
                    .minimumTapTarget()
                }
                Button("Resolve") { resolve(item) }
                    .accessibilityIdentifier(A11yID.ItemDetail.resolve)
                    .minimumTapTarget()

            case .resolved:
                Button("Archive") { apply(.archive, to: item) }.minimumTapTarget()
                reopenButton

            case .archived:
                reopenButton
            }

            Button {
                showingExport = true
            } label: {
                Label("Export evidence packet", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier(A11yID.ItemDetail.exportEvidence)
            .minimumTapTarget()
        }
    }

    private var reopenButton: some View {
        Button("Reopen") { showingReopen = true }
            .accessibilityIdentifier(A11yID.ItemDetail.reopen)
            .minimumTapTarget()
    }

    private func termsSection(_ item: RentalItem) -> some View {
        Section("Terms you confirmed") {
            DetailRow(label: "Delivered", value: Formatters.mediumDate(item.deliveryDate))
            DetailRow(label: "Billing basis", value: item.terms.billingBasis.displayName)
            DetailRow(label: "Rollover mode", value: item.terms.rolloverMode.displayName)
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Included usage").font(.subheadline).foregroundStyle(.secondary)
                    Text(usage).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    Text("Recorded for your reference. \(AppConfiguration.displayName) does not calculate excess-hour charges.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            NavigationLink("Edit terms") { EditRentalItemView(itemID: item.id) }
                .minimumTapTarget()
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
                DetailRow(label: "Vendor equipment ID", value: identifier, valueIsMonospaced: true)
            }
            if let serial = item.serialNumber {
                DetailRow(label: "Serial number", value: serial, valueIsMonospaced: true)
            }
        }
    }

    private func timelineSection(_ item: RentalItem) -> some View {
        Section {
            ForEach(item.sortedEvents.suffix(4).reversed(), id: \.id) { event in
                TimelineRow(event: event)
            }
            NavigationLink("See the full timeline", value: RentalDestination.timeline(itemID: item.id))
                .accessibilityIdentifier(A11yID.ItemDetail.timeline)
                .minimumTapTarget()
        } header: {
            Text("Recent activity")
        }
    }

    private func evidenceSection(_ item: RentalItem) -> some View {
        Section("Photos and documents") {
            EvidenceGrid(assets: item.assets ?? [], fileStore: dependencies.fileStore)
            NavigationLink("Add or manage attachments") { EvidenceManagerView(itemID: item.id) }
                .minimumTapTarget()
        }
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

/// One timeline entry.
struct TimelineRow: View {
    let event: RentalEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.type.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.type.displayName).font(.subheadline.weight(.medium))
                Text(Formatters.dateAndTime(event.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let number = event.confirmationNumber {
                    Text("Confirmation \(number)")
                        .font(.caption)
                        .fontDesign(.monospaced)
                }
                if let representative = event.vendorRepresentative {
                    Text("Spoke to \(representative)").font(.caption).foregroundStyle(.secondary)
                }
                if let detail = event.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if event.location != nil {
                    Label("Location recorded", systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
