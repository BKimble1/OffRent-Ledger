import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// Where everything is, on Today.
///
/// It used to draw nothing at all when no jobsite had a place, on the reasoning that an empty map
/// is worse than no map. That was wrong in a way the screenshots made obvious: with one rental
/// and no location the section simply was not there, so there was no way to discover that the map
/// existed, and no way to find out that a rental was missing from it. A section that appears and
/// disappears also makes Today's layout move under the reader between launches.
///
/// So it is always here. With nothing to show it says so, over the map, and stays tappable —
/// the full-screen map is where a location gets added.
struct TodayMapPanel: View {

    let items: [RentalItem]

    @Query(sort: \JobSite.name) private var jobSites: [JobSite]

    @State private var camera: MapCameraPosition = .automatic
    @State private var isPresentingFullScreen = false

    /// Built once per change, not once per read.
    ///
    /// `records` walks every rental and every jobsite and assembles a dozen strings for each.
    /// `clusters`, `pinnedCount`, `caption` and `accessibilityLabel` each used to call it, so a
    /// single render of this card rebuilt the whole index five times — and SwiftUI renders a
    /// card on a scrolling screen a great many times.
    @State private var records: [MapRecord] = []
    @State private var clusters: [MapCluster] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Space.snug) {
            SectionHeader(title: "On the map", count: pinnedCount == 0 ? nil : pinnedCount)
                .padding(.horizontal, Space.tight)

            Button {
                isPresentingFullScreen = true
            } label: {
                mapCard
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(A11yID.Today.map)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Opens the full-screen map.")

            Text(caption)
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.tight)
        }
        .fullScreenCover(isPresented: $isPresentingFullScreen) {
            OperationsMapView()
        }
        .task(id: indexKey) { rebuild() }
    }

    /// Cheap to compute and changes exactly when the index would. Comparing it is what makes
    /// `.task(id:)` a rebuild trigger rather than a rebuild on every render.
    private var indexKey: String {
        let rentals = items.map { "\($0.id)-\($0.statusRaw)-\($0.modifiedAt.timeIntervalSince1970)" }
        let sites = jobSites.map { "\($0.id)-\($0.modifiedAt.timeIntervalSince1970)" }
        return (rentals + sites).joined(separator: "|")
    }

    private func rebuild() {
        records = MapIndex.todayRecords(MapIndex.build(items: items, jobSites: jobSites))
        clusters = MapClustering.cluster(records)
    }

    // MARK: - The card

    private var mapCard: some View {
        Map(position: $camera, interactionModes: []) {
            ForEach(clusters) { cluster in
                Marker(
                    cluster.title,
                    systemImage: symbol(for: cluster),
                    coordinate: CLLocationCoordinate2D(
                        latitude: cluster.latitude, longitude: cluster.longitude
                    )
                )
                .tint(tint(for: cluster))
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay {
            // The overlay, not a replacement. The brief is explicit: with nothing in progress the
            // map still renders, with a calm centred message over it — never blank space.
            if overlayMessage != nil {
                RoundedRectangle(cornerRadius: Radius.card)
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay {
            if let overlayMessage {
                VStack(spacing: Space.tight) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                    Text(overlayMessage)
                        .font(Typography.rowTitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(Space.comfortable)
                .accessibilityIdentifier(A11yID.Today.mapEmptyOverlay)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(Palette.hairline, lineWidth: Layout.hairline)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(Space.snug)
                .background(.regularMaterial, in: Circle())
                .padding(Space.snug)
                .accessibilityHidden(true)
        }
        // The whole card, not just the pins. A map inside a button swallows taps unless the
        // shape is stated, which is how "the card looks tappable and is not" happens.
        .contentShape(RoundedRectangle(cornerRadius: Radius.card))
    }

    // MARK: - Words

    /// `nil` when there is something to look at.
    private var overlayMessage: String? {
        if openRentals.isEmpty { return "No rentals in progress" }
        if clusters.isEmpty { return "No rental has a location yet" }
        return nil
    }

    private var caption: String {
        if openRentals.isEmpty {
            return "Nothing is on rent right now. Jobsites you save will be waiting here."
        }
        if clusters.isEmpty {
            return """
                None of your open rentals has a jobsite with a location. Open the map to add one, \
                or set it from the rental itself.
                """
        }
        let unplaced = MapClustering.unplaced(records).filter { $0.kind == .rental }.count
        if unplaced > 0 {
            return unplaced == 1
                ? "Tap to open the map. 1 rental has no location yet."
                : "Tap to open the map. \(unplaced) rentals have no location yet."
        }
        return "Tap to open the map, search your rentals, and see what is where."
    }

    private var accessibilityLabel: String {
        guard !openRentals.isEmpty else { return "Map. No rentals in progress." }
        guard pinnedCount > 0 else { return "Map. No rental has a location yet." }
        return "Map. \(pinnedCount) location\(pinnedCount == 1 ? "" : "s") with open rentals."
    }

    // MARK: - Derived

    private var openRentals: [RentalItem] { items.filter { $0.status.isOpen } }

    private var pinnedCount: Int { clusters.count }

    private func tint(for cluster: MapCluster) -> Color {
        guard let representative = cluster.representative else { return Palette.waiting }
        guard let status = representative.status else { return Palette.waiting }
        return Palette.tint(for: status)
    }

    private func symbol(for cluster: MapCluster) -> String {
        guard let representative = cluster.representative else { return "mappin" }
        guard let status = representative.status else { return "mappin.and.ellipse" }
        return status.symbolName
    }
}
