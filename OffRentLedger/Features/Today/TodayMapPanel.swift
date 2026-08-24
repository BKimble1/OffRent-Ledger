import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// Where the open rentals are.
///
/// One pin per jobsite rather than one per rental: two machines at the same yard have the same
/// coordinate, and two markers drawn on top of each other is a map that lies about how many
/// there are. Selecting a pin opens a card listing that site's rentals, each of which opens the
/// rental itself.
///
/// The panel draws nothing at all when no jobsite has a place. An empty map is worse than no map:
/// it takes a third of the screen to say "we know nothing", and on a dashboard that is
/// specifically about what needs doing today, that space belongs to something else.
struct TodayMapPanel: View {

    let items: [RentalItem]

    @State private var camera: MapCameraPosition = .automatic
    @State private var selectedSiteID: UUID?

    var body: some View {
        if !pins.isEmpty {
            VStack(alignment: .leading, spacing: Space.base) {
                SectionHeader(title: "On the map")

                Map(position: $camera, selection: $selectedSiteID) {
                    ForEach(pins) { pin in
                        Marker(pin.title, systemImage: pin.symbol, coordinate: pin.coordinate)
                            .tint(pin.tint)
                            .tag(pin.id)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(Palette.hairline, lineWidth: Layout.hairline)
                )
                .accessibilityIdentifier(A11yID.Today.map)
                .accessibilityLabel(
                    "Map of \(pins.count) jobsite\(pins.count == 1 ? "" : "s") with open rentals"
                )

                if let pin = selectedPin {
                    selectionCard(pin)
                } else {
                    Text("Tap a pin to see what is on rent there.")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear { camera = .automatic }
        }
    }

    // MARK: - Selection

    private var selectedPin: SitePin? {
        guard let selectedSiteID else { return nil }
        return pins.first { $0.id == selectedSiteID }
    }

    private func selectionCard(_ pin: SitePin) -> some View {
        VStack(alignment: .leading, spacing: Space.snug) {
            CardHeader(
                title: pin.title,
                subtitle: pin.subtitle,
                symbol: "mappin.circle.fill",
                tint: pin.tint
            )
            ListGroup {
                ForEach(Array(pin.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { RowDivider() }
                    NavigationLink(value: RentalDestination.item(id: item.id)) {
                        NavigationRow(
                            title: item.equipmentName,
                            subtitle: item.status.displayName,
                            symbol: item.status.symbolName,
                            tint: Palette.tint(for: item.status)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard(padding: Space.base)
        .accessibilityIdentifier(A11yID.Today.mapSelection)
    }

    // MARK: - Pins

    /// Grouped by jobsite, and only for sites that have been given a place. A rental whose site
    /// is just a name is not missing from the app — it is missing from the map, which is a
    /// different and much smaller thing.
    private var pins: [SitePin] {
        var grouped: [UUID: SitePin] = [:]
        for item in items {
            guard let site = item.agreement?.jobSite,
                  let coordinate = site.coordinate
            else { continue }
            grouped[site.id, default: SitePin(
                id: site.id,
                title: site.name,
                address: site.placeName ?? site.address ?? "",
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                items: []
            )].items.append(item)
        }
        return grouped.values.sorted { $0.title < $1.title }
    }

    struct SitePin: Identifiable {
        let id: UUID
        let title: String
        let address: String
        let latitude: Double
        let longitude: Double
        var items: [RentalItem]

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        var subtitle: String {
            let count = "\(items.count) open rental\(items.count == 1 ? "" : "s")"
            return address.isEmpty ? count : "\(count) · \(address)"
        }

        /// The most urgent status at this site decides the pin's colour, so a yard with one
        /// machine waiting on a phone call does not read as settled because the other three are.
        var tint: Color {
            let ranked = items.map(\.status).sorted { lhs, rhs in
                Self.urgency(lhs) > Self.urgency(rhs)
            }
            return Palette.tint(for: ranked.first ?? .active)
        }

        var symbol: String {
            let ranked = items.map(\.status).sorted { lhs, rhs in
                Self.urgency(lhs) > Self.urgency(rhs)
            }
            return (ranked.first ?? .active).symbolName
        }

        private static func urgency(_ status: RentalItemStatus) -> Int {
            switch status {
            case .contactVendor, .needsFollowUp: 4
            case .invoiceReview: 3
            case .awaitingPickup: 2
            case .active: 1
            default: 0
            }
        }
    }
}
