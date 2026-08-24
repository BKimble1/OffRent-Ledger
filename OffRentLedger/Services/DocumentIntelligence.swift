import Foundation
import OSLog

/// Reads a recognised page and proposes fields the rule parser did not find.
///
/// Deliberately narrow. It proposes; it never decides. Everything it returns goes through
/// `ModelSuggestionValidator`, which checks each value against the text the recogniser actually
/// produced and throws away anything that is not there. That order — model proposes, page
/// decides — is what makes this safe to put in an app whose promise is "based on the terms you
/// confirmed".
protocol DocumentIntelligence: Sendable {
    /// Whether this device can run it at all. False is normal, not an error: an older iPhone, a
    /// device with Apple Intelligence switched off, an unsupported language.
    var isAvailable: Bool { get }
    /// One sentence for the review screen when it is not available.
    var unavailableReason: String? { get }

    func propose(from document: RecognizedDocument, kind: DocumentKind) async -> [ProposedField]
}

/// The path taken on any device that cannot run the model, and in every test.
///
/// It returns nothing, which is exactly what "no model" should mean: the rule parser's
/// suggestions stand alone and the screen looks the same as it always did. Scanning must never
/// depend on a model being present.
struct UnavailableDocumentIntelligence: DocumentIntelligence {
    var isAvailable: Bool { false }
    var unavailableReason: String?
    func propose(from document: RecognizedDocument, kind: DocumentKind) async -> [ProposedField] {
        []
    }
}

/// Returns fixed proposals. Used by tests that need the validated path without a model.
struct StubDocumentIntelligence: DocumentIntelligence {
    var isAvailable: Bool { true }
    var unavailableReason: String? { nil }
    var proposals: [ProposedField] = []
    func propose(from document: RecognizedDocument, kind: DocumentKind) async -> [ProposedField] {
        proposals
    }
}

enum DocumentIntelligenceFactory {

    private static let logger = Logger(subsystem: "com.idlery.offrent", category: "scanning")

    /// The best reader this device can offer.
    static func make() -> any DocumentIntelligence {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return FoundationModelDocumentIntelligence()
        }
        return UnavailableDocumentIntelligence(
            unavailableReason: "This iPhone is running an older version of iOS."
        )
        #else
        // Built with an SDK that has no on-device model. The app still scans; it just does not
        // read tables.
        return UnavailableDocumentIntelligence(
            unavailableReason: "This build has no on-device model."
        )
        #endif
    }
}

#if canImport(FoundationModels)
import FoundationModels

/// One field the model claims to have read.
@available(iOS 26.0, *)
@Generable
struct ModelReadField {
    @Guide(description: """
        Which field this is. Use exactly one of: vendorName, agreementNumber, equipmentName, \
        equipmentIdentifier, serialNumber, startDate, scheduledEndDate, dailyRate, weeklyRate, \
        fourWeekRate, invoiceNumber, invoiceTotal, billedThroughDate, rentalSubtotal, \
        deliveryCharge, pickupCharge, fuelCharge, damageCharge, cleaningCharge, \
        environmentalCharge, taxAmount.
        """)
    var field: String

    @Guide(description: """
        The value exactly as it is printed on the page. Copy the characters. Do not reformat a \
        number, do not add a currency symbol, do not convert a date.
        """)
    var value: String

    @Guide(description: """
        The complete line of text from the document that this value appears on, copied verbatim \
        from the text you were given.
        """)
    var sourceLine: String
}

@available(iOS 26.0, *)
@Generable
struct ModelReadDocument {
    @Guide(description: """
        Every field you can find, and nothing else. Leave a field out entirely rather than \
        guessing at it.
        """)
    var fields: [ModelReadField]
}

/// Apple's on-device model, running locally.
///
/// Nothing leaves the phone. That is not a nice-to-have here: the pages this reads are rental
/// agreements and invoices with a contractor's company name, job sites and prices on them, and
/// the app's whole privacy position is that they stay on the device. A cloud model would have
/// meant rewriting the privacy screen, and would have made scanning depend on signal on a
/// jobsite, which is where scanning happens.
@available(iOS 26.0, *)
struct FoundationModelDocumentIntelligence: DocumentIntelligence {

    private static let logger = Logger(subsystem: "com.idlery.offrent", category: "scanning")

    /// Long enough for a rental agreement, short enough to stay inside the context window with
    /// room for the instructions and the reply.
    private static let characterLimit = 6_000

    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This iPhone cannot run the on-device model."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is switched off in iOS Settings."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading."
        case .unavailable:
            return "The on-device model is not available right now."
        @unknown default:
            return "The on-device model is not available right now."
        }
    }

    func propose(from document: RecognizedDocument, kind: DocumentKind) async -> [ProposedField] {
        guard isAvailable else { return [] }
        let text = String(document.rawText.prefix(Self.characterLimit))
        guard !text.isEmpty else { return [] }

        let session = LanguageModelSession(instructions: Self.instructions(for: kind))
        do {
            let response = try await session.respond(
                to: Self.prompt(for: text),
                generating: ModelReadDocument.self
            )
            return response.content.fields.map {
                ProposedField(field: $0.field, value: $0.value, sourceLine: $0.sourceLine)
            }
        } catch {
            // Every failure here is silent by design. A guardrail refusal, a context overflow or
            // a model that is busy all mean the same thing to the user: the rule parser's
            // suggestions, which is what they had before.
            Self.logger.info(
                "On-device read did not complete: \(String(describing: error), privacy: .public)"
            )
            return []
        }
    }

    private static func instructions(for kind: DocumentKind) -> String {
        """
        You are reading text recognised from a photograph of a \(kind.displayName.lowercased()) \
        for equipment rental.

        Your only job is to find values that are printed on the page and say which line each one \
        is on. You are not estimating, calculating or interpreting anything.

        Rules:
        - Copy every value exactly as printed. Never reformat, round, convert or complete one.
        - If a value is not printed on the page, leave that field out. An omitted field is \
        correct; an invented one is not.
        - Rate tables often put the labels on one line and the figures on the line below. Match \
        them by column position.
        - Never infer a rate from another rate. A weekly rate is not a daily rate times seven.
        - The line you quote must be copied from the text you were given, character for character.
        """
    }

    private static func prompt(for text: String) -> String {
        """
        Here is the recognised text. Find the fields that are printed in it.

        ---
        \(text)
        ---
        """
    }
}
#endif
