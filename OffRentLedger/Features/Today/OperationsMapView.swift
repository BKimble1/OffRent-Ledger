import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// Everything, on one map.
///
/// The Today card answers "is anything near me"; this answers "where is *that* one". It is a map
/// filling the screen with a search field over it that searches the user's own records — never
/// the web — across equipment, identifiers, serials, company, jobsite, address, agreement number,
/// PO and status.
///
/// Two rules it does not bend:
///
/// - **A record with no coordinate is never drawn at one.** It appears in search results and in
///   a list beneath, marked `No location set`, with the action that fixes it. Putting it at (0, 0)
///   or at the map's centre would be the map telling a lie quietly.
/// - **Markers never stack.** Records within about a metre become one marker with a count, so the
///   third machine at a yard is reachable rather than buried under the first.
struct OperationsMapView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \RentalItem.modifiedAt, order: .reverse) private var items: [RentalItem]
    @Query(sort: \JobSite.name) private var jobSites: [JobSite]

    @State private var camera: MapCameraPosition = .automatic
    @State private var query = ""
    @State private var filter: MapFilter = .all
    @State private var selectedClusterID: String?
    /// A record the user opened *explicitly* — from a search result or from a cluster's list.
    ///
    /// Distinct from the map's own selection, which is a marker. Keeping them apart is what
    /// stops one clobbering the other; see `focusedRecord` for the rule that decides between
    /// them when both are set.
    @State private var focusedRecordID: UUID?
    @State private var showsLegend = false
    @State private var editingJobSiteID: UUID?

    /// Built once per change to the store, not once per keystroke.
    ///
    /// `MapIndex.build` walks every rental and every jobsite and assembles a dozen strings for
    /// each. Typing into the search field re-evaluates this body on every character, and
    /// `allRecords`, `visibleRecords`, `matches`, `clusters` and `count(for:)` each read it —
    /// so one keystroke rebuilt the entire index six times.
    @State private var allRecords: [MapRecord] = []

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                map
                controls
            }
            .safeAreaInset(edge: .bottom) { bottomPanel }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .accessibilityIdentifier(A11yID.OperationsMap.root)
        .sheet(item: Binding(
            get: { editingJobSiteID.flatMap { id in jobSites.first { $0.id == id } } },
            set: { if $0 == nil { editingJobSiteID = nil } }
        )) { site in
            JobsiteMapEditor(existing: site)
        }
        .task(id: indexKey) { allRecords = MapIndex.build(items: items, jobSites: jobSites) }
    }

    /// What `.task(id:)` compares to decide whether the index needs rebuilding.
    ///
    /// Three numbers, and no allocation. The first version of this built a string per rental and
    /// joined them, which is the very cost the cached index exists to avoid — `.task(id:)`
    /// evaluates its id on *every* render, so a thousand rentals meant a thousand string
    /// interpolations per keystroke.
    ///
    /// The latest `modifiedAt` is enough to notice an edit because every write path stamps it
    /// with the current time, so any change moves the maximum forward. The two counts catch an
    /// insertion or a deletion.
    private var indexKey: MapIndexKey {
        var latest: TimeInterval = 0
        for item in items { latest = max(latest, item.modifiedAt.timeIntervalSince1970) }
        for site in jobSites { latest = max(latest, site.modifiedAt.timeIntervalSince1970) }
        return MapIndexKey(items: items.count, jobSites: jobSites.count, latestChange: latest)
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $camera, selection: $selectedClusterID) {
            ForEach(clusters) { cluster in
                Marker(
                    markerTitle(cluster),
                    systemImage: symbol(for: cluster),
                    coordinate: CLLocationCoordinate2D(
                        latitude: cluster.latitude, longitude: cluster.longitude
                    )
                )
                .tint(tint(for: cluster))
                .tag(cluster.id)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
        .ignoresSafeArea()
        .accessibilityIdentifier(A11yID.OperationsMap.map)
    }

    /// The count is on the marker, so a stack of four is visibly four before it is tapped.
    private func markerTitle(_ cluster: MapCluster) -> String {
        cluster.isSingle ? cluster.title : "\(cluster.title) · \(cluster.badgeCount)"
    }

    // MARK: - The controls over the map

    private var controls: some View {
        VStack(spacing: Space.snug) {
            HStack(spacing: Space.snug) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: Layout.minimumTapTarget, height: Layout.minimumTapTarget)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityIdentifier(A11yID.OperationsMap.close)
                .accessibilityLabel("Close the map")

                searchField

                Button {
                    withAnimation(Motion.respecting(Motion.quick, reduceMotion: reduceMotion)) {
                        showsLegend.toggle()
                    }
                } label: {
                    Image(systemName: showsLegend ? "info.circle.fill" : "info.circle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(showsLegend ? Palette.accent : .primary)
                        .frame(width: Layout.minimumTapTarget, height: Layout.minimumTapTarget)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityIdentifier(A11yID.OperationsMap.legendToggle)
                .accessibilityLabel(showsLegend ? "Hide the key" : "Show the key")
            }

            filterRow

            if showsLegend { legend }
            if !query.isEmpty { searchResults }
        }
        .padding(.horizontal, Space.comfortable)
        .padding(.top, Space.snug)
    }

    private var searchField: some View {
        HStack(spacing: Space.snug) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Equipment, company, jobsite, ID, PO", text: $query)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                // The height comes from the text and its padding rather than from a number, so
                // the pill grows at the accessibility sizes instead of clipping what is in it.
                .padding(.vertical, Space.base - 1)
                .accessibilityIdentifier(A11yID.OperationsMap.searchField)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        // A bare 20pt glyph is a 20pt target. The glyph is unchanged; what takes
                        // the tap is Apple's 44, which on a map over a moving truck is the
                        // difference between clearing the search and panning to the next county.
                        .frame(
                            width: Layout.minimumTapTarget, height: Layout.minimumTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, Space.base)
        .frame(minHeight: Layout.minimumTapTarget)
        .background(.regularMaterial, in: Capsule())
        // The shape is stated so the whole pill takes the tap, not only the glyphs inside it.
        // Without it a tap between the magnifying glass and the placeholder falls through to the
        // map underneath, which pans instead of focusing the field.
        .contentShape(Capsule())
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.snug) {
                ForEach(MapFilter.allCases) { candidate in
                    FilterChip(
                        title: candidate.title,
                        count: count(for: candidate),
                        isSelected: filter == candidate
                    ) {
                        withAnimation(
                            Motion.respecting(Motion.quick, reduceMotion: reduceMotion)
                        ) {
                            filter = candidate
                        }
                    }
                    .accessibilityIdentifier("map.filter.\(candidate.rawValue)")
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// What the colours mean. Small, and only when asked for — a key permanently over a map is a
    /// key covering the map.
    private var legend: some View {
        VStack(alignment: .leading, spacing: Space.snug) {
            Text("What the pins mean")
                .font(Typography.sectionTitle)
                .foregroundStyle(.secondary)
            legendRow(Palette.attention, "exclamationmark.bubble", "Needs a call, or a follow-up")
            legendRow(Palette.review, "doc.text.magnifyingglass", "Invoice to review")
            legendRow(Palette.waiting, "clock", "Off rent, awaiting pickup")
            legendRow(Palette.accent, "shippingbox.fill", "On rent")
            legendRow(.secondary, "mappin.and.ellipse", "Jobsite with nothing on rent")
            Text("A pin with a number is several records at one place. Tap it to choose.")
                .font(Typography.micro)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card))
        .accessibilityIdentifier(A11yID.OperationsMap.legend)
    }

    private func legendRow(_ tint: Color, _ symbol: String, _ text: String) -> some View {
        HStack(spacing: Space.snug) {
            Image(systemName: symbol)
                .font(Typography.caption)
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(text).font(Typography.caption)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Search results

    private var searchResults: some View {
        VStack(spacing: 0) {
            if matches.isEmpty {
                Text("Nothing of yours matches “\(query)”.")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.base)
            } else {
                ForEach(Array(matches.prefix(6).enumerated()), id: \.element.id) { index, record in
                    if index > 0 { RowDivider(inset: Space.base) }
                    Button { select(record) } label: { resultRow(record) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(A11yID.OperationsMap.searchResult)
                }
                if matches.count > 6 {
                    RowDivider(inset: Space.base)
                    Text("\(matches.count - 6) more. Keep typing to narrow it down.")
                        .font(Typography.micro)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.base)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card))
        // `children: .contain` before the identifier. An accessibility modifier on a plain
        // layout container is pushed down onto everything inside it, so the bare identifier put
        // `map.searchResults` on the result row itself and the row's own `map.searchResult`
        // was gone — the search worked, the row was on screen, and the test waited eight
        // seconds for an element that had been renamed by its own parent.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.OperationsMap.searchResults)
    }

    private func resultRow(_ record: MapRecord) -> some View {
        HStack(spacing: Space.base) {
            Image(systemName: record.status?.symbolName ?? record.kind.symbolName)
                .font(Typography.rowDetail)
                .foregroundStyle(record.status.map(Palette.tint(for:)) ?? .secondary)
                .frame(width: Layout.rowIcon)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.title).font(Typography.rowTitle).foregroundStyle(.primary)
                Text(resultSubtitle(record))
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.snug)
            if !record.hasCoordinate {
                Image(systemName: "mappin.slash")
                    .font(Typography.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(Space.base)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(record.accessibilityLabel)
    }

    private func resultSubtitle(_ record: MapRecord) -> String {
        var parts: [String] = []
        if let status = record.status { parts.append(status.displayName) }
        if let subtitle = record.subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        if let site = record.jobSiteName, record.kind == .rental { parts.append(site) }
        if !record.hasCoordinate { parts.append("No location set") }
        return parts.joined(separator: " · ")
    }

    // MARK: - The detail card

    @ViewBuilder
    private var bottomPanel: some View {
        if let record = focusedRecord {
            detailCard(record)
        } else if let cluster = selectedCluster {
            if cluster.isSingle, let only = cluster.listedRecords.first {
                detailCard(only)
            } else {
                clusterCard(cluster)
            }
        } else if !unplacedRentals.isEmpty, query.isEmpty {
            unplacedCard
        }
    }

    private func detailCard(_ record: MapRecord) -> some View {
        VStack(alignment: .leading, spacing: Space.snug) {
            HStack(alignment: .firstTextBaseline, spacing: Space.snug) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title).font(Typography.rowTitle.weight(.semibold))
                    if let status = record.status {
                        Text(status.displayName)
                            .font(Typography.caption.weight(.semibold))
                            .foregroundStyle(Palette.tint(for: status))
                    }
                }
                Spacer(minLength: Space.snug)
                Button {
                    focusedRecordID = nil
                    selectedClusterID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        // As above: the glyph stays 20pt, the target becomes 44.
                        .frame(
                            width: Layout.minimumTapTarget, height: Layout.minimumTapTarget,
                            alignment: .trailing
                        )
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close this card")
            }

            if let subtitle = record.subtitle, !subtitle.isEmpty {
                Text(subtitle).font(Typography.caption).foregroundStyle(.secondary)
            }
            if let site = record.jobSiteName, record.kind == .rental {
                Text(record.address.map { "\(site) · \($0)" } ?? site)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let address = record.address, !address.isEmpty {
                Text(address)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !record.hasCoordinate {
                Text("No location set")
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(Palette.attentionText)
            }

            HStack(spacing: Space.snug) {
                if record.kind == .rental {
                    Button("Open") { open(record) }
                        .buttonStyle(.offRentSecondary)
                        .accessibilityIdentifier(A11yID.OperationsMap.openRecord)
                    Button("Edit") { edit(record) }
                        .buttonStyle(.offRentSecondary)
                        .accessibilityIdentifier(A11yID.OperationsMap.editRecord)
                    if !record.hasCoordinate {
                        Button(record.jobSiteID == nil ? "Add a location" : "Fix the location") {
                            // A rental with a jobsite is missing a *place*, which is the
                            // jobsite's business and can be fixed here. A rental with no jobsite
                            // at all needs the rental editor, which lives behind the map.
                            if let siteID = record.jobSiteID {
                                editingJobSiteID = siteID
                            } else {
                                edit(record)
                            }
                        }
                        .buttonStyle(.offRentSecondary)
                        .accessibilityIdentifier(A11yID.OperationsMap.addLocation)
                    }
                } else {
                    Button(record.hasCoordinate ? "Edit jobsite" : "Add a location") {
                        editingJobSiteID = record.id
                    }
                    .buttonStyle(.offRentSecondary)
                    .accessibilityIdentifier(A11yID.OperationsMap.addLocation)
                }
            }
        }
        .padding(Space.comfortable)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        // As above: without `.contain` this card's identifier lands on Open, Edit and
        // Add a location too, and none of the three can be addressed by name.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.OperationsMap.detailCard)
    }

    private func clusterCard(_ cluster: MapCluster) -> some View {
        VStack(alignment: .leading, spacing: Space.snug) {
            Text(cluster.title).font(Typography.rowTitle.weight(.semibold))
            Text("\(cluster.listedRecords.count) rentals at this place")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(cluster.listedRecords.enumerated()), id: \.element.id) { index, record in
                if index > 0 { RowDivider(inset: 0) }
                Button { focusedRecordID = record.id } label: { resultRow(record) }
                    .buttonStyle(.plain)
            }
        }
        .padding(Space.comfortable)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.OperationsMap.clusterCard)
    }

    /// The rentals the map cannot draw, listed rather than silently missing.
    private var unplacedCard: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            Text(
                unplacedRentals.count == 1
                    ? "1 rental has no location"
                    : "\(unplacedRentals.count) rentals have no location"
            )
            .font(Typography.rowDetail.weight(.semibold))
            Text("Search for one to give it a jobsite. Nothing is placed on the map by guessing.")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.comfortable)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .accessibilityIdentifier(A11yID.OperationsMap.unplacedNotice)
    }

    // MARK: - Actions

    private func select(_ record: MapRecord) {
        focusedRecordID = record.id
        query = ""
        guard let latitude = record.latitude, let longitude = record.longitude else {
            selectedClusterID = nil
            return
        }
        selectedClusterID = MapClustering.bucketKey(latitude: latitude, longitude: longitude)
        // No flight when Reduce Motion is on. A slower camera is still the camera travelling
        // the width of a county, which is the movement the setting exists to stop.
        withAnimation(
            Motion.respecting(Motion.standard, reduceMotion: reduceMotion, travelling: true)
        ) {
            camera = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
        }
    }

    private func open(_ record: MapRecord) {
        // Close first, then route. Pushing onto a tab's stack while a full-screen cover is up
        // leaves the user looking at the map with the rental invisibly behind it.
        dismiss()
        router.handle(.rentalItem(id: record.id))
    }

    /// Closes the map and pushes the editor, rather than presenting a sheet inside a
    /// full-screen cover. A nested presentation there has no reliable dismissal — the sheet's
    /// own Save pops it, but a swipe-down lands on a map the user thought they had left — and
    /// the rental's own screen is where an edit belongs anyway.
    private func edit(_ record: MapRecord) {
        dismiss()
        router.handle(.rentalItem(id: record.id))
        router.rentalsPath.append(RentalDestination.editItem(id: record.id))
    }

    // MARK: - Derived

    private var visibleRecords: [MapRecord] {
        MapFilter.apply(filter, to: allRecords)
    }

    private var matches: [MapRecord] {
        MapSearch.matches(visibleRecords, query: query)
    }

    private var clusters: [MapCluster] {
        MapClustering.cluster(query.isEmpty ? visibleRecords : matches)
    }

    private var unplacedRentals: [MapRecord] {
        MapClustering.unplaced(visibleRecords).filter { $0.kind == .rental }
    }

    private var selectedCluster: MapCluster? {
        guard let selectedClusterID else { return nil }
        return clusters.first { $0.id == selectedClusterID }
    }

    /// The record whose detail card is showing, or nil to fall through to the marker's cluster.
    ///
    /// This used to be an `onChange` on the map's selection that set and cleared the focused
    /// record, and it fought itself: `select(_:)` wrote the record and then wrote the cluster,
    /// the change handler ran after both, saw a cluster with three machines in it, and cleared
    /// the very card the user had just asked for. A search result for a machine at a busy yard
    /// opened a list instead — and one for a machine with no coordinate at all opened nothing.
    ///
    /// Derived instead. The rule is a sentence: an explicitly opened record wins, unless the
    /// user has since tapped a marker that does not contain it, in which case the marker is the
    /// more recent gesture and wins.
    private var focusedRecord: MapRecord? {
        guard let focusedRecordID,
              let record = allRecords.first(where: { $0.id == focusedRecordID })
        else { return nil }
        if let cluster = selectedCluster,
           !cluster.records.contains(where: { $0.id == focusedRecordID }) {
            return nil
        }
        return record
    }

    private func count(for candidate: MapFilter) -> Int {
        MapFilter.apply(candidate, to: allRecords).count
    }

    private func tint(for cluster: MapCluster) -> Color {
        guard let status = cluster.representative?.status else { return .secondary }
        return Palette.tint(for: status)
    }

    private func symbol(for cluster: MapCluster) -> String {
        guard let representative = cluster.representative else { return "mappin" }
        guard let status = representative.status else { return "mappin.and.ellipse" }
        return status.symbolName
    }
}
