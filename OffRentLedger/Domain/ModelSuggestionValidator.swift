import Foundation

/// A field an on-device model says it read off the page.
///
/// Three strings, all of them the model's claim rather than the app's fact. Nothing here is
/// trusted until `ModelSuggestionValidator` has checked it against the text the recogniser
/// actually produced.
struct ProposedField: Sendable, Equatable {
    /// The `SuggestedField` raw value the model chose.
    var field: String
    /// The value exactly as the model says it is printed.
    var value: String
    /// The line the model says it read it from, copied from the page.
    var sourceLine: String
}

/// Turns a model's proposals into suggestions, or throws them away.
///
/// A language model reading a rental contract is useful for one thing the rule parser cannot do:
/// associating a label with a figure that is not on the same line. Rate tables put "DAILY WEEKLY
/// 4-WEEK" on one row and "285.00 1,140.00 3,420.00" on the next, and a line-by-line rule has
/// nothing to match. A model reads the table.
///
/// It is also capable of producing a number that was never on the page, stated with the same
/// fluency as one that was. In an app whose whole promise is "based on the terms you confirmed",
/// that is not an acceptable failure, so the model is never the source of a value — the page is:
///
/// 1. The line the model quotes must be a line the recogniser actually produced.
/// 2. The value must appear inside the recognised text, character for character once whitespace
///    and case are normalised — as a value in its own right, and outside quotation marks.
/// 3. The value must parse as the type its field requires.
/// 4. A rule-based suggestion for the same field always wins. The parser is the floor, and where
///    the two disagree there is no way to tell which is right, so the app keeps the one whose
///    reasoning it can print.
/// 5. Nothing from a model ever arrives pre-ticked, whatever its confidence. The user chooses.
///
/// A proposal that fails any of those is dropped silently. There is no "the model thought" state
/// in this app.
enum ModelSuggestionValidator {

    /// Just under `FieldSuggestion.preselectThreshold`, so rule 5 holds by construction rather
    /// than by remembering to check it at the call site.
    static let maximumConfidence: Double = 0.79

    static let ruleName = "on-device model"

    static func validate(
        _ proposals: [ProposedField],
        against document: RecognizedDocument,
        existing: [FieldSuggestion],
        calendar: Calendar
    ) -> [FieldSuggestion] {
        let normalisedLines = document.lines.map(normalise)
        let haystack = outsideQuotation(normalise(document.rawText))
        var claimed = Set(existing.map(\.field))
        var accepted: [FieldSuggestion] = []

        for proposal in proposals {
            guard let field = SuggestedField(rawValue: proposal.field) else { continue }
            // Rule 4: the parser is the floor. Also stops a model proposing the same field twice.
            guard !claimed.contains(field) else { continue }

            let value = proposal.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            // Rule 2, before rule 1: a value that is not on the page at all is the failure worth
            // catching, and it is cheaper to check.
            guard containsAsValue(normalise(value), in: haystack) else { continue }

            // Rule 1: the quoted line has to be one of ours. Matched on a normalised prefix
            // rather than equality, because a model asked to copy a line will sometimes drop a
            // trailing column of whitespace.
            let quoted = normalise(proposal.sourceLine)
            guard !quoted.isEmpty,
                  let lineIndex = normalisedLines.firstIndex(where: {
                      $0 == quoted || $0.contains(quoted) || quoted.contains($0)
                  })
            else { continue }

            guard let parsed = parse(value, as: field, calendar: calendar) else { continue }

            claimed.insert(field)
            accepted.append(
                FieldSuggestion(
                    field: field,
                    value: parsed,
                    confidence: min(maximumConfidence, document.averageRecognitionConfidence),
                    provenance: SuggestionProvenance(
                        sourceLine: document.lines[lineIndex],
                        lineIndex: lineIndex,
                        rule: ruleName,
                        recognitionConfidence: document.averageRecognitionConfidence
                    )
                )
            )
        }
        return accepted
    }

    // MARK: - Parsing

    static func parse(_ value: String, as field: SuggestedField, calendar: Calendar) -> SuggestedValue? {
        switch field {
        case .dailyRate, .weeklyRate, .fourWeekRate, .invoiceTotal, .rentalSubtotal,
             .deliveryCharge, .pickupCharge, .fuelCharge, .damageCharge, .cleaningCharge,
             .environmentalCharge, .taxAmount:
            guard let amount = MoneyMath.parse(value), amount >= 0 else { return nil }
            return .money(amount)

        case .startDate, .scheduledEndDate, .billedThroughDate:
            guard let date = DateTextParser.parse(value, calendar: calendar) else {
                return nil
            }
            return .date(date)

        case .vendorName, .agreementNumber, .purchaseOrderNumber, .equipmentName,
             .equipmentIdentifier, .serialNumber, .invoiceNumber:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            // A "value" that is really a whole sentence is a model describing the page rather
            // than quoting it.
            guard (1...120).contains(trimmed.count) else { return nil }
            return .text(trimmed)
        }
    }

    // MARK: - What counts as "on the page"

    /// Whether `needle` appears in `haystack` as a value in its own right.
    ///
    /// `contains` was not enough, and the gap it left was the exact failure this type exists to
    /// prevent. A model proposing a daily rate of "12" was validated by a line reading `120.00`,
    /// because "12" is a substring of it — so a figure the page never stated arrived carrying the
    /// page's own authority, and the review screen offered it as something read off the document.
    /// The same hole accepts "44" from `44-118392` and "05" from `05/04/2026`.
    ///
    /// So a match has to begin and end where a value does. Not mid-word, and — the case that
    /// matters for money — not mid-number.
    static func containsAsValue(_ needle: String, in haystack: String) -> Bool {
        guard !needle.isEmpty else { return false }

        var searchFrom = haystack.startIndex
        while let found = haystack.range(of: needle, range: searchFrom..<haystack.endIndex) {
            let before = haystack[..<found.lowerBound].suffix(2)
            let after = haystack[found.upperBound...].prefix(2)
            let boundedLeft = !continuesAValue(before.last, beside: before.dropLast().last)
            let boundedRight = !continuesAValue(after.first, beside: after.dropFirst().first)
            let isRate = isPercentage(needle, followedBy: haystack[found.upperBound...])
            if boundedLeft && boundedRight && !isRate { return true }
            searchFrom = haystack.index(after: found.lowerBound)
        }
        return false
    }

    /// Whether this occurrence is a percentage rather than a value.
    ///
    /// No field this validator can accept is a percentage — `taxAmount` is an amount, not a rate.
    /// So a number printed with a percent sign after it is a rate the vendor quoted, and a model
    /// proposing `12` from `RPP (12%) ......... 136.80` has read the rate and called it money.
    /// `containsAsValue` would otherwise have said yes: `%` is neither alphanumeric nor one of
    /// the separators, so it looked like a clean right-hand boundary.
    ///
    /// The parser guards the identical hazard in `moneyBoundary`. This is the same rule on the
    /// model path.
    private static func isPercentage(_ needle: String, followedBy rest: Substring) -> Bool {
        guard needle.last?.isNumber == true else { return false }
        return rest.drop(while: { $0 == " " }).first == "%"
    }

    /// Whether `character` means the value carries on past the end of the match.
    ///
    /// A letter or a digit always does. A separator only does when something alphanumeric sits on
    /// its far side, which is what tells `120.00` (the number continues) apart from `JOB-2291.`
    /// at the end of a sentence (it does not), and keeps the `#` of `P.O. #: JOB-2291` a boundary
    /// while the `-` inside `44-118392` is not.
    private static func continuesAValue(_ character: Character?, beside neighbour: Character?) -> Bool {
        guard let character else { return false }
        if character.isLetter || character.isNumber { return true }
        guard ".,-/".contains(character), let neighbour else { return false }
        return neighbour.isLetter || neighbour.isNumber
    }

    /// The recognised text with everything between a matched pair of quotation marks removed.
    ///
    /// A figure inside quotation marks is not the page stating it. It is the page quoting
    /// something — a defined term in the conditions, an example rate in a clause, or the model's
    /// own answer echoed back into the line it claims to have copied. Either way it is not
    /// evidence that the vendor billed it, and "based on the terms you confirmed" has to mean the
    /// terms the document asserts.
    ///
    /// Only *paired* marks open a span, and an odd one out is left where it is. A stray quote is
    /// what a recogniser returns for an inches mark on a fork or a hose, and treating one of those
    /// as an opening would silently delete the rest of the document from the check.
    static func outsideQuotation(_ text: String) -> String {
        let paired = text.filter { $0 == "\"" }.count / 2 * 2
        guard paired >= 2 else { return text }

        var result = ""
        var seen = 0
        var inside = false
        for character in text {
            if character == "\"", seen < paired {
                seen += 1
                inside = seen % 2 == 1
                result.append(" ")
                continue
            }
            // Replaced rather than deleted, so the text either side of a quotation does not fuse
            // into a token the page never printed.
            result.append(inside ? " " : character)
        }
        return result
    }

    /// Case, whitespace runs and the characters OCR and typography disagree about.
    static func normalise(_ text: String) -> String {
        let unified = text
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        return unified
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
