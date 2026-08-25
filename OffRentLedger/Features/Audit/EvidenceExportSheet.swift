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
                            .foregroundStyle(Palette.attentionText)
                    }
                }
            }
            .offRentFormBackground()
            .navigationTitle("Evidence packet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                let assets: [EvidenceAsset] = item?.assets ?? []
                selectedAssetIDs = Set(assets.map(\.id))
            }
        }
    }

    private func buildPacket(for item: RentalItem) -> EvidencePacket? {
        guard let agreement = item.agreement, let vendor = agreement.vendor else { return nil }
        let events = item.sortedEvents
        let confirmationEvent = events.last { $0.type == .vendorConfirmationRecorded }
        let pickupEvent = events.last { $0.type == .pickupRecorded }

        let invoice: VendorInvoice? = item.latestInvoice

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

        // Every non-trivial argument is hoisted into an annotated local. `EvidencePacket` takes
        // twenty-five arguments; leaving `.map { .init(...) }` closures, a leading-dot nested
        // initialiser and three chained collection calls inline made it one expression the type
        // checker has to solve whole, which is exactly what produces "unable to type-check this
        // expression in reasonable time".
        let vendorSummary = EvidencePacket.PartySummary(
            name: vendor.name, branch: vendor.branch, phone: vendor.phone,
            email: vendor.email, link: vendor.link
        )

        var siteSummary: EvidencePacket.SiteSummary?
        if let site = agreement.jobSite {
            siteSummary = EvidencePacket.SiteSummary(
                name: site.name, projectIdentifier: site.projectIdentifier, address: site.address
            )
        }

        let estimate = RentalRateEngine.estimate(
            terms: item.terms, asOf: dependencies.clock.now, calendar: dependencies.clock.calendar
        )
        let timeline: [EvidencePacket.TimelineEntry] = events.map(\.timelineEntry)

        var confirmation: ConfirmationEvidence?
        if let event = confirmationEvent {
            confirmation = ConfirmationEvidence(
                confirmationNumber: event.confirmationNumber,
                vendorRepresentative: event.vendorRepresentative,
                contactMethod: event.contactMethod ?? .other,
                confirmedAt: event.timestamp,
                notes: event.detail,
                userAffirmedContact: true,
                acknowledgedNoConfirmationNumber: event.confirmationNumber == nil,
                meterReading: event.meterReading,
                fuelLevel: event.fuelLevel
            )
        }

        var pickup: PickupEvidence?
        if let event = pickupEvent {
            pickup = PickupEvidence(
                pickedUpAt: event.timestamp,
                finalMeterReading: event.meterReading,
                finalFuelLevel: event.fuelLevel,
                notes: event.detail
            )
        }

        let allAssets: [EvidenceAsset] = item.assets ?? []
        var selectedAssets: [EvidencePacket.AssetSummary] = []
        for asset in allAssets where selectedAssetIDs.contains(asset.id) {
            selectedAssets.append(asset.summary)
        }

        let disclaimer = EvidencePacketBuilder.disclaimer(
            appName: AppConfiguration.displayName, companyName: AppConfiguration.companyName
        )

        return EvidencePacket(
            generatedAt: dependencies.clock.now,
            appDisplayName: AppConfiguration.displayName,
            appVersion: AppConfiguration.versionAndBuild,
            companyName: AppConfiguration.companyName,
            vendor: vendorSummary,
            jobSite: siteSummary,
            agreementNumber: agreement.agreementNumber,
            agreementStartDate: agreement.startDate,
            agreementScheduledEndDate: agreement.scheduledEndDate,
            equipmentName: item.equipmentName,
            equipmentClass: item.equipmentClass,
            vendorEquipmentIdentifier: item.vendorEquipmentIdentifier,
            serialNumber: item.serialNumber,
            status: item.status,
            terms: item.terms,
            estimate: estimate,
            timeline: timeline,
            confirmation: confirmation,
            pickup: pickup,
            meterUnit: item.meterUnit,
            selectedAssets: selectedAssets,
            invoice: invoice?.value,
            comparison: comparison,
            userNotes: userNotes.nilIfBlank,
            disclaimer: disclaimer
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
                .appendingPathComponent(SafePath.component(name))
            try data.write(to: destination, options: .atomic)
            generated = destination

            RentalWorkflowService(context: context, clock: dependencies.clock)
                .append(event: .evidenceExported, to: item, detail: "Evidence packet generated.")
            // The packet itself is already on disk, so this only fails to record that it was
            // made. Say so rather than leaving the timeline quietly short of an entry.
            if let problem = PersistentStore.save(context, describing: "This export") {
                failure = problem
            }
        } catch {
            failure = "The packet could not be generated. \(error.localizedDescription)"
        }
    }
}
