import SwiftData
import SwiftUI

/// Builds and shares the evidence packet.
struct EvidenceExportSheet: View {

    let itemID: UUID

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var items: [RentalItem]

    @State private var selectedAssetIDs: Set<UUID> = []
    @State private var userNotes = ""
    @State private var generated: URL?
    @State private var isGenerating = false
    @State private var failure: String?

    init(itemID: UUID) {
        self.itemID = itemID
        _items = Query(filter: #Predicate<RentalItem> { $0.id == itemID })
    }

    private var item: RentalItem? { items.first }

    var body: some View {
        NavigationStack {
            Form {
                if !EntitlementPolicy.isAllowed(.evidencePDFExport, entitlement: dependencies.effectiveEntitlement) {
                    Section {
                        ProUpsellRow(
                            feature: .evidencePDFExport,
                            reason: .evidenceExport,
                            onTap: { reason in
                                dismiss()
                                router.presentedSheet = .paywall(reason: reason)
                            }
                        )
                    }
                }

                if let item, let packet = buildPacket(for: item) {
                    let missing = EvidencePacketBuilder.completeness(of: packet)
                    if !missing.isEmpty {
                        Section {
                            ForEach(missing, id: \.self) { line in
                                Label(line, systemImage: "info.circle")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } header: {
                            Text("What is not in this packet")
                        } footer: {
                            Text("""
                                You can still export. A reader will simply see that these were \
                                not recorded, which is more useful than a document that looks \
                                complete and is not.
                                """)
                        }
                    }
                }

                Section("Include these attachments") {
                    if let assets = item?.assets, !assets.isEmpty {
                        ForEach(assets, id: \.id) { asset in
                            Toggle(isOn: Binding(
                                get: { selectedAssetIDs.contains(asset.id) },
                                set: { include in
                                    if include { selectedAssetIDs.insert(asset.id) }
                                    else { selectedAssetIDs.remove(asset.id) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(asset.displayName)
                                    Text(Formatters.dateAndTime(asset.capturedAt))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .minimumTapTarget()
                        }
                    } else {
                        Text("No attachments on this rental.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Your notes for the packet") {
                    TextField("Anything a reader should know", text: $userNotes, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section {
                    Button {
                        Task { await generate() }
                    } label: {
                        HStack {
                            Label("Generate the packet", systemImage: "doc.badge.gearshape")
                            if isGenerating { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isGenerating || item == nil)
                    .minimumTapTarget()

                    if let generated {
                        ShareLink(item: generated) {
                            Label("Share the packet", systemImage: "square.and.arrow.up")
                        }
                        .minimumTapTarget()
                    }
                } footer: {
                    Text("""
                        The packet carries a plain-language note explaining what it is and what it \
                        is not. Read it before sending this to anyone.
                        """)
                }

                if let failure {
                    Section {
                        Label(failure, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Palette.attention)
                    }
                }
            }
            .navigationTitle("Evidence packet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                selectedAssetIDs = Set((item?.assets ?? []).map(\.id))
            }
        }
    }

    private func buildPacket(for item: RentalItem) -> EvidencePacket? {
        guard let agreement = item.agreement, let vendor = agreement.vendor else { return nil }
        let events = item.sortedEvents
        let confirmationEvent = events.last { $0.type == .vendorConfirmationRecorded }
        let pickupEvent = events.last { $0.type == .pickupRecorded }

        let invoice = (agreement.invoices ?? [])
            .filter { $0.primaryItemID == nil || $0.primaryItemID == item.id }
            .max(by: { $0.attachedAt < $1.attachedAt })

        var comparison: InvoiceComparison?
        if let invoice {
            comparison = InvoiceComparisonEngine.compare(
                InvoiceComparisonInput(
                    terms: item.terms,
                    confirmationDate: confirmationEvent?.timestamp,
                    pickupDate: pickupEvent?.timestamp,
                    invoice: invoice.value,
                    expectedRentalSubtotalOverride: invoice.expectedRentalSubtotalOverride,
                    calendar: dependencies.clock.calendar,
                    now: dependencies.clock.now
                )
            )
        }

        return EvidencePacket(
            generatedAt: dependencies.clock.now,
            appDisplayName: AppConfiguration.displayName,
            appVersion: AppConfiguration.versionAndBuild,
            companyName: AppConfiguration.companyName,
            vendor: .init(
                name: vendor.name, branch: vendor.branch, phone: vendor.phone,
                email: vendor.email, link: vendor.link
            ),
            jobSite: agreement.jobSite.map {
                .init(name: $0.name, projectIdentifier: $0.projectIdentifier, address: $0.address)
            },
            agreementNumber: agreement.agreementNumber,
            agreementStartDate: agreement.startDate,
            agreementScheduledEndDate: agreement.scheduledEndDate,
            equipmentName: item.equipmentName,
            equipmentClass: item.equipmentClass,
            vendorEquipmentIdentifier: item.vendorEquipmentIdentifier,
            serialNumber: item.serialNumber,
            status: item.status,
            terms: item.terms,
            estimate: RentalRateEngine.estimate(
                terms: item.terms, asOf: dependencies.clock.now, calendar: dependencies.clock.calendar
            ),
            timeline: events.map(\.timelineEntry),
            confirmation: confirmationEvent.map { event in
                ConfirmationEvidence(
                    confirmationNumber: event.confirmationNumber,
                    vendorRepresentative: event.vendorRepresentative,
                    contactMethod: event.contactMethod ?? .other,
                    confirmedAt: event.timestamp,
                    notes: event.detail,
                    userAffirmedContact: true,
                    acknowledgedNoConfirmationNumber: event.confirmationNumber == nil
                )
            },
            pickup: pickupEvent.map { PickupEvidence(pickedUpAt: $0.timestamp, notes: $0.detail) },
            meterUnit: item.meterUnit,
            selectedAssets: (item.assets ?? [])
                .filter { selectedAssetIDs.contains($0.id) }
                .map(\.summary),
            invoice: invoice?.value,
            comparison: comparison,
            userNotes: userNotes.nilIfBlank,
            disclaimer: EvidencePacketBuilder.disclaimer(
                appName: AppConfiguration.displayName, companyName: AppConfiguration.companyName
            )
        )
    }

    private func generate() async {
        guard let item, let packet = buildPacket(for: item) else {
            failure = "This rental is missing a vendor, so a packet cannot be assembled."
            return
        }
        guard EntitlementPolicy.isAllowed(
            .evidencePDFExport, entitlement: dependencies.effectiveEntitlement
        ) else {
            dismiss()
            router.presentedSheet = .paywall(reason: .evidenceExport)
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        let fileStore = dependencies.fileStore
        do {
            let data = try await dependencies.evidenceRenderer.render(packet: packet) { path in
                let url = fileStore.url(forRelativePath: path)
                return try? Data(contentsOf: url)
            }
            let name = "OffRentLedger-\(item.equipmentName.replacingOccurrences(of: " ", with: "-")).pdf"
            let destination = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(AppFileStore.sanitise(name))
            try data.write(to: destination, options: .atomic)
            generated = destination

            RentalWorkflowService(context: context, clock: dependencies.clock)
                .append(event: .evidenceExported, to: item, detail: "Evidence packet generated.")
            try? context.save()
        } catch {
            failure = "The packet could not be generated. \(error.localizedDescription)"
        }
    }
}
