import SwiftData
import SwiftUI

/// Where an off-rent confirmation is written down.
///
/// This is the single most sensitive screen in the app. Everything about it is arranged so that
/// what gets saved is a record of something the user did, not something the app implies it did:
///
/// - The disclosure is at the top and cannot be dismissed.
/// - Save is disabled until the affirmation is ticked.
/// - A blank confirmation number needs a deliberate "the vendor gave no number" acknowledgement.
/// - The refusal reason is shown, not swallowed, when validation fails.
struct RecordConfirmationSheet: View {

    let itemID: UUID

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var items: [RentalItem]

    @State private var confirmationNumber = ""
    @State private var noNumberGiven = false
    @State private var representative = ""
    @State private var method: VendorContactMethod = .phone
    @State private var confirmedAt = Date()
    @State private var notes = ""
    @State private var affirmed = false
    @State private var meterReading: Decimal?
    @State private var fuelLevel: FuelLevel = .notApplicable
    @State private var capturedLocation: LocationSnapshotRecord?
    @State private var locationDenied = false
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
                if let item { Section { subjectRow(item) } }

                Section {
                    OffRentDisclosureBanner(identifier: A11yID.Confirmation.disclosure)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }

                // `Section("Title") { } footer: { }` does not exist: the string-title
                // initialiser is `Section(_:content:)` and has no footer variant. A header
                // closure is the form that takes both.
                Section {
                    TextField("Confirmation number", text: $confirmationNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .fontDesign(.monospaced)
                        .disabled(noNumberGiven)
                        .accessibilityIdentifier(A11yID.Confirmation.number)

                    Toggle("The vendor did not give a number", isOn: $noNumberGiven)
                        .accessibilityIdentifier(A11yID.Confirmation.noNumberToggle)
                        .minimumTapTarget()

                    TextField("Who confirmed it? (optional)", text: $representative)
                        .accessibilityIdentifier(A11yID.Confirmation.representative)

                    Picker("How did you contact them?", selection: $method) {
                        ForEach(VendorContactMethod.allCases, id: \.self) { option in
                            Label(option.displayName, systemImage: option.symbolName).tag(option)
                        }
                    }
                    .accessibilityIdentifier(A11yID.Confirmation.method)

                    DatePicker(
                        "Confirmed at",
                        selection: $confirmedAt,
                        in: ...dependencies.clock.now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .accessibilityIdentifier(A11yID.Confirmation.confirmedAt)
                } header: {
                    Text("The vendor's confirmation")
                } footer: {
                    Text("""
                        Rent is estimated up to this moment, not up to pickup. If the vendor \
                        confirmed off-rent at a time earlier than now, set it here.
                        """)
                }

                Section {
                    Toggle(isOn: $affirmed) {
                        Text(AppCopy.confirmationAffirmation).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier(A11yID.Confirmation.affirmation)
                    .accessibilityHint(AppCopy.confirmationAffirmationHint)
                    .minimumTapTarget()
                } footer: {
                    Text(AppCopy.confirmationAffirmationHint)
                }

                Section("Condition at off-rent (optional)") {
                    CurrencyFieldFreeform(
                        title: "Meter reading",
                        suffix: item?.meterUnit.abbreviation ?? "",
                        value: $meterReading,
                        identifier: A11yID.Confirmation.meterReading
                    )
                    Picker("Fuel level", selection: $fuelLevel) {
                        ForEach(FuelLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .accessibilityIdentifier(A11yID.Confirmation.fuelLevel)

                    locationRow

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if let rejection {
                    Section {
                        Label(rejection.message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Palette.attention)
                            .accessibilityIdentifier(A11yID.Confirmation.validationMessage)
                    }
                }
            }
            .accessibilityIdentifier(A11yID.Confirmation.root)
            .offRentFormBackground()
            .safeAreaInset(edge: .bottom) { saveBar }
            .navigationTitle("Vendor confirmation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { confirmedAt = dependencies.clock.now }
        }
    }

    /// Which machine this is about.
    ///
    /// The sheet used to open onto "Confirmation number" with nothing naming the rental. On a
    /// jobsite with four machines from the same yard, that is one wrong record away from useless.
    private func subjectRow(_ item: RentalItem) -> some View {
        HStack(spacing: Space.base) {
            RowIcon(symbol: item.status.symbolName, tint: Palette.tint(for: item.status))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.equipmentName).font(Typography.rowTitle)
                if let subtitle = subjectSubtitle(item) {
                    Text(subtitle).font(Typography.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func subjectSubtitle(_ item: RentalItem) -> String? {
        let parts: [String?] = [item.vendorEquipmentIdentifier, item.agreement?.vendor?.name]
        let joined: String = parts.compactMap { $0 }.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    /// Save, with the reason it is unavailable when it is.
    ///
    /// Disabled rather than failing on tap: the one thing that must never happen here is a
    /// confirmation saved without the user affirming it. A disabled button that does not say why
    /// is its own problem, so the bar carries the sentence.
    private var saveBar: some View {
        StickyActionBar {
            VStack(spacing: Space.snug) {
                Button("Save confirmation", action: save)
                    .buttonStyle(.offRentPrimary)
                    .accessibilityIdentifier(A11yID.Confirmation.save)
                    .disabled(!canSave)
                if !canSave {
                    Text("Tick \"\(AppCopy.confirmationAffirmation)\" above to save.")
                        .font(Typography.micro)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var locationRow: some View {
        Group {
            if let capturedLocation {
                DetailRow(
                    label: "Location",
                    value: String(
                        format: "%.4f, %.4f (±%.0f m)",
                        capturedLocation.latitude,
                        capturedLocation.longitude,
                        capturedLocation.horizontalAccuracyMetres
                    )
                )
                Button("Remove location", role: .destructive) { self.capturedLocation = nil }
                    .minimumTapTarget()
            } else {
                Button {
                    Task { await captureLocation() }
                } label: {
                    HStack {
                        Label("Add current location", systemImage: "mappin.and.ellipse")
                        if isCapturingLocation {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .accessibilityIdentifier(A11yID.Confirmation.addLocation)
                .accessibilityHint(AppCopy.locationExplanation)
                .disabled(isCapturingLocation)
                .minimumTapTarget()

                if locationDenied {
                    Text("""
                        Location is off for \(AppConfiguration.displayName). You can turn it on in \
                        Settings, or just carry on — nothing here needs it.
                        """)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var canSave: Bool {
        affirmed && (noNumberGiven || !confirmationNumber.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func captureLocation() async {
        isCapturingLocation = true
        defer { isCapturingLocation = false }
        let snapshot = await dependencies.location.requestOneTimeLocation()
        // A denial is not an error path. The user carries on and the record simply has no
        // coordinate — which is exactly what the disclosure promised.
        capturedLocation = snapshot
        locationDenied = snapshot == nil
    }

    private func save() {
        guard let item else { return dismiss() }

        let evidence = ConfirmationEvidence(
            confirmationNumber: noNumberGiven ? nil : confirmationNumber,
            vendorRepresentative: representative.isEmpty ? nil : representative,
            contactMethod: method,
            confirmedAt: confirmedAt,
            notes: notes.isEmpty ? nil : notes,
            userAffirmedContact: affirmed,
            acknowledgedNoConfirmationNumber: noNumberGiven,
            meterReading: meterReading,
            fuelLevel: fuelLevel == .notApplicable ? nil : fuelLevel
        )

        let workflow = RentalWorkflowService(context: context, clock: dependencies.clock)
        switch workflow.recordConfirmation(evidence, for: item, location: capturedLocation) {
        case .success:
            try? context.save()
            dismiss()
        case let .failure(failure):
            rejection = failure
        }
    }
}

/// A decimal field for values that are not money — meter readings, hours.
struct CurrencyFieldFreeform: View {
    let title: String
    var suffix: String = ""
    @Binding var value: Decimal?
    var identifier: String?

    @State private var text = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            TextField("—", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .accessibilityIdentifier(identifier ?? "decimalField.\(title)")
                .onChange(of: text) { _, newValue in
                    value = newValue.isEmpty ? nil : MoneyMath.parse(newValue)
                }
            if !suffix.isEmpty {
                Text(suffix).foregroundStyle(.secondary)
            }
        }
        .minimumTapTarget()
    }
}
