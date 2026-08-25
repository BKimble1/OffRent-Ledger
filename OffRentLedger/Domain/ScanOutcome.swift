import Foundation

extension SuggestedField {
    /// Which document a field can honestly be read off.
    ///
    /// A rental contract does not carry an invoice total and an invoice does not set the
    /// scheduled return date, so a rule that fired across kinds would be proposing a value the
    /// document cannot contain. The parser already only runs the right rules; this is the second
    /// half of the same statement, used by the review screen to count what is *usable* rather
    /// than what merely matched.
    func applies(to kind: DocumentKind) -> Bool {
        switch kind {
        case .rentalContract:
            switch self {
            case .invoiceNumber, .invoiceTotal, .billedThroughDate, .rentalSubtotal,
                 .deliveryCharge, .pickupCharge, .fuelCharge, .damageCharge, .cleaningCharge,
                 .environmentalCharge, .taxAmount:
                return false
            default:
                return true
            }
        case .vendorInvoice:
            switch self {
            case .startDate, .scheduledEndDate:
                return false
            default:
                return true
            }
        }
    }
}

/// What a finished scan actually produced, and therefore what the review screen should offer.
///
/// This type exists because of a screenshot: a residential lease, correctly recognised as
/// containing nothing about an equipment rental, under a large orange button reading
/// `Use 0 values`. The button was doing the honest thing — committing nothing — while looking
/// like the way forward, and the way forward was in fact the small grey Cancel above it.
///
/// A count of zero is not a quantity to offer. It is a different screen.
enum ScanOutcome: Sendable, Equatable {
    /// Nothing on the document maps to a field this kind of document can carry.
    case nothingFound
    /// At least one usable value. `count` is what was found, not what is ticked.
    case found(count: Int)

    static func evaluate(suggestions: [FieldSuggestion], kind: DocumentKind) -> ScanOutcome {
        let usable = suggestions.filter { $0.field.applies(to: kind) }
        return usable.isEmpty ? .nothingFound : .found(count: usable.count)
    }

    var hasAnything: Bool {
        if case .nothingFound = self { return false }
        return true
    }
}

/// The words on the review screen's controls, kept here so they can be asserted on without a
/// simulator and so `Use 0 values` cannot come back.
enum ScanReviewCopy {

    /// The commit button. Never renders a zero — the caller must not draw it at all when the
    /// selection is empty, and this asserts that by refusing to produce the string.
    static func useValues(selected: Int) -> String? {
        guard selected > 0 else { return nil }
        return selected == 1 ? "Use 1 suggested value" : "Use \(selected) suggested values"
    }

    /// Shown instead when suggestions exist but the user has unticked all of them. Carrying on
    /// by hand is a legitimate outcome and deserves its own words rather than a count of zero.
    static let enterManually = "Enter the details by hand"

    static func nothingFoundTitle(kind: DocumentKind) -> String {
        switch kind {
        case .rentalContract: "No rental details found"
        case .vendorInvoice: "No invoice details found"
        }
    }

    static func nothingFoundMessage(kind: DocumentKind, pageCount: Int) -> String {
        let pages = pageCount == 1 ? "that page" : "those \(pageCount) pages"
        switch kind {
        case .rentalContract:
            return """
                The text on \(pages) was read, but nothing on it looks like equipment, a rate or \
                a rental date. Try a sharper photo of the rate table, add the other pages, or \
                type the details in.
                """
        case .vendorInvoice:
            return """
                The text on \(pages) was read, but nothing on it looks like an invoice number, a \
                total or a charge line. Try a sharper photo, add the other pages, or type the \
                details in.
                """
        }
    }

    static let rescan = "Rescan"
    static let addPages = "Add pages"
    static let recognizedText = "Recognised text"

    /// The line under the summary. Says what was found without claiming it is right.
    static func summary(outcome: ScanOutcome, pageCount: Int) -> String {
        let pages = pageCount == 1 ? "1 page" : "\(pageCount) pages"
        switch outcome {
        case .nothingFound:
            return "Read \(pages). Nothing on them matched a field."
        case let .found(count):
            let values = count == 1 ? "1 value" : "\(count) values"
            return "Found \(values) across \(pages). Check each one before you use it."
        }
    }
}
