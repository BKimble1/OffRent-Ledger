import Foundation

/// Turns recognised text into *suggestions*.
///
/// Three properties matter more than accuracy:
///
/// 1. It is pure. Text in, suggestions out. It holds no reference to a store, a context or a
///    view model, so there is no path by which parsing writes anything. The review screen is not
///    a convention someone could forget to route through — it is the only thing that can write.
/// 2. It reports its own uncertainty. Every suggestion carries a confidence and the line it came
///    from, and only the confident ones arrive ticked.
/// 3. It is testable without a camera. `DocumentTextParserTests` runs it against synthetic
///    fixtures, which is why OCR behaviour is covered on a machine with no iOS SDK at all.
///
/// Accuracy is a distant fourth, because the review screen makes a wrong suggestion a nuisance
/// rather than a defect. That ordering is deliberate.
enum DocumentTextParser {

    // MARK: - Public

    static func parse(
        _ document: RecognizedDocument,
        kind: DocumentKind,
        calendar: Calendar
    ) -> ParseResult {

        var best: [SuggestedField: FieldSuggestion] = [:]
        var matchedLineIndices: Set<Int> = []

        // A marginal scan should not produce confident suggestions. A recogniser confidence of
        // 1.0 leaves rule confidence untouched; 0.6 scales everything to 0.8 of it, which is
        // enough to drop most rules below the preselect threshold.
        let recognitionFactor = 0.5 + 0.5 * clamp(document.averageRecognitionConfidence)

        for (index, line) in document.lines.enumerated() {
            for rule in rules(for: kind) {
                guard let match = rule.firstMatch(in: line) else { continue }
                guard let value = rule.interpret(match.text, calendar: calendar) else { continue }

                let confidence = clamp(rule.confidence * recognitionFactor)
                let candidate = FieldSuggestion(
                    field: rule.field,
                    value: value,
                    confidence: confidence,
                    provenance: SuggestionProvenance(
                        sourceLine: line,
                        lineIndex: index,
                        rule: rule.name,
                        recognitionConfidence: document.averageRecognitionConfidence,
                        page: document.page(ofLineAt: index),
                        valueStart: match.range?.location,
                        valueLength: match.range?.length
                    )
                )
                matchedLineIndices.insert(index)

                // Highest confidence wins; ties go to the earlier line, which on a rental
                // contract is nearer the header and therefore nearer the authoritative figure.
                if let existing = best[rule.field], existing.confidence >= confidence { continue }
                best[rule.field] = candidate
            }
        }

        // A second pass over label lines that carry no value of their own.
        //
        // Some vendors print the label and the value on separate lines:
        //
        //     RENTAL AGREEMENT NUMBER
        //     NG-77304
        //
        // Line-by-line matching cannot see that, and the field simply went missing — on a real
        // agreement, silently. Joining a bare label to the line beneath it and re-running the
        // rules finds it, and the join is restricted to lines with *no digits at all* so that
        // two ordinary rows are never fused into a value neither of them carries.
        for index in document.lines.indices.dropLast() {
            let label = document.lines[index]
            guard !label.contains(where: \.isNumber) else { continue }
            guard label.count <= 48 else { continue }
            let joined = label + " " + document.lines[index + 1]

            for rule in rules(for: kind) {
                guard let match = rule.firstMatch(in: joined) else { continue }
                guard let value = rule.interpret(match.text, calendar: calendar) else { continue }

                // Slightly below an inline match of the same rule, so that when a document
                // carries both forms the one printed on a single line wins — and so a joined
                // match of a 0.94 rule still lands above the preselect threshold on a clean scan.
                let confidence = clamp(rule.confidence * 0.95 * recognitionFactor)
                if let existing = best[rule.field], existing.confidence >= confidence { continue }

                best[rule.field] = FieldSuggestion(
                    field: rule.field,
                    value: value,
                    confidence: confidence,
                    provenance: SuggestionProvenance(
                        // The *joined* text is the source line, because that is what was read —
                        // showing only the label would leave the user checking a value against a
                        // line that does not contain it.
                        sourceLine: joined,
                        lineIndex: index,
                        rule: rule.name + "-joined",
                        recognitionConfidence: document.averageRecognitionConfidence,
                        page: document.page(ofLineAt: index),
                        valueStart: match.range?.location,
                        valueLength: match.range?.length
                    )
                )
                matchedLineIndices.insert(index)
                matchedLineIndices.insert(index + 1)
            }
        }

        // The vendor's own name is almost never labelled — it is the letterhead. Fall back to the
        // first line that looks like a company, at a confidence low enough that it always arrives
        // unticked.
        if best[.vendorName] == nil,
           let fallback = vendorNameFallback(document, recognitionFactor: recognitionFactor) {
            best[.vendorName] = fallback
            matchedLineIndices.insert(fallback.provenance.lineIndex)
        }

        let unmatched = document.lines.enumerated()
            .filter { !matchedLineIndices.contains($0.offset) }
            .map(\.element)

        let suggestions = best.values.sorted {
            $0.field.rawValue < $1.field.rawValue
        }

        return ParseResult(
            suggestions: suggestions, rawText: document.rawText, unmatchedLines: unmatched
        )
    }

    // MARK: - Rules

    private struct Rule {
        enum Kind { case money, date, text }

        let field: SuggestedField
        let name: String
        let confidence: Double
        let kind: Kind
        let patterns: [String]
        /// A line matching this is skipped by the rule entirely.
        ///
        /// Rental paperwork labels a weekly rate "7 DAY RATE" and a four-week rate "28 DAY RATE"
        /// often enough that a rule looking for "day" would happily read a $985 weekly figure as
        /// a daily rate — a four-fold error on the single number the whole estimate rests on.
        /// A positive pattern cannot express "not that"; this can.
        var excludeIf: String? = nil

        /// The captured value, and where in the line it sits.
        ///
        /// The range is what lets the review screen point at the figure inside the line it came
        /// from — "read from: 7 DAY RATE: **$985.00**" — rather than only naming the line.
        func firstMatch(in line: String) -> (text: String, range: NSRange?)? {
            if let excludeIf, RegexCache.matches(pattern: excludeIf, in: line) { return nil }
            for pattern in patterns {
                guard let captured = RegexCache.firstCaptureWithRange(pattern: pattern, in: line)
                else { continue }
                let trimmed = captured.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return (trimmed, captured.range) }
            }
            return nil
        }

        func interpret(_ raw: String, calendar: Calendar) -> SuggestedValue? {
            switch kind {
            case .money:
                guard let amount = MoneyMath.parse(raw), amount >= .zero else { return nil }
                return .money(amount)
            case .date:
                guard let parsed = DateTextParser.parse(raw, calendar: calendar) else { return nil }
                return .date(parsed)
            case .text:
                let cleaned = raw
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \t:#-–—"))
                    .trimmingCharacters(in: .whitespaces)
                guard cleaned.count >= 2, cleaned.count <= 120 else { return nil }
                return .text(cleaned)
            }
        }
    }

    // Money and date fragments, shared so a change to what counts as an amount applies uniformly.
    //
    // The trailing lookahead is the whole point of this being written out rather than being the
    // obvious `[0-9,.]+`. Vision reads `4,18O.00` for `4,180.00` often enough to matter — a
    // capital O where a zero belongs — and without the lookahead the fragment happily captures
    // `4,18` and stops, turning a $4,180 rental charge into $418. That is not a near-miss the
    // user notices; it is a plausible number in the right place.
    //
    // So an amount must not be followed by a letter or digit, nor by a separator that is itself
    // followed by one. Both halves are needed. With only the first, the engine backtracks: on
    // `4,18O.00` it gives up `4,18`, then `4,1`, then `4,`, and finally matches the bare `4` —
    // whose next character is a comma, which passed. One dollar, from a four-thousand-dollar
    // line, reported with high confidence. The second half closes that: a comma or a point with
    // a digit after it means the number is still going, so the match is not at its end.
    //
    // `404.O2` is rejected outright. `$5,292.22.` at the end of a sentence is not, because the
    // full stop has nothing after it. A rejected amount becomes a field the user fills in, with
    // the garbled line visible under Recognised text — which is the honest outcome.
    ///
    /// `%` is in the rejection set for a reason that cost real money on a real invoice.
    /// `SALES TAX 8.25%  130.84` is one line with two numbers on it: a rate and an amount. The
    /// old boundary accepted `8.25` because the character after it was neither a letter nor a
    /// digit — so the parser reported the tax as $8.25 at 0.90 confidence, above the threshold
    /// that pre-ticks a suggestion, and the user would have accepted a figure $122.59 short of
    /// what the vendor billed. A percentage is never an amount of money.
    private static let moneyBoundary = #"(?![0-9A-Za-z%]|[.,][0-9A-Za-z])"#
    private static let moneyFragment =
        #"\$?\s?([0-9][0-9,]*(?:\.[0-9]{1,2})?)"# + moneyBoundary
    private static let dateFragment =
        #"([0-9]{1,2}[/\-][0-9]{1,2}[/\-][0-9]{2,4}|[0-9]{4}-[0-9]{2}-[0-9]{2}|[A-Za-z]{3,9}\.?\s+[0-9]{1,2},?\s+[0-9]{4}|[0-9]{1,2}-[A-Za-z]{3}-[0-9]{2,4})"#

    /// What can sit between a label and its value.
    ///
    /// An optional colon or equals, and optionally a run of leader characters — the
    /// `DAY .................. 465.00` form that rate schedules are printed in. Two or more, so a
    /// single stray dot cannot join two unrelated things.
    /// The percentage and the closing bracket are there because rental paperwork prints the rate
    /// it charged beside the amount it produced: `SALES TAX 8.25%  130.84`,
    /// `RPP (DAMAGE WAIVER) 12%  136.80`. Without stepping over the rate, the amount is either
    /// missed entirely or — before the money boundary rejected percentages — read as the rate.
    private static let gap =
        #"\s*\)?\s*[:=]?\s*(?:[0-9]+(?:\.[0-9]+)?\s*%\s*)?(?:[.·•\-–—_]{2,}\s*)?"#

    private static let sharedRules: [Rule] = [
        Rule(field: .agreementNumber, name: "labelled-agreement-number", confidence: 0.94, kind: .text,
             patterns: [
                #"(?i)\b(?:rental\s+)?(?:agreement|contract)\s*(?:no\.?|number|#)\s*[:#]?\s*([A-Z0-9][A-Z0-9\-/]{2,})"#,
                #"(?i)\bcontract\s*[:#]\s*([A-Z0-9][A-Z0-9\-/]{2,})"#,
             ]),
        Rule(field: .agreementNumber, name: "bare-rental-number", confidence: 0.66, kind: .text,
             patterns: [#"(?i)\brental\s*#\s*([A-Z0-9][A-Z0-9\-/]{2,})"#]),

        Rule(field: .equipmentIdentifier, name: "labelled-unit-number", confidence: 0.9, kind: .text,
             patterns: [
                #"(?i)\b(?:unit|equip(?:ment)?|asset|machine)\s*(?:no\.?|number|id|#)\s*[:#]?\s*([A-Z0-9][A-Z0-9\-]{2,})"#
             ]),
        Rule(field: .serialNumber, name: "labelled-serial", confidence: 0.9, kind: .text,
             patterns: [#"(?i)\bserial\s*(?:no\.?|number|#)?\s*[:#]?\s*([A-Z0-9][A-Z0-9\-]{4,})"#]),
        Rule(field: .equipmentName, name: "labelled-equipment", confidence: 0.85, kind: .text,
             patterns: [
                #"(?i)^\s*(?:equipment|description|item|unit\s+description)\s*[:]\s*(.+)$"#
             ]),

        Rule(field: .dailyRate, name: "labelled-daily-rate", confidence: 0.94, kind: .money,
             patterns: [
                #"(?i)\b(?:daily|day)\s*(?:rate|rental)?"# + gap + moneyFragment,
                #"(?i)"# + moneyFragment + #"\s*(?:/|per\s+)day\b"#,
             ],
             excludeIf: #"(?i)\b(?:7\s*-?\s*day|28\s*-?\s*day|4\s*-?\s*week|four[\s\-]week|weekly)\b"#),
        Rule(field: .weeklyRate, name: "labelled-weekly-rate", confidence: 0.94, kind: .money,
             patterns: [
                #"(?i)\b(?:weekly|week|7[\s\-]?day)\s*(?:rate|rental)?"# + gap + moneyFragment,
                #"(?i)"# + moneyFragment + #"\s*(?:/|per\s+)week\b"#,
             ],
             excludeIf: #"(?i)\b(?:4\s*-?\s*week|four[\s\-]week|28\s*-?\s*day)\b"#),
        Rule(field: .fourWeekRate, name: "labelled-four-week-rate", confidence: 0.94, kind: .money,
             patterns: [
                #"(?i)\b(?:4[\s\-]?week|four[\s\-]week|28[\s\-]?day)\s*(?:rate|rental)?"# + gap + moneyFragment,
                #"(?i)"# + moneyFragment + #"\s*(?:/|per\s+)(?:4\s*weeks?|28\s*days?)\b"#,
             ]),
    ]

    private static let contractRules: [Rule] = [
        Rule(field: .startDate, name: "labelled-start-date", confidence: 0.92, kind: .date,
             patterns: [
                #"(?i)\b(?:date\s+out|out\s+date|start\s+date|delivery\s+date|rental\s+start|date\s+delivered)"# + gap + dateFragment
             ]),
        Rule(field: .scheduledEndDate, name: "labelled-end-date", confidence: 0.9, kind: .date,
             patterns: [
                #"(?i)\b(?:est(?:\.|imated)?\s+return|expected\s+return|due\s+(?:back|date|in)"#
                + #"|scheduled\s+end|return\s+date|end\s+date|off[\s\-]?rent\s+date|date\s+in)"#
                + gap + dateFragment
             ]),
    ]

    private static let invoiceRules: [Rule] = [
        Rule(field: .invoiceNumber, name: "labelled-invoice-number", confidence: 0.95, kind: .text,
             patterns: [#"(?i)\binvoice\s*(?:no\.?|number|#)?\s*[:#]\s*([A-Z0-9][A-Z0-9\-/]{2,})"#,
                        #"(?i)\binvoice\s*#\s*([A-Z0-9][A-Z0-9\-/]{2,})"#]),
        Rule(field: .invoiceTotal, name: "labelled-invoice-total", confidence: 0.93, kind: .money,
             patterns: [
                #"(?i)\b(?:invoice\s+total|total\s+due|amount\s+due|balance\s+due|grand\s+total)"# + gap + moneyFragment
             ]),
        Rule(field: .invoiceTotal, name: "bare-total", confidence: 0.7, kind: .money,
             patterns: [#"(?i)^\s*total"# + gap + moneyFragment + #"\s*$"#]),
        Rule(field: .billedThroughDate, name: "labelled-billed-through", confidence: 0.9, kind: .date,
             patterns: [
                #"(?i)\b(?:billed\s+through|billing\s+period\s+end(?:ing)?|through|thru)"# + gap + dateFragment
             ]),
        Rule(field: .rentalSubtotal, name: "labelled-rental-subtotal", confidence: 0.9, kind: .money,
             patterns: [
                #"(?i)\b(?:rental\s+(?:subtotal|charges?|amount)|equipment\s+rental)"# + gap + moneyFragment
             ]),
        // A bare `SUBTOTAL   1,585.90` line, which is how most invoices actually print it.
        // Lower confidence than the labelled form: on an invoice with several sections the first
        // subtotal is not necessarily the rental one, so this is offered and never pre-ticked.
        Rule(field: .rentalSubtotal, name: "bare-subtotal", confidence: 0.68, kind: .money,
             patterns: [#"(?i)\bsub[\s\-]?total"# + gap + moneyFragment]),
        Rule(field: .deliveryCharge, name: "labelled-delivery", confidence: 0.9, kind: .money,
             patterns: [#"(?i)\b(?:delivery|drop[\s\-]?off|freight\s+out)(?:\s+(?:charge|fee|surcharge|recovery))*"# + gap + moneyFragment]),
        // `PICKUP / HAUL OUT` is one line on a real invoice, and the slash used to stop the
        // match dead. The trailing group steps over a second word joined by a slash or a dash.
        Rule(field: .pickupCharge, name: "labelled-pickup", confidence: 0.9, kind: .money,
             patterns: [
                #"(?i)\b(?:pick[\s\-]?up|collection|haul[\s\-]?(?:out|off|away)?|freight\s+in|return\s+freight)"#
                + #"(?:\s*[/&\-]?\s*(?:haul|out|off|away|charge|fee|surcharge|recovery)\b)*"#
                + gap + moneyFragment
             ]),
        Rule(field: .fuelCharge, name: "labelled-fuel", confidence: 0.9, kind: .money,
             patterns: [#"(?i)\b(?:fuel|refuel(?:ing)?|diesel)(?:\s+(?:charge|fee|surcharge|recovery))*"# + gap + moneyFragment]),
        Rule(field: .damageCharge, name: "labelled-damage", confidence: 0.9, kind: .money,
             patterns: [#"(?i)\b(?:damage|repair)(?:\s+(?:charge|fee|waiver|recovery))*"# + gap + moneyFragment]),
        Rule(field: .cleaningCharge, name: "labelled-cleaning", confidence: 0.9, kind: .money,
             patterns: [#"(?i)\b(?:cleaning|wash[\s\-]?out)(?:\s+(?:charge|fee|surcharge|recovery))*"# + gap + moneyFragment]),
        Rule(field: .environmentalCharge, name: "labelled-environmental", confidence: 0.88, kind: .money,
             patterns: [#"(?i)\b(?:environmental|enviro|misc(?:ellaneous)?)(?:\s+(?:charge|fee|recovery|surcharge)){0,3}"# + gap + moneyFragment]),
        Rule(field: .taxAmount, name: "labelled-tax", confidence: 0.92, kind: .money,
             patterns: [#"(?i)\b(?:sales\s+tax|tax(?:es)?)\s*(?:\([0-9.]+%\))?"# + gap + moneyFragment]),
    ]

    private static func rules(for kind: DocumentKind) -> [Rule] {
        switch kind {
        case .rentalContract: sharedRules + contractRules
        case .vendorInvoice: sharedRules + invoiceRules
        }
    }

    // MARK: - Vendor letterhead fallback

    private static let companySuffixes = [
        "rental", "rentals", "equipment", "equip", "supply", "inc", "inc.", "llc", "l.l.c.",
        "co", "co.", "company", "corp", "corp.", "leasing", "machinery", "tool", "tools",
    ]

    private static func vendorNameFallback(
        _ document: RecognizedDocument, recognitionFactor: Double
    ) -> FieldSuggestion? {
        // Only the top of the page. A "…LLC" three quarters of the way down an invoice is a
        // liability clause, not the letterhead.
        for (index, line) in document.lines.prefix(6).enumerated() {
            let words = line.lowercased().split(separator: " ").map(String.init)
            guard words.count <= 8, line.count >= 4, line.count <= 60 else { continue }
            guard words.contains(where: { companySuffixes.contains($0) }) else { continue }
            // Skip lines that are mostly digits — an address or a phone number.
            let digits = line.filter(\.isNumber).count
            guard digits * 2 < line.count else { continue }

            return FieldSuggestion(
                field: .vendorName,
                value: .text(line),
                // Deliberately below the preselect threshold even on a perfect scan. This is a
                // guess about layout, not a labelled field.
                confidence: clamp(0.55 * recognitionFactor),
                provenance: SuggestionProvenance(
                    sourceLine: line,
                    lineIndex: index,
                    rule: "letterhead-position-guess",
                    recognitionConfidence: document.averageRecognitionConfidence
                )
            )
        }
        return nil
    }

    private static func clamp(_ value: Double) -> Double { min(1.0, max(0.0, value)) }
}

/// Compiled-once regular expressions.
///
/// `NSRegularExpression` rather than Swift's `Regex` literals on purpose: bare-slash regex
/// literals need a language-mode flag that differs between the Xcode project's Swift 5 mode and
/// the package's, and a parser that compiles in one and not the other would defeat the point of
/// sharing the file.
enum RegexCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: NSRegularExpression] = [:]

    static func expression(for pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[pattern] { return cached }
        guard let created = try? NSRegularExpression(pattern: pattern) else { return nil }
        cache[pattern] = created
        return created
    }

    static func matches(pattern: String, in text: String) -> Bool {
        guard let expression = expression(for: pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.firstMatch(in: text, range: range) != nil
    }

    /// The first capture group, and its range in the line.
    static func firstCaptureWithRange(
        pattern: String, in text: String
    ) -> (text: String, range: NSRange)? {
        guard let expression = expression(for: pattern) else { return nil }
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, options: [], range: full),
              match.numberOfRanges > 1
        else { return nil }
        let captured = match.range(at: 1)
        guard captured.location != NSNotFound,
              let swiftRange = Range(captured, in: text)
        else { return nil }
        return (String(text[swiftRange]), captured)
    }

    /// The first capture group of the first match, or nil.
    static func firstCapture(pattern: String, in text: String) -> String? {
        guard let expression = expression(for: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[captureRange])
    }
}

/// Date formats seen on US rental paperwork.
enum DateTextParser {
    private static let formats = [
        "MM/dd/yyyy", "M/d/yyyy", "MM/dd/yy", "M/d/yy",
        "MM-dd-yyyy", "M-d-yyyy", "MM-dd-yy", "M-d-yy",
        "yyyy-MM-dd",
        "MMMM d, yyyy", "MMM d, yyyy", "MMMM d yyyy", "MMM d yyyy",
        "dd-MMM-yyyy", "d-MMM-yyyy", "dd-MMM-yy", "d-MMM-yy",
    ]

    /// Parsed at noon in the calendar's own time zone.
    ///
    /// Midnight is a trap: a date stored at 00:00 in one zone is the previous day in another, and
    /// a rental that starts "a day earlier" than the contract says is a billing dispute the app
    /// caused. Noon is far from either boundary.
    static func parse(_ raw: String, calendar: Calendar) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.calendar = calendar
            formatter.dateFormat = format
            formatter.isLenient = false
            guard let parsed = formatter.date(from: trimmed) else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: parsed)
            components.hour = 12
            guard let atNoon = calendar.date(from: components) else { continue }

            // A rental contract dated 1904 or 2140 is a mis-read, not a document.
            let year = components.year ?? 0
            guard year >= 2000, year <= 2100 else { continue }
            return atNoon
        }
        return nil
    }
}
