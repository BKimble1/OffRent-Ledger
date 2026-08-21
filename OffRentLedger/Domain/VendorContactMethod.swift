import Foundation

/// How the user says they reached the rental company.
///
/// The app records the user's account of the contact. It does not observe, verify or perform it —
/// `phone` means "the user tapped call and told us they spoke to someone", not "a call was
/// placed and answered".
enum VendorContactMethod: String, CaseIterable, Codable, Sendable {
    case phone
    case email
    case textMessage
    case vendorApp
    case vendorWebsite
    case inPerson
    case other

    var displayName: String {
        switch self {
        case .phone: "Phone call"
        case .email: "Email"
        case .textMessage: "Text message"
        case .vendorApp: "Vendor app"
        case .vendorWebsite: "Vendor website"
        case .inPerson: "In person"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .phone: "phone"
        case .email: "envelope"
        case .textMessage: "message"
        case .vendorApp: "app.badge"
        case .vendorWebsite: "safari"
        case .inPerson: "person.2"
        case .other: "ellipsis.circle"
        }
    }
}

/// Fuel level as a coarse, honest scale. A gauge photograph is the real evidence; this is the
/// searchable summary next to it.
enum FuelLevel: String, CaseIterable, Codable, Sendable {
    case empty
    case quarter
    case half
    case threeQuarters
    case full
    case notApplicable

    var displayName: String {
        switch self {
        case .empty: "Empty"
        case .quarter: "1/4"
        case .half: "1/2"
        case .threeQuarters: "3/4"
        case .full: "Full"
        case .notApplicable: "Not applicable"
        }
    }
}

/// The unit a machine's meter counts in.
enum MeterUnit: String, CaseIterable, Codable, Sendable {
    case hours
    case miles
    case kilometres
    case none

    var displayName: String {
        switch self {
        case .hours: "Hours"
        case .miles: "Miles"
        case .kilometres: "Kilometres"
        case .none: "No meter"
        }
    }

    var abbreviation: String {
        switch self {
        case .hours: "hr"
        case .miles: "mi"
        case .kilometres: "km"
        case .none: ""
        }
    }
}
