import Foundation
import PDFKit
import UIKit
import XCTest

@testable import OffRentLedger

/// The evidence packet, rendered.
///
/// There were no tests here at all, which is how the document shipped invisible. Every line of it
/// was drawn with `UIColor.label` — a *dynamic* colour, resolving against whatever interface
/// style was current when the renderer ran. On a phone set to dark that is white, onto a PDF page
/// that has no background of its own. The file was the right size, the text was extractable, and
/// a reader saw a blank sheet.
///
/// So these tests do not ask what the document *says*. `EvidencePacketBuilder` is pure and
/// covered elsewhere for that. These ask what it *looks like*, by rendering a page to a bitmap
/// and reading the pixels back, because that is the only question the old code got wrong.
final class EvidencePDFTests: XCTestCase {

    private let renderer = PDFEvidenceRenderer()

    // MARK: - The document is visible

    /// White paper, dark ink, on the page itself rather than on whatever it happens to be
    /// composited over.
    ///
    /// This is the whole bug, expressed as an assertion. Transparent paper fails it on alpha;
    /// white ink fails it on there being nothing dark anywhere.
    func testTheFirstPageIsWhitePaperWithDarkInkOnIt() async throws {
        let data = try await renderer.render(packet: packet(), imageLoader: { _ in nil })
        let pixels = try rasterise(data, page: 0)

        let corner = pixels.pixel(x: 6, y: 6)
        XCTAssertEqual(
            corner.alpha, 255,
            "the page is transparent — a viewer compositing it onto a dark surface sees nothing"
        )
        XCTAssertTrue(
            corner.red > 240 && corner.green > 240 && corner.blue > 240,
            "the paper is not white; it is rgb(\(corner.red), \(corner.green), \(corner.blue))"
        )

        XCTAssertGreaterThan(
            pixels.darkOpaqueCount, 500,
            """
            almost nothing dark was drawn on this page. Either the text is the same colour as \
            the paper, or it was never drawn at all — which is what a dynamic UIColor resolving \
            to white produces, and it looks identical to a blank document.
            """
        )
    }

    /// Every page, not only the first. A running header and footer are drawn on each one, so a
    /// page that lost its paper would still carry ink and pass a naive check.
    func testEveryPageIsWhitePaper() async throws {
        let data = try await renderer.render(
            packet: packet(userNotes: Self.longNote), imageLoader: { _ in nil }
        )
        let document = try XCTUnwrap(PDFDocument(data: data), "the renderer produced no PDF")
        XCTAssertGreaterThan(document.pageCount, 1, "the long note should have run onto a second page")

        for index in 0..<document.pageCount {
            let corner = try rasterise(data, page: index).pixel(x: 6, y: 6)
            XCTAssertEqual(corner.alpha, 255, "page \(index + 1) has no paper")
            XCTAssertTrue(
                corner.red > 240 && corner.green > 240 && corner.blue > 240,
                "page \(index + 1) is not white"
            )
        }
    }

    // MARK: - The document is complete

    /// A note longer than a page continues rather than being cut off at the foot.
    ///
    /// The old layout measured a block, asked for one page's worth of room, and drew it anyway.
    /// Anything taller than a page was clipped and the remainder was simply gone — no marker, no
    /// error, in a document whose entire purpose is to be complete.
    func testALongNoteIsNotClippedAtThePageFoot() async throws {
        let data = try await renderer.render(
            packet: packet(userNotes: Self.longNote), imageLoader: { _ in nil }
        )
        let document = try XCTUnwrap(PDFDocument(data: data))
        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")

        XCTAssertTrue(
            text.contains(Self.noteOpening),
            "the note's first sentence is missing entirely"
        )
        XCTAssertTrue(
            text.contains(Self.noteClosing),
            """
            the note's last sentence never made it into the document. It was drawn past the \
            bottom of a page and clipped, which is exactly the silent loss this checks for.
            """
        )
    }

    /// The disclaimer survives too. It is the paragraph that stops the document overclaiming, so
    /// losing its tail to a page break is the worst possible thing to lose.
    func testTheDisclaimerIsPresentInFull() async throws {
        let subject = packet()
        let data = try await renderer.render(packet: subject, imageLoader: { _ in nil })
        let document = try XCTUnwrap(PDFDocument(data: data))
        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n", with: " ")

        // Compared word by word rather than as one string: PDFKit reflows line breaks, so an
        // equality check would fail on whitespace while the document was perfectly correct.
        let expected = subject.disclaimer.split(whereSeparator: \.isWhitespace).map(String.init)
        let missing = expected.filter { !text.contains($0) }
        XCTAssertTrue(
            missing.isEmpty,
            "the disclaimer is missing \(missing.count) of its \(expected.count) words: \(missing.prefix(8))"
        )
    }

    /// The footer numbers every page and says how many there are, so a reader holding a loose
    /// sheet knows whether they have the whole thing.
    func testEveryPageIsNumberedAndSaysHowManyThereAre() async throws {
        let data = try await renderer.render(
            packet: packet(userNotes: Self.longNote), imageLoader: { _ in nil }
        )
        let document = try XCTUnwrap(PDFDocument(data: data))
        let total = document.pageCount
        XCTAssertGreaterThan(total, 1)

        for index in 0..<total {
            let page = try XCTUnwrap(document.page(at: index))
            let text = (page.string ?? "").replacingOccurrences(of: "\n", with: " ")
            XCTAssertTrue(
                text.contains("Page \(index + 1) of \(total)"),
                "page \(index + 1) does not carry \"Page \(index + 1) of \(total)\""
            )
        }
    }

    // MARK: - Rasterising

    private struct Bitmap {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        struct Pixel {
            let red: Int
            let green: Int
            let blue: Int
            let alpha: Int
        }

        func pixel(x: Int, y: Int) -> Pixel {
            let offset = (y * width + x) * 4
            return Pixel(
                red: Int(bytes[offset]), green: Int(bytes[offset + 1]),
                blue: Int(bytes[offset + 2]), alpha: Int(bytes[offset + 3])
            )
        }

        /// Pixels that are both opaque and dark — ink, in other words.
        var darkOpaqueCount: Int {
            var count = 0
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                let alpha = Int(bytes[offset + 3])
                guard alpha > 200 else { continue }
                let luminance = Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])
                if luminance < 384 { count += 1 }
            }
            return count
        }
    }

    /// Draws a page into a buffer that starts fully transparent.
    ///
    /// Starting transparent is the point: anything opaque in the result was put there by the
    /// page. A renderer that fills its own white background passes; one that relies on the
    /// viewer to supply a light surface does not.
    private func rasterise(_ data: Data, page index: Int) throws -> Bitmap {
        let document = try XCTUnwrap(PDFDocument(data: data), "the renderer produced no PDF")
        let page = try XCTUnwrap(document.page(at: index), "there is no page \(index + 1)")
        let bounds = page.bounds(for: .mediaBox)
        let width = Int(bounds.width)
        let height = Int(bounds.height)

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &bytes, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        page.draw(with: .mediaBox, to: context)
        return Bitmap(width: width, height: height, bytes: bytes)
    }

    // MARK: - Fixture

    private static let noteOpening = "The yard was called on the eleventh and did not answer."
    private static let noteClosing = "That is the last line of this note and it must survive."

    /// Comfortably more than one page of prose, so the flow across pages is genuinely exercised
    /// rather than assumed.
    private static let longNote: String = {
        let middle = (1...90).map {
            "Paragraph \($0) of the operator's account of what happened on site, written out at "
                + "enough length that the whole note cannot possibly fit on a single page."
        }
        return ([noteOpening] + middle + [noteClosing]).joined(separator: "\n\n")
    }()

    private func packet(userNotes: String? = nil) -> EvidencePacket {
        let start = Date(timeIntervalSince1970: 1_777_000_000)
        let terms = RentalTerms(
            deliveryDate: start,
            rateCard: RateCard(daily: Decimal(285)),
            billingBasis: .daily
        )
        return EvidencePacket(
            generatedAt: start.addingTimeInterval(86_400 * 16),
            appDisplayName: "OffRent Ledger",
            appVersion: "1.0 (1)",
            companyName: "Idlery Services LLC",
            vendor: .init(
                name: "Cedar Ridge Equipment Rental", branch: "Marlin Falls",
                phone: "(940) 555-0148", email: nil, link: nil
            ),
            jobSite: .init(name: "Ridgeline Phase 2", projectIdentifier: "RL-2", address: nil),
            agreementNumber: "CR-44821",
            agreementStartDate: start,
            agreementScheduledEndDate: start.addingTimeInterval(86_400 * 14),
            equipmentName: "Skid Steer Loader",
            equipmentClass: "75HP",
            vendorEquipmentIdentifier: "SS-2214",
            serialNumber: "A9KT4417732",
            status: .invoiceReview,
            terms: terms,
            estimate: RentalRateEngine.estimate(
                terms: terms, asOf: start.addingTimeInterval(86_400 * 7),
                calendar: Calendar(identifier: .gregorian)
            ),
            timeline: [
                .init(
                    timestamp: start.addingTimeInterval(86_400 * 7), title: "Contact attempt recorded",
                    detail: "No answer at the yard", contactMethod: .phone,
                    vendorRepresentative: nil, confirmationNumber: nil, hasLocation: false
                )
            ],
            confirmation: nil,
            pickup: nil,
            meterUnit: .hours,
            selectedAssets: [],
            invoice: nil,
            comparison: nil,
            userNotes: userNotes,
            disclaimer: EvidencePacketBuilder.disclaimer(
                appName: "OffRent Ledger", companyName: "Idlery Services LLC"
            )
        )
    }
}
