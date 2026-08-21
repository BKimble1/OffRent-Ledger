import Foundation

/// Every destination the app can be opened into from outside itself: a local notification, the
/// widget, or an App Intent.
///
/// Parsing and building live in the same type so a link the app builds is a link the app can
/// read. `DeepLinkTests` round-trips every case, which is what stops a widget tap from silently
/// landing on the wrong tab after a URL format tweak.
enum DeepLink: Sendable, Equatable {
    case today
    case rentals
    case audit
    case addRental
    case rentalItem(id: UUID)
    /// Opens the confirmation sheet for a specific item. It opens the *sheet* — it never records
    /// anything on its own. An App Intent that silently wrote a vendor confirmation would be
    /// creating evidence the user never affirmed.
    case recordConfirmation(itemID: UUID)
    case invoiceReview(invoiceID: UUID)

    private static let scheme = SharedIdentifiers.urlScheme

    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .today:
            components.host = "today"
        case .rentals:
            components.host = "rentals"
        case .audit:
            components.host = "audit"
        case .addRental:
            components.host = "add-rental"
        case let .rentalItem(id):
            components.host = "item"
            components.path = "/\(id.uuidString)"
        case let .recordConfirmation(itemID):
            components.host = "confirm"
            components.path = "/\(itemID.uuidString)"
        case let .invoiceReview(invoiceID):
            components.host = "invoice"
            components.path = "/\(invoiceID.uuidString)"
        }
        return components.url
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        guard let host = url.host()?.lowercased() else { return nil }

        // `pathComponents` starts with "/" for an absolute path; the identifier is the next one.
        let identifier = url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:))

        switch host {
        case "today": self = .today
        case "rentals": self = .rentals
        case "audit": self = .audit
        case "add-rental": self = .addRental
        case "item":
            guard let identifier else { return nil }
            self = .rentalItem(id: identifier)
        case "confirm":
            guard let identifier else { return nil }
            self = .recordConfirmation(itemID: identifier)
        case "invoice":
            guard let identifier else { return nil }
            self = .invoiceReview(invoiceID: identifier)
        default: return nil
        }
    }
}
