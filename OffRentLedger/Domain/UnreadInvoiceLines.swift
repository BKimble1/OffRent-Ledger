import Foundation

/// A recognised line the invoice parser could not turn into a suggestion.
///
/// The parser reports these as `ParseResult.unmatchedLines` and the review screen mentions how
/// many there were, folded away under the raw text. That is enough for somebody checking the
/// scan and not nearly enough for the form the scan fills in: a charge the rules did not
/// recognise simply never became a line, so the invoice was recorded smaller than the one in the
/// user's hand and nothing on screen said so.
struct UnreadInvoiceLine: Identifiable, Equatable, Sendable {
    /// Position in the list the line was salvaged from. Stable for the life of one scan, which
    /// is all a `ForEach` needs, and no `UUID` churn on every redraw.
    var id: Int
    /// The line exactly as it was read. Shown verbatim, because a user checking it against the
    /// paper needs the app's words to be the document's words.
    var text: String
    /// The amount at the end of the line, when the line ends in something unambiguously money.
    var amount: Decimal?
}

/// Picks the charge-shaped lines out of what the parser could not interpret.
///
/// Deliberately conservative in both directions. It never *adds* anything: the caller shows what
/// this returns and the user taps the ones that are real, because a line reading `TOTAL DUE
/// $3,214.00` is a charge line by shape and a double-count by meaning, and only the person
/// holding the invoice can tell. And it only offers lines that carry money, because a line with
/// no amount cannot make a total wrong.
enum UnreadInvoiceLines {

    /// Longer than this is prose — terms and conditions, a delivery address, a signature block —
    /// rather than a row off a charge table.
    static let maximumLineLength = 96

    static func chargeCandidates(in lines: [String]) -> [UnreadInvoiceLine] {
        var candidates: [UnreadInvoiceLine] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count <= maximumLineLength else { continue }
            // A description as well as a number. A bare figure on its own line is a table cell,
            // a page number or a unit count, and offering it as a charge would be guessing.
            guard trimmed.contains(where: \.isLetter) else { continue }
            guard let amount = trailingAmount(in: trimmed) else { continue }
            candidates.append(UnreadInvoiceLine(id: index, text: trimmed, amount: amount))
        }
        return candidates
    }

    /// The amount at the end of a line, when there is one that can only be money.
    ///
    /// `MoneyMath.parse` alone is too generous here: it accepts `4`, and `PALLET FORKS 4` is a
    /// quantity. So the token has to *look* like currency before it is read as currency — either
    /// it carries a currency mark, or it is written to the cent.
    static func trailingAmount(in line: String) -> Decimal? {
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let last = tokens.last, looksLikeMoney(last) else { return nil }
        guard let amount = MoneyMath.parse(last) else { return nil }
        // Zero and credits are real on an invoice, but neither makes a total larger, and offering
        // them as "charges you may be missing" would be noise on every scan.
        return amount > .zero ? amount : nil
    }

    private static func looksLikeMoney(_ token: String) -> Bool {
        var text = token
        if text.hasPrefix("(") && text.hasSuffix(")") {
            text = String(text.dropFirst().dropLast())
        }
        if text.hasPrefix("-") { text = String(text.dropFirst()) }
        guard text.contains(where: \.isNumber) else { return false }
        if text.hasPrefix("$") || text.uppercased().hasPrefix("USD") { return true }

        // Otherwise it has to be written to the cent. `1,250.00` is money; `1250` is a unit
        // number, a quantity or a serial, and this must not guess which.
        guard let dot = text.lastIndex(of: ".") else { return false }
        let fraction = text[text.index(after: dot)...]
        return fraction.count == 2 && fraction.allSatisfy(\.isNumber)
    }
}
