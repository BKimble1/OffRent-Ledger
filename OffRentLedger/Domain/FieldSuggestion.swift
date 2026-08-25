import Foundation

/// A field the parser knows how to look for on a rental contract or a vendor invoice.
enum SuggestedField: String, CaseIterable, Codable, Sendable {
    case vendorName
    case agreementNumber
    case equipmentName
    case equipmentIdentifier
    case serialNumber
    case startDate
    case scheduledEndDate
    case dailyRate
    case weeklyRate
    case fourWeekRate
    case invoiceNumber
    case invoiceTotal
    case billedThroughDate
    case rentalSubtotal
    case deliveryCharge
    case pickupCharge
    case fuelCharge
    case damageCharge
    case cleaningCharge
    case environmentalCharge
    case taxAmount

    var displayName: String {
        switch self {
        case .vendorName: "Rental company"
        case .agreementNumber: "Agreement number"
        case .equipmentName: "Equipment"
        case .equipmentIdentifier: "Vendor equipment ID"
        case .serialNumber: "Serial number"
        case .startDate: "Start date"
        case .scheduledEndDate: "Scheduled end date"
        case .dailyRate: "Daily rate"
        case .weeklyRate: "Weekly rate"
        case .fourWeekRate: "4-week rate"
        case .invoiceNumber: "Invoice number"
        case .invoiceTotal: "Invoice total"
        case .billedThroughDate: "Billed through"
        case .rentalSubtotal: "Rental subtotal"
        case .deliveryCharge: "Delivery"
        case .pickupCharge: "Pickup"
        case .fuelCharge: "Fuel / refueling"
        case .damageCharge: "Damage"
        case .cleaningCharge: "Cleaning"
        case .environmentalCharge: "Environmental / misc."
        case .taxAmount: "Taxes"
        }
    }

    var invoiceCategory: InvoiceCategory? {
        switch self {
        case .rentalSubtotal: .rentalSubtotal
        case .deliveryCharge: .delivery
        case .pickupCharge: .pickup
        case .fuelCharge: .fuel
        case .damageCharge: .damage
        case .cleaningCharge: .cleaning
        case .environmentalCharge: .environmental
        case .taxAmount: .taxes
        default: nil
        }
    }
}

enum SuggestedValue: Sendable, Equatable {
    case text(String)
    case money(Decimal)
    case date(Date)

    var textValue: String? { if case let .text(value) = self { value } else { nil } }
    var moneyValue: Decimal? { if case let .money(value) = self { value } else { nil } }
    var dateValue: Date? { if case let .date(value) = self { value } else { nil } }
}

/// Where a suggestion came from.
///
/// Kept because a user looking at a field they did not type deserves to see the line it was read
/// off, and because a mis-parse is far easier to diagnose from the source line than from the
/// value alone. It is also what lets the review screen show "read from: RENTAL RATE 285.00/DAY"
/// under a field, which is the difference between a user trusting a suggestion and guessing.
struct SuggestionProvenance: Sendable, Equatable, Codable {
    /// The recognised line the value was taken from, verbatim.
    var sourceLine: String
    /// Index into `RecognizedDocument.lines`.
    var lineIndex: Int
    /// The name of the rule that matched, for diagnostics and for the fixture tests.
    var rule: String
    /// Vision's own confidence for the text, before the parser's rule confidence is applied.
    var recognitionConfidence: Double
    /// Which page of the document the line came from, zero-based.
    ///
    /// Added because a five-page vendor invoice has a rate table on page 1 and a summary on
    /// page 4, and "read from: TOTAL DUE $3,214.00" with no page is not enough for a user to
    /// go and check it. Defaults to 0 so every existing call site and fixture still builds.
    var page: Int
    /// Where in `sourceLine` the captured value sits, as UTF-16 offsets, when the rule knows.
    ///
    /// Two integers rather than a `Range` so the type stays `Codable` without a custom
    /// implementation. `nil` when the rule matched the whole line.
    var valueStart: Int?
    var valueLength: Int?

    init(
        sourceLine: String,
        lineIndex: Int,
        rule: String,
        recognitionConfidence: Double,
        page: Int = 0,
        valueStart: Int? = nil,
        valueLength: Int? = nil
    ) {
        self.sourceLine = sourceLine
        self.lineIndex = lineIndex
        self.rule = rule
        self.recognitionConfidence = recognitionConfidence
        self.page = page
        self.valueStart = valueStart
        self.valueLength = valueLength
    }

    /// A page is only worth naming when there is more than one.
    func pageDescription(of pageCount: Int) -> String? {
        guard pageCount > 1 else { return nil }
        return "page \(page + 1)"
    }
}

struct FieldSuggestion: Sendable, Equatable, Identifiable {
    /// Threshold above which a suggestion arrives already ticked on the review screen.
    ///
    /// Deliberately high. A preselected wrong value is worse than an unselected right one,
    /// because the user's job changes from "fill this in" to "notice this is wrong".
    static let preselectThreshold: Double = 0.80

    var id: UUID
    var field: SuggestedField
    var value: SuggestedValue
    /// 0…1, combining how specific the matching rule was with how confident the text recogniser
    /// was about the characters.
    var confidence: Double
    var provenance: SuggestionProvenance

    init(
        id: UUID = UUID(),
        field: SuggestedField,
        value: SuggestedValue,
        confidence: Double,
        provenance: SuggestionProvenance
    ) {
        self.id = id
        self.field = field
        self.value = value
        self.confidence = confidence
        self.provenance = provenance
    }

    var isPreselected: Bool { confidence >= Self.preselectThreshold }

    var confidenceDescription: String {
        switch confidence {
        case 0.80...: "High confidence"
        case 0.55..<0.80: "Medium confidence"
        default: "Low confidence"
        }
    }
}

enum DocumentSource: String, Codable, Sendable {
    case documentCamera
    case photoLibrary
    case pdfImport

    var displayName: String {
        switch self {
        case .documentCamera: "Scanned"
        case .photoLibrary: "From Photos"
        case .pdfImport: "Imported PDF"
        }
    }
}

enum DocumentKind: String, Codable, Sendable, CaseIterable {
    case rentalContract
    case vendorInvoice

    var displayName: String {
        switch self {
        case .rentalContract: "Rental contract"
        case .vendorInvoice: "Vendor invoice"
        }
    }
}

/// What the text recogniser produced, before any interpretation.
///
/// `rawText` is preserved separately from the parsed suggestions for the life of the record, so
/// the user can always see the document as it was read rather than only as it was understood.
struct RecognizedDocument: Sendable, Equatable {
    var rawText: String
    var lines: [String]
    /// Which page each line came from, parallel to `lines`.
    ///
    /// Empty when the recogniser did not track it, in which case every line reports page 0.
    /// Kept as a parallel array rather than folded into a `RecognizedLine` struct so that every
    /// existing call site — three services, two stubs and forty fixtures — still compiles.
    var linePages: [Int]
    /// Mean per-line confidence reported by the recogniser, 0…1.
    var averageRecognitionConfidence: Double
    var pageCount: Int
    var source: DocumentSource

    /// The page a line was recognised on, zero-based, or 0 when unknown.
    func page(ofLineAt index: Int) -> Int {
        linePages.indices.contains(index) ? linePages[index] : 0
    }

    /// The lines on one page, with their indices into `lines`.
    func lines(onPage page: Int) -> [(index: Int, text: String)] {
        lines.enumerated()
            .filter { self.page(ofLineAt: $0.offset) == page }
            .map { (index: $0.offset, text: $0.element) }
    }

    init(
        rawText: String,
        lines: [String]? = nil,
        linePages: [Int] = [],
        averageRecognitionConfidence: Double = 1.0,
        pageCount: Int = 1,
        source: DocumentSource = .documentCamera
    ) {
        self.linePages = linePages
        self.rawText = rawText
        self.lines = lines ?? rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        self.averageRecognitionConfidence = averageRecognitionConfidence
        self.pageCount = pageCount
        self.source = source
    }
}

struct ParseResult: Sendable, Equatable {
    var suggestions: [FieldSuggestion]
    var rawText: String
    /// Lines nothing matched. Shown collapsed under "Text we could not interpret", so the user can
    /// see that the app read the page rather than wondering what it missed.
    var unmatchedLines: [String]

    func suggestion(for field: SuggestedField) -> FieldSuggestion? {
        suggestions.first { $0.field == field }
    }

    var preselected: [FieldSuggestion] { suggestions.filter(\.isPreselected) }
}
