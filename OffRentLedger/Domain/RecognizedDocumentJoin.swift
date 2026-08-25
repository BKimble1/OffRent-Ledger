import Foundation

extension RecognizedDocument {

    /// Reads as one document what was recognised as two.
    ///
    /// This exists because of "Add pages". A scan that began as an imported PDF holds no page
    /// images — the PDF is read straight out of its own text layer — so the only way to add a
    /// photograph of the page the PDF was missing and still have the PDF is to recognise both
    /// and join the results. Without this, adding a page to a PDF scan replaced it.
    ///
    /// The join is arithmetic, not interpretation: nothing is re-read, nothing is re-ordered and
    /// no line is dropped. `self` comes first because it is the document the user started from.
    func appending(_ other: RecognizedDocument) -> RecognizedDocument {
        guard !other.lines.isEmpty else { return self }
        guard !lines.isEmpty else { return other }

        let pagesHere = pageSpan
        let joinedPages = normalisedPages + other.normalisedPages.map { $0 + pagesHere }

        // Weighted by how much text each side contributed, rather than averaged flat. The parser
        // scales every rule's confidence by this figure, so a single-line photograph appended to
        // a six-page PDF must not halve the confidence of everything the PDF said — which is the
        // difference between a suggestion arriving ticked and arriving unticked.
        let lineTotal = Double(lines.count + other.lines.count)
        let weighted = averageRecognitionConfidence * Double(lines.count)
            + other.averageRecognitionConfidence * Double(other.lines.count)

        return RecognizedDocument(
            rawText: [rawText, other.rawText].filter { !$0.isEmpty }.joined(separator: "\n"),
            lines: lines + other.lines,
            linePages: joinedPages,
            averageRecognitionConfidence: lineTotal > 0 ? weighted / lineTotal : 0,
            pageCount: pagesHere + other.pageSpan,
            // The source of the document the user began with. A PDF that has had a photograph
            // added to it is still the PDF they imported, and the review screen says so.
            source: source
        )
    }

    /// How many pages this document actually accounts for.
    ///
    /// `pageCount` and `linePages` are set independently by the recogniser, and a fixture may
    /// carry lines on pages beyond the count it declares. Taking the larger of the two keeps the
    /// joined page numbers from colliding, which is what would put a line from the added
    /// photograph on the same page as a line from the PDF.
    private var pageSpan: Int {
        max(pageCount, (linePages.max() ?? -1) + 1)
    }

    /// `linePages` is allowed to be empty, in which case every line is on page 0.
    private var normalisedPages: [Int] {
        linePages.count == lines.count ? linePages : lines.map { _ in 0 }
    }
}
