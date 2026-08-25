import Foundation

/// The pieces of a place, as a map search hands them back, before anything decides what to
/// call it.
///
/// Foundation-only on purpose. The MapKit types that produce these live in the Features layer;
/// the decision about what a jobsite should be *named* is a product decision with a right and a
/// wrong answer, so it belongs where it can be tested without a map.
///
/// `Hashable` rather than merely `Equatable` because `ChosenPlace` carries one and is itself
/// `Hashable` — a SwiftUI `ForEach` over search results needs that, and `Equatable` alone
/// silently breaks the conformance of everything that holds it.
struct PlaceComponents: Hashable, Sendable {
    /// What the search called it. For a business this is the business; for an address result it
    /// is usually the street line, and occasionally just a postal code.
    var searchResultName: String?
    var street: String?
    var locality: String?
    var administrativeArea: String?
    var postalCode: String?

    init(
        searchResultName: String? = nil,
        street: String? = nil,
        locality: String? = nil,
        administrativeArea: String? = nil,
        postalCode: String? = nil
    ) {
        self.searchResultName = searchResultName
        self.street = street
        self.locality = locality
        self.administrativeArea = administrativeArea
        self.postalCode = postalCode
    }
}

/// What to call a place, and how to write its address.
///
/// This exists because of one shipped bug: a jobsite arrived on the Today map labelled `07820`.
/// A map search for a rural site with no street address returns a placemark whose name is the
/// postal code, the old code took `name` as given, and the pin then said nothing a person could
/// use. A postal code is an address component; it is not what anybody calls a jobsite.
enum PlaceNaming {

    /// True for `07820`, `07820-1234`, `K1A 0B1` — a code, not a name.
    ///
    /// Two shapes, both narrow on purpose:
    ///
    /// - **Digit-dominant**, which covers US ZIP and ZIP+4, and most of Europe.
    /// - **Alternating letter/digit**, which covers Canadian postal codes exactly.
    ///
    /// UK postcodes are deliberately *not* matched. `SW1A 1AA` and `M1 1AE` are letter-dominant,
    /// and any rule loose enough to catch them also catches `ZONE 4`, `PHASE 2` and `LOT 14B` —
    /// which are what construction sites are actually called. Mislabelling a pin `07820` was the
    /// bug; throwing away a site genuinely named `ZONE 4` would be a worse one, because nothing
    /// on screen would say it had happened.
    static func isBarePostalCode(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 10 else { return false }

        let squashed = trimmed.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        guard !squashed.isEmpty else { return false }

        var digits = 0
        for character in squashed {
            if character.isNumber {
                digits += 1
            } else if character.isLetter {
                // Lowercase means somebody wrote a word. `Bay 3` is a place; `SW1A` is a code.
                guard character.isUppercase else { return false }
            } else {
                return false
            }
        }
        guard digits > 0 else { return false }

        // Digit-dominant: 07820, 76541, 078201234.
        if digits >= squashed.count - digits { return true }

        // Canadian: strictly letter, digit, letter, digit, letter, digit.
        if squashed.count == 6 {
            let characters = Array(squashed)
            let alternates = characters.enumerated().allSatisfy { index, character in
                index % 2 == 0 ? character.isLetter : character.isNumber
            }
            if alternates { return true }
        }

        return false
    }

    /// The address line shown under the name: street, then town, state and code.
    static func formattedAddress(_ components: PlaceComponents) -> String {
        let region = [components.locality, components.administrativeArea, components.postalCode]
            .compactMap(clean)
            .joined(separator: ", ")
        return [clean(components.street), region.isEmpty ? nil : region]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    /// What to pre-fill the jobsite name with.
    ///
    /// In order of preference: the business or place the search actually named, the street, the
    /// town. A postal code is used only when there is genuinely nothing else — and then it is
    /// written as "Near 07820" rather than as a bare code, because the difference between a
    /// label and a name is the thing that made the original pin useless.
    static func suggestedSiteName(_ components: PlaceComponents) -> String {
        if let name = clean(components.searchResultName), !isBarePostalCode(name) {
            return name
        }
        if let street = clean(components.street), !isBarePostalCode(street) {
            return street
        }
        if let locality = clean(components.locality) {
            return locality
        }
        if let area = clean(components.administrativeArea) {
            return area
        }
        if let code = clean(components.postalCode) ?? clean(components.searchResultName) {
            return "Near \(code)"
        }
        return "Dropped pin"
    }

    /// A name for a pin the user dropped by hand, before any reverse geocoding comes back.
    ///
    /// Not the coordinate. A rule of this app is that raw latitude and longitude are never the
    /// primary way a place is shown, and a placeholder that reads `41.8781, -87.6298` would put
    /// exactly that on the map for as long as the network takes — or forever, offline.
    static let droppedPinPlaceholder = "Dropped pin"

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
