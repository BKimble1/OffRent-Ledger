import CoreLocation
import Foundation

/// Turns a stored coordinate into something a person can read.
///
/// Display only. The coordinate is what gets recorded and what goes into the evidence export —
/// a reverse-geocoded name is Apple's opinion about a point, arrives over the network, and is
/// not the thing the phone actually measured. So the number stays the record and this decides
/// what the screen says about it.
///
/// It is also why the confirmation sheet still records a GPS fix rather than letting somebody
/// search for a place: "where this phone was when the call was made" and "a place the user
/// picked from a list" are different claims, and only one of them is evidence.
enum PlaceNameResolver {

    private static let geocoder = CLGeocoder()

    /// A short description — "Ridgeline Business Park, Plano" — or nil when there is no network,
    /// no match, or the request is throttled. The caller falls back to the coordinate.
    static func describe(latitude: Double, longitude: Double) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return nil
        }
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        let parts = [
            placemark.name != street ? placemark.name : nil,
            street.isEmpty ? nil : street,
            placemark.locality,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }

        // De-duplicated: Apple often returns the street as both `name` and `thoroughfare`, and
        // "1400 Ridgeline Dr, 1400 Ridgeline Dr, Plano" is worse than the raw coordinate.
        var seen = Set<String>()
        let unique = parts.filter { seen.insert($0).inserted }
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }
}
