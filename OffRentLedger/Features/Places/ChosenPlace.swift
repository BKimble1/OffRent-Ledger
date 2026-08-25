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
    /// The placemark broken up, kept so the naming rules can see the parts rather than only the
    /// string the search happened to assemble. This is what stops a jobsite being called `07820`.
    var components: PlaceComponents

    init(
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        components: PlaceComponents = PlaceComponents()
    ) {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.components = components
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// What a row shows when there is no separate address worth printing.
    var singleLine: String { address.isEmpty ? name : "\(name) · \(address)" }

    /// What to call a jobsite here. See `PlaceNaming` for why this is not simply `name`.
    var suggestedSiteName: String { PlaceNaming.suggestedSiteName(components) }
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
        let components = PlaceComponents(
            searchResultName: mapItem.name,
            street: street.isEmpty ? nil : street,
            locality: placemark.locality,
            administrativeArea: placemark.administrativeArea,
            postalCode: placemark.postalCode
        )
        let address = PlaceNaming.formattedAddress(components)
        let name = PlaceNaming.suggestedSiteName(components)
        guard !name.isEmpty || !address.isEmpty else { return nil }

        self.init(
            name: name.isEmpty ? address : name,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            components: components
        )
    }
}
