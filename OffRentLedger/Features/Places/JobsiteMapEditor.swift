import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// A jobsite, chosen on a map.
///
/// This replaces a text-only search sheet that handed back a name and a coordinate with nothing
/// in between. Three things were wrong with that, and all three are visible in the shipped app:
///
/// 1. **No map.** Somebody searching "Quarry Lane" got a list of four rows and no way to tell
///    which one was their site.
/// 2. **No pin to drop.** A new pour on a road that does not exist yet has no searchable
///    address, and that is a large share of the sites this app is for.
/// 3. **No confirmation step.** Tapping a row saved it, so a mis-tap was a wrong location with
///    no obvious undo.
///
/// So: a real map, a search field over it, a draggable pin, an editable name, and an explicit
/// `Confirm location`. Nothing is written until that is pressed.
struct JobsiteMapEditor: View {

    /// The site being edited, or nil to create one.
    let existing: JobSite?
    /// Pre-fills the name and the search when a rental draft already has one.
    var initialName: String = ""
    var onSaved: (JobSite) -> Void = { _ in }

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var camera: MapCameraPosition = .automatic
    @State private var query = ""
    @State private var results: [ChosenPlace] = []
    @State private var isSearching = false
    @State private var searchFailed = false
    @State private var resultsAreVisible = false

    /// Where the pin is. The single source of truth for what will be saved.
    @State private var pinned: PinnedPlace?
    @State private var siteName = ""
    @State private var projectIdentifier = ""
    @State private var isDroppingByHand = false
    @State private var hasLoaded = false
    @State private var saveFailure: String?
    @State private var visibleRegion: MKCoordinateRegion?

    @FocusState private var searchIsFocused: Bool

    /// What the pin currently stands on: a coordinate, plus whatever is known about it.
    private struct PinnedPlace: Equatable {
        var latitude: Double
        var longitude: Double
        var placeName: String?
        var address: String?
        /// True when the user put it there rather than picking a search result.
        var isManual: Bool

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                map
                searchLayer
            }
            .safeAreaInset(edge: .bottom) { detailsPanel }
            .navigationTitle(existing == nil ? "New jobsite" : "Jobsite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier(A11yID.Jobsite.cancel)
                }
            }
            .onAppear(perform: load)
            .task(id: query) { await search() }
        }
        .accessibilityIdentifier(A11yID.Jobsite.root)
    }

    // MARK: - Map

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let pinned {
                    Marker(
                        siteName.nilIfBlank ?? pinned.placeName ?? PlaceNaming.droppedPinPlaceholder,
                        systemImage: "mappin",
                        coordinate: pinned.coordinate
                    )
                    .tint(Palette.accent)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .including([.gasStation, .parking])))
            .mapControls { MapCompass(); MapScaleView() }
            .onMapCameraChange { context in visibleRegion = context.region }
            // A tap anywhere puts the pin there. It is the whole answer to "this site has no
            // address" — and it is only armed while the user has asked for it, so an ordinary
            // pan on a map they are reading does not move a pin they already placed.
            // The coordinate space is stated rather than defaulted. `onTapGesture` has an
            // overload taking no parameters and one taking a `CGPoint`, and leaving the type
            // checker to pick between them from a closure's arity is the kind of ambiguity that
            // compiles here and not on the next toolchain.
            .onTapGesture(coordinateSpace: .local) { screenPoint in
                guard isDroppingByHand else { return }
                guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                dropPin(at: coordinate)
            }
            .ignoresSafeArea(edges: .bottom)
            .accessibilityIdentifier(A11yID.Jobsite.map)
            .accessibilityLabel(mapAccessibilityLabel)
        }
    }

    private var mapAccessibilityLabel: String {
        guard let pinned else { return "Map. No location chosen yet." }
        let name = siteName.nilIfBlank ?? pinned.placeName ?? PlaceNaming.droppedPinPlaceholder
        return pinned.address.map { "Map. \(name), \($0)." } ?? "Map. \(name)."
    }

    // MARK: - Search

    private var searchLayer: some View {
        VStack(spacing: Space.snug) {
            searchField
            if resultsAreVisible { resultsList }
        }
        .padding(.horizontal, Space.comfortable)
        .padding(.top, Space.snug)
    }

    private var searchField: some View {
        HStack(spacing: Space.snug) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search for an address or place", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchIsFocused)
                // The height comes from the text and its padding rather than from a number, so
                // the field grows at the accessibility sizes instead of clipping what is in it.
                // 21pt of body text plus 12 each side is the 48 this used to be nailed to.
                .padding(.vertical, Space.base)
                .onChange(of: searchIsFocused) { _, focused in
                    if focused { resultsAreVisible = true }
                }
                .accessibilityIdentifier(A11yID.Jobsite.searchField)
            if isSearching {
                ProgressView().controlSize(.small)
            } else if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        // A 20pt glyph with nothing around it is a 20pt target. The glyph is
                        // unchanged; the area that takes the tap is Apple's 44.
                        .frame(
                            width: Layout.minimumTapTarget, height: Layout.minimumTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, Space.base)
        .frame(minHeight: Layout.controlHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.control))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control)
                .strokeBorder(Palette.hairline, lineWidth: Layout.hairline)
        )
        // The whole field takes the tap, not only the glyphs in it. Without the shape, a tap in
        // the gap between the magnifying glass and the placeholder falls through to the map
        // underneath, which pans instead of focusing the field.
        .contentShape(RoundedRectangle(cornerRadius: Radius.control))
    }

    @ViewBuilder
    private var resultsList: some View {
        VStack(spacing: 0) {
            if !results.isEmpty {
                ForEach(Array(results.prefix(6).enumerated()), id: \.element.id) { index, place in
                    if index > 0 { RowDivider(inset: Space.base) }
                    Button { choose(place) } label: { resultRow(place) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(A11yID.Jobsite.searchResult)
                }
            } else if let message = searchStateMessage {
                Text(message)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.base)
            }

            RowDivider(inset: Space.base)
            Button {
                beginManualPin()
            } label: {
                HStack(spacing: Space.snug) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(isDroppingByHand ? "Tap the map to place the pin" : "Drop a pin instead")
                    Spacer(minLength: 0)
                }
                .font(Typography.rowDetail)
                .foregroundStyle(Palette.accentText)
                .padding(Space.base)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(A11yID.Jobsite.dropPin)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(Palette.hairline, lineWidth: Layout.hairline)
        )
    }

    private func resultRow(_ place: ChosenPlace) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(place.name).font(Typography.rowTitle).foregroundStyle(.primary)
            if !place.address.isEmpty {
                Text(place.address)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.base)
        .contentShape(Rectangle())
    }

    /// Every state the search can be in, said plainly. None of them loses the pin already placed.
    private var searchStateMessage: String? {
        if searchFailed {
            return """
                Searching needs a connection. You can still drop a pin on the map and name the \
                site yourself.
                """
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Search for the address, the yard, or the nearest town." }
        if trimmed.count < 3 { return "Three letters is enough to start." }
        if isSearching { return nil }
        return "Nothing found for “\(trimmed)”. Try the street, or drop a pin."
    }

    // MARK: - The details panel

    private var detailsPanel: some View {
        VStack(alignment: .leading, spacing: Space.base) {
            if let saveFailure {
                Label(saveFailure, systemImage: "externaldrive.badge.exclamationmark")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.attentionText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let pinned {
                VStack(alignment: .leading, spacing: Space.tight) {
                    // The name, editable, and pre-filled with something a person would say —
                    // never a postal code and never a coordinate.
                    FieldLabel("Jobsite name", isRequired: true)
                    TextField("Jobsite name", text: $siteName)
                        .font(Typography.rowTitle)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier(A11yID.Jobsite.name)
                        .accessibilityLabel("Jobsite name, required")

                    if let address = pinned.address, !address.isEmpty {
                        Text(address)
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(A11yID.Jobsite.address)
                    } else if pinned.isManual {
                        Text("A pin you placed. No address — the coordinate is the record.")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Project number (optional)", text: $projectIdentifier)
                        .font(Typography.caption)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }

                // §4.4 in full: a pin that arrived from a search result can still be moved.
                // Search puts the marker on the address, and on a jobsite the address is often
                // the gate rather than the pour — so "close, but not there" has to be fixable
                // without starting again.
                Button(isDroppingByHand ? "Tap the map to move the pin" : "Move the pin") {
                    beginManualPin()
                }
                .buttonStyle(.offRentSecondary)
                .accessibilityIdentifier(A11yID.Jobsite.dropPinPanel)

                Button("Confirm location", action: save)
                    .buttonStyle(.offRentPrimary)
                    .disabled(!canSave)
                    .accessibilityIdentifier(A11yID.Jobsite.confirm)

                if !canSave {
                    Text("Give the site a name to save it.")
                        .font(Typography.micro)
                        .foregroundStyle(.secondary)
                }
            } else if existing != nil || !siteName.trimmingCharacters(in: .whitespaces).isEmpty {
                // A site that has a name but no pin. Either it predates places entirely, or the
                // user is naming somewhere the map does not help with. Both are saveable: the
                // name is what the schema requires.
                FieldLabel("Jobsite name", isRequired: true)
                TextField("Jobsite name", text: $siteName)
                    .font(Typography.rowTitle)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier(A11yID.Jobsite.name)
                    .accessibilityLabel("Jobsite name, required")

                Text("This site has no location on the map yet. You can still save its name, or drop a pin first.")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Save jobsite", action: save)
                    .buttonStyle(.offRentPrimary)
                    .disabled(!canSave)
                    .accessibilityIdentifier(A11yID.Jobsite.saveWithoutPin)

                Button(isDroppingByHand ? "Cancel dropping a pin" : "Drop a pin") {
                    beginManualPin()
                }
                .buttonStyle(.offRentSecondary)
                .accessibilityIdentifier(A11yID.Jobsite.dropPinEmpty)
            } else {
                Text(
                    isDroppingByHand
                        ? "Tap the map where the site is."
                        : "Search for the site, or drop a pin where it is."
                )
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(isDroppingByHand ? "Cancel dropping a pin" : "Drop a pin") {
                    beginManualPin()
                }
                .buttonStyle(.offRentSecondary)
                .accessibilityIdentifier(A11yID.Jobsite.dropPinEmpty)
            }
        }
        .padding(.horizontal, Space.comfortable)
        .padding(.top, Space.base)
        .padding(.bottom, Space.snug)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        // A plain stack pushes an accessibility modifier down onto everything inside it,
        // so without `.contain` this identifier would replace the name field's, the
        // address field's and Confirm location's.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.Jobsite.panel)
    }

    /// A name is all the schema requires, and all this screen should.
    ///
    /// It used to require a pin as well, which made every jobsite that predates places
    /// permanently uneditable: a contractor upgrading from an earlier build opened "Ridgeline
    /// Phase 2", found the spelling wrong, and could not save the correction because the site
    /// had no coordinate and the map had nothing to confirm. It also made a name-only jobsite —
    /// a yard, a shop, anywhere the map is beside the point — impossible to create at all.
    ///
    /// §4 still holds: a *pin* is only ever written when the user has explicitly confirmed one.
    /// This is about the record, not the pin.
    private var canSave: Bool {
        !siteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let existing {
            siteName = existing.name
            projectIdentifier = existing.projectIdentifier ?? ""
            if let coordinate = existing.coordinate {
                pinned = PinnedPlace(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    placeName: existing.placeName,
                    address: existing.address,
                    isManual: existing.placeName == nil
                )
                centre(on: coordinate.latitude, longitude: coordinate.longitude)
            } else {
                query = existing.name
                resultsAreVisible = true
            }
        } else {
            siteName = initialName
            query = initialName
            resultsAreVisible = true
            searchIsFocused = initialName.isEmpty
        }
    }

    private func choose(_ place: ChosenPlace) {
        pinned = PinnedPlace(
            latitude: place.latitude,
            longitude: place.longitude,
            placeName: place.name,
            address: place.address,
            isManual: false
        )
        // Only fill the name if the user has not written their own. Somebody who typed
        // "Ridgeline Phase 2" and then searched for the address means to keep their name.
        if siteName.trimmingCharacters(in: .whitespaces).isEmpty {
            siteName = place.suggestedSiteName
        }
        isDroppingByHand = false
        resultsAreVisible = false
        searchIsFocused = false
        centre(on: place.latitude, longitude: place.longitude)
    }

    private func beginManualPin() {
        isDroppingByHand.toggle()
        if isDroppingByHand {
            searchIsFocused = false
            resultsAreVisible = false
        }
    }

    private func dropPin(at coordinate: CLLocationCoordinate2D) {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        pinned = PinnedPlace(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            placeName: nil,
            address: nil,
            isManual: true
        )
        isDroppingByHand = false
        if siteName.trimmingCharacters(in: .whitespaces).isEmpty {
            siteName = PlaceNaming.droppedPinPlaceholder
        }
        // Reverse geocoding is a convenience, not the record. If it fails, or the phone is
        // offline, the pin is still exactly where the user put it and still saveable.
        Task {
            let described = await PlaceNameResolver.describe(
                latitude: coordinate.latitude, longitude: coordinate.longitude
            )
            guard let described, pinned?.latitude == coordinate.latitude else { return }
            pinned?.address = described
            if siteName == PlaceNaming.droppedPinPlaceholder { siteName = described }
        }
    }

    /// Reduce Motion means no flight across the map. A gentler curve is still the camera
    /// travelling, which is the thing the setting was turned on to stop.
    private func centre(on latitude: Double, longitude: Double) {
        withAnimation(
            Motion.respecting(Motion.standard, reduceMotion: reduceMotion, travelling: true)
        ) {
            camera = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                )
            )
        }
    }

    private func save() {
        guard canSave else { return }
        let now = dependencies.clock.now
        let site: JobSite
        if let existing {
            site = existing
        } else {
            site = JobSite(name: "", createdAt: now, modifiedAt: now)
            context.insert(site)
        }
        site.name = siteName.trimmingCharacters(in: .whitespacesAndNewlines)
        site.projectIdentifier = projectIdentifier.nilIfBlank
        // Only written when there is one. Saving a name must never clear a place the site
        // already had, and must never invent one it has not got.
        if let pinned {
            site.placeName = pinned.placeName
            site.address = pinned.address
            site.latitude = pinned.latitude
            site.longitude = pinned.longitude
        }
        site.modifiedAt = now
        // Dismissing on a failed write would put the user back on the rental form with a jobsite
        // selected that is not in the store.
        if let problem = PersistentStore.save(context, describing: "This jobsite") {
            saveFailure = problem
            return
        }
        saveFailure = nil
        onSaved(site)
        dismiss()
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
        // request is made once typing stops rather than once per character.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        isSearching = true
        searchFailed = false
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]
        // Biased towards what the user is looking at, which is how Apple Maps behaves and what
        // makes "quarry lane" find the one two miles away rather than the one two states away.
        // No location permission is involved: this is the map's region, not the device's.
        if let visibleRegion { request.region = visibleRegion }

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            results = response.mapItems.compactMap(ChosenPlace.init(mapItem:))
            resultsAreVisible = true
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            // An empty result is not a failure worth a warning; a genuinely failed request is,
            // because the user's next tap will not work either.
            let nsError = error as NSError
            searchFailed = nsError.domain != MKError.errorDomain
                || nsError.code != MKError.placemarkNotFound.rawValue
        }
    }
}
