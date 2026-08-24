import SwiftData
import SwiftUI

/// Records that the equipment actually left.
struct RecordPickupSheet: View {

    let itemID: UUID

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var items: [RentalItem]

    @State private var pickedUpAt = Date()
    @State private var observedBy = ""
    @State private var finalMeter: Decimal?
    @State private var finalFuel: FuelLevel = .notApplicable
    @State private var notes = ""
    @State private var capturedLocation: LocationSnapshotRecord?
    @State private var isCapturingLocation = false
    @State private var rejection: TransitionRejection?

    init(itemID: UUID) {
        self.itemID = itemID
        _items = Query(filter: #Predicate<RentalItem> { $0.id == itemID })
    }

    private var item: RentalItem? { items.first }

    var body: some View {
        NavigationStack {
            Form {
                if let item {
                    Section {
                        HStack(spacing: Space.base) {
                            RowIcon(
                                symbol: item.status.symbolName,
                                tint: Palette.tint(for: item.status)
                            )
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.equipmentName).font(Typography.rowTitle)
                                if let vendor = item.agreement?.vendor?.name {
                                    Text(vendor)
                                        .font(Typography.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Section {
                    DatePicker(
                        "Picked up",
                        selection: $pickedUpAt,
                        in: ...dependencies.clock.now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .accessibilityIdentifier(A11yID.Pickup.pickedUpAt)

                    TextField("Who saw it leave? (optional)", text: $observedBy)
                        .accessibilityIdentifier(A11yID.Pickup.observedBy)
                } footer: {
                    Text("""
                        Recording pickup does not change what you are billed. Rent was estimated \
                        up to the off-rent confirmation you recorded, not up to this moment.
                        """)
                }

                Section("Final condition (optional)") {
                    CurrencyFieldFreeform(
                        title: "Final meter reading",
                        suffix: item?.meterUnit.abbreviation ?? "",
                        value: $finalMeter,
                        identifier: A11yID.Pickup.finalMeter
                    )
                    Picker("Final fuel level", selection: $finalFuel) {
                        ForEach(FuelLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .accessibilityIdentifier(A11yID.Pickup.finalFuel)

                    if capturedLocation == nil {
                        Button {
                            Task {
                                isCapturingLocation = true
                                capturedLocation = await dependencies.location.requestOneTimeLocation()
                                isCapturingLocation = false
                            }
                        } label: {
                            HStack {
                                Label("Add current location", systemImage: "mappin.and.ellipse")
                                if isCapturingLocation { Spacer(); ProgressView() }
                            }
                        }
                        .accessibilityHint(AppCopy.locationExplanation)
                        .disabled(isCapturingLocation)
                        .minimumTapTarget()
                    } else {
                        Button("Remove location", role: .destructive) { capturedLocation = nil }
                            .minimumTapTarget()
                    }

                    TextField("Pickup notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                        .accessibilityIdentifier(A11yID.Pickup.notes)
                }

                Section {
                    NavigationLink("Add final condition photos") {
                        if let item { EvidenceManagerView(itemID: item.id) }
                    }
                    .minimumTapTarget()
                } footer: {
                    Text("Photos taken now are attached to this rental and can go into the evidence packet.")
                }

                if let rejection {
                    Section {
                        Label(rejection.message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Palette.attention)
                    }
                }
            }
            .offRentFormBackground()
            .safeAreaInset(edge: .bottom) {
                StickyActionBar {
                    VStack(spacing: Space.snug) {
                        Button("Save pickup", action: save)
                            .buttonStyle(.offRentPrimary)
                            .accessibilityIdentifier(A11yID.Pickup.save)
                        Text("Pickup is a separate record from the vendor's off-rent confirmation.")
                            .font(Typography.micro)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle("Record pickup")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier(A11yID.Pickup.root)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { pickedUpAt = dependencies.clock.now }
        }
    }

    private func save() {
        guard let item else { return dismiss() }
        let evidence = PickupEvidence(
            pickedUpAt: pickedUpAt,
            observedBy: observedBy.isEmpty ? nil : observedBy,
            finalMeterReading: finalMeter,
            finalFuelLevel: finalFuel == .notApplicable ? nil : finalFuel,
            notes: notes.isEmpty ? nil : notes
        )
        let workflow = RentalWorkflowService(context: context, clock: dependencies.clock)
        switch workflow.recordPickup(evidence, for: item, location: capturedLocation) {
        case .success:
            try? context.save()
            dismiss()
        case let .failure(failure):
            rejection = failure
        }
    }
}
