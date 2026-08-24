import Foundation
import XCTest
@testable import OffRentDomain

/// The legal documents, parsed.
///
/// These run against the files the app actually bundles rather than against a fixture, because
/// the failure worth catching is the one where somebody edits the policy and a heading stops
/// matching — a fixture would keep passing while the shipping screen turned into one untitled
/// wall of text.
final class LegalDocumentOutlineTests: XCTestCase {

    private func bundledMarkdown(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root
                .appendingPathComponent("OffRentLedger/Resources/Legal")
                .appendingPathComponent("\(name).md"),
            encoding: .utf8
        )
    }

    // MARK: - The shipping documents

    func testBothBundledDocumentsParseIntoTitledSections() throws {
        for name in ["TermsOfUse", "PrivacyPolicy"] {
            let outline = LegalDocumentOutline(markdown: try bundledMarkdown(name))
            XCTAssertFalse(outline.title.isEmpty, "\(name) has no title line")
            XCTAssertGreaterThanOrEqual(
                outline.clauses.count, 5,
                "\(name) parsed into \(outline.clauses.count) clauses, which means the heading "
                    + "pattern stopped matching"
            )
            for clause in outline.clauses {
                XCTAssertFalse(clause.title.isEmpty, "\(name) has an untitled clause")
                XCTAssertFalse(
                    clause.blocks.isEmpty,
                    "\(name) clause '\(clause.title)' has no content"
                )
            }
        }
    }

    func testClauseIdentifiersAreUniqueAndOrdered() throws {
        let outline = LegalDocumentOutline(markdown: try bundledMarkdown("TermsOfUse"))
        XCTAssertEqual(outline.clauses.map(\.id), Array(0..<outline.clauses.count))
    }

    func testNoRenderedLineStillCarriesItsMarkdownBullet() throws {
        for name in ["TermsOfUse", "PrivacyPolicy"] {
            let outline = LegalDocumentOutline(markdown: try bundledMarkdown(name))
            for clause in outline.clauses {
                for block in clause.blocks {
                    switch block {
                    case .paragraph(let text):
                        XCTAssertFalse(
                            text.hasPrefix("- ") || text.hasPrefix("* "),
                            "a bullet leaked into a paragraph in \(name): \(text)"
                        )
                    case .bullets(let items):
                        for item in items {
                            XCTAssertFalse(
                                item.hasPrefix("- ") || item.hasPrefix("* "),
                                "a bullet marker survived into the rendered item: \(item)"
                            )
                            XCTAssertFalse(item.isEmpty, "an empty bullet in \(name)")
                        }
                    }
                }
            }
        }
    }

    /// The clause that must never quietly disappear from the terms.
    func testTermsStillSayTheAppDoesNotContactRentalCompanies() throws {
        let outline = LegalDocumentOutline(markdown: try bundledMarkdown("TermsOfUse"))
        let everything = outline.clauses
            .flatMap(\.blocks)
            .flatMap { block -> [String] in
                switch block {
                case .paragraph(let text): return [text]
                case .bullets(let items): return items
                }
            }
            .joined(separator: " ")
            .lowercased()
        XCTAssertTrue(
            everything.contains("does not contact rental companies"),
            "the terms no longer carry the sentence the whole product is built around"
        )
    }

    // MARK: - Parsing rules

    func testNumberedHeadingsSplitIntoANumberAndATitle() {
        let outline = LegalDocumentOutline(
            markdown: """
                # Terms

                Effective date: today.

                ## 1. What this app is

                A record-keeping tool.

                ## 2. What this app is not

                Not an agent.
                """
        )
        XCTAssertEqual(outline.title, "Terms")
        XCTAssertEqual(outline.preamble, ["Effective date: today."])
        XCTAssertEqual(outline.clauses.map(\.number), ["1", "2"])
        XCTAssertEqual(outline.clauses.map(\.title), ["What this app is", "What this app is not"])
        XCTAssertEqual(outline.clauses[0].listLabel, "1. What this app is")
    }

    func testAnUnnumberedHeadingKeepsItsWholeTitle() {
        let (number, title) = LegalDocumentOutline.splitHeading("How we handle your data")
        XCTAssertNil(number)
        XCTAssertEqual(title, "How we handle your data")
    }

    /// A heading like "9.99 problems" is not clause 9 of a document — the split only applies
    /// when what follows the dot is real prose.
    func testADecimalHeadingIsNotTreatedAsAClauseNumber() {
        let (number, title) = LegalDocumentOutline.splitHeading("Version 2 released")
        XCTAssertNil(number)
        XCTAssertEqual(title, "Version 2 released")
    }

    func testHardWrappedProseIsRejoinedIntoOneParagraph() {
        let blocks = LegalDocumentOutline.blocks(from: [
            "OffRent Ledger is a record-keeping tool for equipment rentals. It helps you",
            "write down what you rented.",
            "",
            "- notify a vendor that you are finished;",
            "- terminate, suspend or modify a rental;",
        ])
        XCTAssertEqual(
            blocks,
            [
                .paragraph(
                    "OffRent Ledger is a record-keeping tool for equipment rentals. "
                        + "It helps you write down what you rented."
                ),
                .bullets([
                    "notify a vendor that you are finished;",
                    "terminate, suspend or modify a rental;",
                ]),
            ]
        )
    }

    func testAWrappedBulletStaysOneBullet() {
        let blocks = LegalDocumentOutline.blocks(from: [
            "- determine that any charge is incorrect, unauthorised or",
            "  unlawful;",
        ])
        XCTAssertEqual(
            blocks, [.bullets(["determine that any charge is incorrect, unauthorised or unlawful;"])]
        )
    }

    func testAnEmptyDocumentReportsItselfEmptyRatherThanRenderingAnEmptyScreen() {
        XCTAssertTrue(LegalDocumentOutline(markdown: "").isEmpty)
        XCTAssertTrue(LegalDocumentOutline(markdown: "   \n\n  ").isEmpty)
    }
}
