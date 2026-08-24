import CoreLocation
import MapKit
import SwiftUI

/// A place somebody picked off a map search.
struct ChosenPlace: Equatable, Identifiable, Hashable {
    var id: String { "\(latitude),\(longitude),\(name)" }
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// What a row shows when there is no separate address worth printing.
    var singleLine: String { address.isEmpty ? name : "\(name) · \(address)" }
}

/// Search for somewhere real and pick it.
///
/// Typing a latitude and a longitude is not something anybody does on a jobsite, and a pair of
/// numbers is not checkable — a transposed digit puts a rental in the wrong state and nothing on
/// screen says so. A name and an address are checkable at a glance.
///
/// `MKLocalSearch` rather than `MKLocalSearchCompleter`: the completer returns strings that then
/// have to be resolved into coordinates in a second step, and its delegate callback is the kind
/// of thing that needs an `NSObject` and a lock to bridge into an `@Observable`. One async call
/// that returns names, addresses and coordinates together is less machinery and fewer states.
struct PlaceSearchView: View {

    /// Seeded into the field so somebody who already typed "Ridgeline" does not type it twice.
    let initialQuery: String
    let onPick: (ChosenPlace) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ChosenPlace] = []
    @State private var isSearching = false
    @State private var searchFailed = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                field
                content
            }
            .offRentScreen()
            .navigationTitle("Find a place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier(A11yID.Place.cancel)
                }
            }
        }
        .accessibilityIdentifier(A11yID.Place.root)
        .onAppear {
            if query.isEmpty { query = initialQuery }
            fieldFocused = true
        }
        // Debounced: a search per keystroke is a request per keystroke, and MapKit throttles.
        .task(id: query) { await search() }
    }

    private var field: some View {
        HStack(spacing: Space.snug) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Address, business, or place", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($fieldFocused)
                .accessibilityIdentifier(A11yID.Place.searchField)
            if isSearching {
                ProgressView().controlSize(.small)
            } else if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, Space.base)
        .frame(height: Layout.controlHeight)
        .background(Palette.sunken, in: RoundedRectangle(cornerRadius: Radius.control))
        .padding(.horizontal, Space.comfortable)
        .padding(.vertical, Space.base)
    }

    @ViewBuilder
    private var content: some View {
        if results.isEmpty {
            EmptyStateView(
                symbol: emptySymbol,
                title: emptyTitle,
                message: emptyMessage
            )
            .padding(.horizontal, Space.comfortable)
            Spacer(minLength: 0)
        } else {
            List(results) { place in
                Button {
                    onPick(place)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(Typography.rowTitle)
                            .foregroundStyle(.primary)
                        if !place.address.isEmpty {
                            Text(place.address)
                                .font(Typography.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.tight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(A11yID.Place.result)
            }
            .listStyle(.plain)
            .offRentFormBackground()
        }
    }

    private var emptySymbol: String {
        searchFailed ? "wifi.exclamationmark" : "mappin.and.ellipse"
    }

    private var emptyTitle: String {
        if searchFailed { return "Could not search" }
        return query.trimmingCharacters(in: .whitespaces).count < 3
            ? "Type a place" : "Nothing found"
    }

    private var emptyMessage: String {
        if searchFailed {
            return """
                Searching for a place needs a connection. You can still name the site by hand and \
                add the place later.
                """
        }
        return query.trimmingCharacters(in: .whitespaces).count < 3
            ? "An address, a business, or a town. Three letters is enough to start."
            : "Try the street, or the nearest town."
    }

    // MARK: - Searching

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            results = []
            searchFailed = false
            return
        }
        // The pause is the debounce. `.task(id:)` cancels this on the next keystroke, so the
        // request is only made once typing stops.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        isSearching = true
        searchFailed = false
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            results = response.mapItems.compactMap(ChosenPlace.init(mapItem:))
        } catch {
            guard !Task.isCancelled else { return }
            // A cancelled or empty search is not a failure worth a red screen; a genuinely failed
            // one is, because the user needs to know their next tap will not work either.
            results = []
            searchFailed = (error as NSError).domain != MKError.errorDomain
                || (error as NSError).code != MKError.placemarkNotFound.rawValue
        }
    }
}

extension ChosenPlace {
    /// Built from the placemark rather than from `MKMapItem.name` alone: the name of an address
    /// result is the street line, and without the town underneath two sites on the same street
    /// name in different states look identical.
    init?(mapItem: MKMapItem) {
        let placemark = mapItem.placemark
        let coordinate = placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }

        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        let region = [placemark.locality, placemark.administrativeArea, placemark.postalCode]
            .compactMap { $0 }
            .joined(separator: ", ")
        let address = [street, region].filter { !$0.isEmpty }.joined(separator: ", ")

        let name = mapItem.name ?? (street.isEmpty ? region : street)
        guard !name.isEmpty || !address.isEmpty else { return nil }

        self.init(
            name: name.isEmpty ? address : name,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }
}
