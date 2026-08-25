import Foundation
import XCTest
@testable import OffRentDomain

/// Joining two recognitions into one document.
///
/// This is what "Add pages" stands on. A scan that began as an imported PDF holds no page
/// images, so adding a photograph to it means recognising both and joining the results — and if
/// the join loses a line, or renumbers a page, the user is looking at a review screen that does
/// not describe the document in their hand.
final class RecognizedDocumentJoinTests: XCTestCase {

    private func document(
        _ lines: [String],
        pages: [Int]? = nil,
        pageCount: Int = 1,
        confidence: Double = 1.0,
        source: DocumentSource = .pdfImport
    ) -> RecognizedDocument {
        RecognizedDocument(
            rawText: lines.joined(separator: "\n"),
            lines: lines,
            linePages: pages ?? lines.map { _ in 0 },
            averageRecognitionConfidence: confidence,
            pageCount: pageCount,
            source: source
        )
    }

    func testEveryLineFromBothSidesSurvives() {
        let first = document(["INVOICE 88213", "RENTAL 1,250.00"])
        let second = document(["FUEL 87.50"], source: .photoLibrary)

        let joined = first.appending(second)

        XCTAssertEqual(joined.lines, ["INVOICE 88213", "RENTAL 1,250.00", "FUEL 87.50"])
        XCTAssertEqual(joined.linePages.count, joined.lines.count)
    }

    func testTheAddedPagesAreNumberedAfterTheOnesAlreadyThere() {
        let pdf = document(["PAGE ONE", "PAGE TWO"], pages: [0, 1], pageCount: 2)
        let photo = document(["ADDED"], source: .photoLibrary)

        let joined = pdf.appending(photo)

        XCTAssertEqual(joined.linePages, [0, 1, 2])
        XCTAssertEqual(joined.pageCount, 3)
        XCTAssertEqual(joined.page(ofLineAt: 2), 2)
    }

    func testAPageBeyondTheDeclaredCountStillDoesNotCollide() {
        // The recogniser sets `pageCount` and `linePages` independently. Trusting `pageCount`
        // alone would put the added photograph on the same page as an existing line.
        let ragged = document(["A", "B"], pages: [0, 3], pageCount: 1)
        let added = document(["C"], source: .photoLibrary)

        XCTAssertEqual(ragged.appending(added).linePages, [0, 3, 4])
    }

    func testAnEmptyLinePagesArrayIsTreatedAsOnePage() {
        let noPages = document(["ONLY LINE"], pages: [])
        let added = document(["ADDED"], source: .photoLibrary)

        XCTAssertEqual(noPages.appending(added).linePages, [0, 1])
    }

    func testConfidenceIsWeightedByHowMuchTextEachSideContributed() {
        // Six confident lines plus one poor one must stay confident. A flat average would put
        // this at 0.60 and untick every suggestion the PDF produced.
        let pdf = document(Array(repeating: "LINE", count: 6), confidence: 1.0)
        let photo = document(["BLURRED"], confidence: 0.2, source: .photoLibrary)

        let joined = pdf.appending(photo)

        XCTAssertEqual(joined.averageRecognitionConfidence, (6.0 + 0.2) / 7.0, accuracy: 0.0001)
    }

    func testJoiningWithAnEmptyRecognitionChangesNothing() {
        let pdf = document(["INVOICE 88213"], pageCount: 2)
        let nothing = document([], source: .photoLibrary)

        XCTAssertEqual(pdf.appending(nothing), pdf)
        XCTAssertEqual(nothing.appending(pdf), pdf)
    }

    func testTheDocumentKeepsTheSourceItStartedFrom() {
        let pdf = document(["INVOICE"], source: .pdfImport)
        let photo = document(["ADDED"], source: .photoLibrary)

        XCTAssertEqual(pdf.appending(photo).source, .pdfImport)
    }

    func testTheRawTextCarriesBothSides() {
        let first = document(["ONE"])
        let second = document(["TWO"], source: .photoLibrary)

        XCTAssertEqual(first.appending(second).rawText, "ONE\nTWO")
    }
}
