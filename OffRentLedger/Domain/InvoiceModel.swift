import Foundation

/// The categories a vendor invoice is broken into.
///
/// These are the categories the *user confirms*, not categories the app detects. OCR may suggest
/// one; the review screen always shows what it picked and lets the user change it.
enum InvoiceCategory: String, CaseIterable, Codable, Sendable {
    case rentalSubtotal
    case delivery
    case pickup
    case fuel
    case damage
    case cleaning
    case environmental
    case taxes
    case other

    var displayName: String {
        switch self {
        case .rentalSubtotal: "Rental subtotal"
        case .delivery: "Delivery"
        case .pickup: "Pickup"
        case .fuel: "Fuel / refueling"
        case .damage: "Damage"
        case .cleaning: "Cleaning"
        case .environmental: "Environmental / misc. fees"
        case .taxes: "Taxes"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .rentalSubtotal: "calendar"
        case .delivery: "shippingbox"
        case .pickup: "truck.box"
        case .fuel: "fuelpump"
        case .damage: "bandage"
        case .cleaning: "sparkles"
        case .environmental: "leaf"
        case .taxes: "percent"
        case .other: "square.grid.2x2"
        }
    }

    /// Whether the app can form an expectation for this category from the terms the user
    /// confirmed. Where it cannot, an amount is reported as "not covered by your confirmed
    /// terms" rather than as a mismatch — the app not knowing about a fee is not evidence the
    /// fee is wrong.
    var isDerivableFromTerms: Bool {
        switch self {
        case .rentalSubtotal: true
        default: false
        }
    }
}

/// How far the user has got with one invoice.
enum InvoiceReviewStatus: String, CaseIterable, Codable, Sendable {
    case notReviewed
    case inReview
    case accepted
    case followUpRecorded

    var displayName: String {
        switch self {
        case .notReviewed: "Not reviewed"
        case .inReview: "In review"
        case .accepted: "Accepted"
        case .followUpRecorded: "Follow-up recorded"
        }
    }
}

/// What the user decided about one line.
enum LineReviewState: String, CaseIterable, Codable, Sendable {
    case unreviewed
    case accepted
    case questioned

    var displayName: String {
        switch self {
        case .unreviewed: "Not reviewed"
        case .accepted: "Accepted"
        case .questioned: "Questioned"
        }
    }
}

/// One user-confirmed line off a vendor invoice.
struct InvoiceLineValue: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var category: InvoiceCategory
    var detail: String
    var quantity: Decimal?
    var unitPrice: Decimal?
    var amount: Decimal
    /// Whether this charge appears in the contract information the user entered. A "no" is a
    /// prompt to look, not an accusation.
    var appearedInContract: Bool
    var reviewState: LineReviewState

    init(
        id: UUID = UUID(),
        category: InvoiceCategory,
        detail: String = "",
        quantity: Decimal? = nil,
        unitPrice: Decimal? = nil,
        amount: Decimal,
        appearedInContract: Bool = false,
        reviewState: LineReviewState = .unreviewed
    ) {
        self.id = id
        self.category = category
        self.detail = detail
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.amount = amount
        self.appearedInContract = appearedInContract
        self.reviewState = reviewState
    }
}

/// A whole vendor invoice as the user confirmed it.
struct InvoiceValue: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var invoiceNumber: String?
    var receivedDate: Date
    var billedThroughDate: Date?
    var lines: [InvoiceLineValue]
    /// The total printed on the invoice, entered by the user. Kept separate from the sum of the
    /// lines on purpose: when they disagree, that is itself something worth showing.
    var invoiceTotal: Decimal
    var reviewStatus: InvoiceReviewStatus
    var notes: String?

    init(
        id: UUID = UUID(),
        invoiceNumber: String? = nil,
        receivedDate: Date,
        billedThroughDate: Date? = nil,
        lines: [InvoiceLineValue] = [],
        invoiceTotal: Decimal = .zero,
        reviewStatus: InvoiceReviewStatus = .notReviewed,
        notes: String? = nil
    ) {
        self.id = id
        self.invoiceNumber = invoiceNumber
        self.receivedDate = receivedDate
        self.billedThroughDate = billedThroughDate
        self.lines = lines
        self.invoiceTotal = invoiceTotal
        self.reviewStatus = reviewStatus
        self.notes = notes
    }

    func amount(for category: InvoiceCategory) -> Decimal {
        MoneyMath.sum(lines.filter { $0.category == category }.map(\.amount))
    }

    var lineSum: Decimal { MoneyMath.sum(lines.map(\.amount)) }
}
