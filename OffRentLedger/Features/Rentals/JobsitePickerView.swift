import SwiftData
import SwiftUI

/// Pick a jobsite, or make one on a map.
///
/// Same shape as the company picker, for the same reason: a searchable list whose first row is
/// `Add New`, rather than a wheel whose first entry was `New jobsite` — which made "create
/// another duplicate" the default action on a screen full of sites the user already had.
struct JobsitePickerView: View {

    @Binding var selection: UUID?
    var onPicked: (JobSite?) -> Void = { _ in }
    /// Offered when the caller can genuinely do without one. A rental that never leaves the yard
    /// does not need a jobsite, and forcing one would put a fictional site in the list.
    var allowsNone: Bool = true

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \JobSite.name) private var sites: [JobSite]

    @State private var search = ""
    @State private var creating = false
    /// See the note in `CompanyPickerView`: the nested editor has to finish closing before this
    /// one may, or SwiftUI leaves the picker up and the rental draft unreachable.
    @State private var pendingPick: JobSite?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        creating = true
                    } label: {
                        Label("Add a new jobsite", systemImage: "plus.circle.fill")
                            .foregroundStyle(Palette.accent)
                    }
                    .accessibilityIdentifier(A11yID.Jobsite.addNew)

                    if allowsNone {
                        Button {
                            selection = nil
                            onPicked(nil)
                            dismiss()
                        } label: {
                            HStack {
                                Label("No jobsite", systemImage: "minus.circle")
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                if selection == nil {
                                    Image(systemName: "checkmark")
                                        .font(Typography.rowDetail.weight(.semibold))
                                        .foregroundStyle(Palette.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .minimumTapTarget()
                        .accessibilityIdentifier(A11yID.Jobsite.noJobsite)
                    }
                }

                if filtered.isEmpty {
                    Section {
                        Text(
                            sites.isEmpty
                                ? "No jobsites yet. Add one and every rental there shows on the map."
                                : "No jobsite matches “\(search)”."
                        )
                        .font(Typography.rowDetail)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(filtered, id: \.id) { site in
                            Button { pick(site) } label: { row(site) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(A11yID.Jobsite.row(site.id))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .offRentFormBackground()
            .searchable(text: $search, prompt: "Jobsite or address")
            .navigationTitle("Jobsite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $creating) {
                JobsiteMapEditor(existing: nil, initialName: search) { created in
                    pendingPick = created
                }
            }
            .onChange(of: creating) { _, isCreating in
                guard !isCreating, let created = pendingPick else { return }
                pendingPick = nil
                pick(created)
            }
        }
        .accessibilityIdentifier(A11yID.Jobsite.pickerRoot)
    }

    private func row(_ site: JobSite) -> some View {
        HStack(spacing: Space.base) {
            RowIcon(
                symbol: site.coordinate == nil ? "mappin.and.ellipse" : "mappin.circle.fill",
                tint: site.coordinate == nil ? .secondary : Palette.accent
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(site.name).font(Typography.rowTitle).foregroundStyle(.primary)
                // Whether it is on the map is the one fact that decides where this site shows up,
                // so it is the subtitle rather than a project number nobody is looking for.
                Text(site.locationSummary)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.snug)
            if selection == site.id {
                Image(systemName: "checkmark")
                    .font(Typography.rowDetail.weight(.semibold))
                    .foregroundStyle(Palette.accent)
            }
        }
        .contentShape(Rectangle())
        .minimumTapTarget()
    }

    private func pick(_ site: JobSite) {
        selection = site.id
        onPicked(site)
        dismiss()
    }

    private var filtered: [JobSite] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sites }
        return sites.filter { site in
            let fields: [String?] = [site.name, site.placeName, site.address, site.projectIdentifier]
            let haystack: String = fields.compactMap { $0 }.joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(query)
        }
    }
}

extension JobSite {
    /// What to show under a jobsite's name. Never a coordinate: raw latitude and longitude are
    /// not how this app describes a place in the normal UI.
    var locationSummary: String {
        if let address, !address.isEmpty { return address }
        if let placeName, !placeName.isEmpty { return placeName }
        if coordinate != nil { return "Pinned on the map" }
        return "No location set"
    }
}
