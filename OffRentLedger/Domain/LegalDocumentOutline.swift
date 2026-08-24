import Foundation

/// Turns the bundled legal Markdown into something a screen can lay out.
///
/// The privacy policy and the terms are the two longest things in this app, and until now both
/// were rendered as one undifferentiated block of Markdown: bullet lines showed their hyphens,
/// numbered headings ran into the paragraphs under them, and there was no way to reach clause 9
/// except by scrolling past clauses 1 to 8. That is the shape of a document nobody reads, which
/// for a terms screen is not only an interface problem.
///
/// Parsing lives here, in the portable layer, rather than in the view, because it is the part
/// that can be wrong: a heading pattern that stops matching turns the whole document into one
/// untitled section, and that is worth a test rather than a glance.
public struct LegalDocumentOutline: Equatable, Sendable {

    /// A run of text inside a clause. Only the two shapes these documents actually use.
    public enum Block: Equatable, Sendable {
        case paragraph(String)
        case bullets([String])
    }

    public struct Clause: Equatable, Sendable, Identifiable {
        /// Position in the document. Stable for a given file, which is all a scroll target needs.
        public let id: Int
        /// "1", "9" — the number as written, or nil for an unnumbered heading.
        public let number: String?
        /// The heading with its number and trailing punctuation removed.
        public let title: String
        public let blocks: [Block]

        public init(id: Int, number: String?, title: String, blocks: [Block]) {
            self.id = id
            self.number = number
            self.title = title
            self.blocks = blocks
        }

        /// What the contents list shows: "1. Estimates", or just the title when unnumbered.
        public var listLabel: String {
            guard let number else { return title }
            return "\(number). \(title)"
        }
    }

    /// The `# ` line.
    public let title: String
    /// Everything between the title and the first `## `: the effective date, the version line.
    public let preamble: [String]
    public let clauses: [Clause]

    public init(title: String, preamble: [String], clauses: [Clause]) {
        self.title = title
        self.preamble = preamble
        self.clauses = clauses
    }

    /// True when the file was empty or unparseable — the caller shows its fallback instead of an
    /// authoritative-looking screen with nothing on it.
    public var isEmpty: Bool { clauses.isEmpty && preamble.isEmpty }

    // MARK: - Parsing

    public init(markdown: String) {
        var title = ""
        var preamble: [String] = []
        var clauses: [Clause] = []

        var pendingHeading: (number: String?, title: String)?
        var pendingLines: [String] = []

        func flush() {
            let blocks = Self.blocks(from: pendingLines)
            if let heading = pendingHeading {
                clauses.append(
                    Clause(
                        id: clauses.count,
                        number: heading.number,
                        title: heading.title,
                        blocks: blocks
                    )
                )
            } else {
                // Before the first `##`. Kept as flat lines: this is a date and a version, not
                // prose, and wrapping it in paragraph blocks would only invite a card around it.
                preamble = blocks.flatMap { block -> [String] in
                    switch block {
                    case .paragraph(let text): return [text]
                    case .bullets(let items): return items
                    }
                }
            }
            pendingLines = []
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("# ") && !line.hasPrefix("## ") {
                title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("## ") {
                flush()
                pendingHeading = Self.splitHeading(String(line.dropFirst(3)))
            } else {
                pendingLines.append(rawLine)
            }
        }
        flush()

        self.init(title: title, preamble: preamble, clauses: clauses)
    }

    /// "3. Estimates" → ("3", "Estimates"). "What this app is not — read this part" → (nil, …).
    static func splitHeading(_ heading: String) -> (number: String?, title: String) {
        let trimmed = heading.trimmingCharacters(in: .whitespaces)
        guard let dot = trimmed.firstIndex(of: ".") else { return (nil, trimmed) }
        let candidate = String(trimmed[trimmed.startIndex..<dot])
        guard !candidate.isEmpty, candidate.allSatisfy(\.isNumber) else { return (nil, trimmed) }
        let rest = trimmed[trimmed.index(after: dot)...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? (nil, trimmed) : (candidate, rest)
    }

    /// Groups raw lines into paragraphs and bullet runs.
    ///
    /// These files are hard-wrapped at roughly a hundred columns, so a paragraph arrives as
    /// several lines and has to be rejoined — printing them as written would put a line break in
    /// the middle of every sentence on a phone.
    static func blocks(from lines: [String]) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var bullets: [String] = []

        func flushParagraph() {
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph = []
        }
        func flushBullets() {
            if !bullets.isEmpty { blocks.append(.bullets(bullets)) }
            bullets = []
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                flushBullets()
            } else if let item = Self.bulletBody(line) {
                flushParagraph()
                bullets.append(item)
            } else if !bullets.isEmpty {
                // A continuation line under a bullet, from the same hard wrapping.
                bullets[bullets.count - 1] += " " + line
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        flushBullets()
        return blocks
    }

    /// The text of a `- ` or `* ` list item, with its trailing semicolon or full stop kept —
    /// these lists are legally enumerated clauses and the punctuation is part of the sentence.
    static func bulletBody(_ line: String) -> String? {
        for marker in ["- ", "* "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
