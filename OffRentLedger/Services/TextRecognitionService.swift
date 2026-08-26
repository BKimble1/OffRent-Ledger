import Foundation
import OSLog
import PDFKit
import UIKit
import Vision

/// Turns an image or a PDF into recognised text. On device, always.
///
/// Takes encoded image `Data`, not `UIImage`. `UIImage` is not `Sendable`, and the implementation
/// is an actor — so handing it one is a non-Sendable value crossing an isolation boundary, which
/// the compiler rejects. `Data` is `Sendable`, it is the form the bytes already arrive in from
/// PhotosPicker and from disk, and it avoids carrying a decoded bitmap around: a 12MP frame is
/// ~4 MB encoded and ~48 MB decoded, so the encoded form is the cheaper thing to move.
protocol DocumentTextRecognizing: Sendable {
    func recognize(imageData: [Data], source: DocumentSource) async throws -> RecognizedDocument
    func recognize(pdf data: Data) async throws -> RecognizedDocument
}

enum TextRecognitionError: Error, Equatable {
    case noPages
    case couldNotRenderPDF
    case recognitionFailed(String)
    case cancelled
}

/// Vision's on-device text recogniser.
///
/// Nothing here reaches the network. `usesLanguageCorrection` and `.accurate` both run locally,
/// and `VNRecognizeTextRequest` has no server mode to accidentally enable. That is the whole
/// reason Vision was chosen over any hosted OCR: the privacy claim is a property of the framework
/// rather than a promise about configuration.
///
/// It is an actor so that a scan started from the review sheet cannot overlap with one started
/// from an invoice import, and so cancellation is well defined.
actor VisionTextRecognizer: DocumentTextRecognizing {

    private static let logger = Logger(subsystem: "com.idlery.offrent", category: "ocr")

    /// Longest edge Vision is given. Recognition accuracy stops improving well before a 12MP
    /// frame, and the memory does not.
    private let maxDimension: CGFloat = 2_400

    func recognize(imageData: [Data], source: DocumentSource) async throws -> RecognizedDocument {
        guard !imageData.isEmpty else { throw TextRecognitionError.noPages }

        var lines: [String] = []
        var linePages: [Int] = []
        var confidences: [Double] = []

        for (index, data) in imageData.enumerated() {
            try Task.checkCancellation()
            // Decoded here, inside the actor. The bitmap is created and consumed within this
            // isolation domain and never crosses a boundary.
            guard let image = UIImage(data: data) else {
                throw TextRecognitionError.recognitionFailed("unreadable image data")
            }
            let page = try recognizeOne(image.downscaled(toMaxDimension: maxDimension))
            lines.append(contentsOf: page.lines)
            linePages.append(contentsOf: page.lines.map { _ in index })
            confidences.append(contentsOf: page.confidences)
        }

        return makeDocument(
            lines: lines,
            linePages: linePages,
            confidences: confidences,
            pageCount: imageData.count,
            source: source
        )
    }

    func recognize(pdf data: Data) async throws -> RecognizedDocument {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw TextRecognitionError.couldNotRenderPDF
        }

        var lines: [String] = []
        var linePages: [Int] = []
        var confidences: [Double] = []

        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }

            // A PDF exported from a vendor's billing system usually carries a real text layer.
            // Using it is both more accurate than rasterising and recognising, and far cheaper.
            if let embedded = page.string, embedded.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 {
                let pageLines = embedded
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                lines.append(contentsOf: pageLines)
                linePages.append(contentsOf: pageLines.map { _ in index })
                // An embedded text layer is exact, not recognised.
                confidences.append(contentsOf: pageLines.map { _ in 1.0 })
                continue
            }

            guard let image = render(page: page) else { continue }
            let recognized = try recognizeOne(image)
            lines.append(contentsOf: recognized.lines)
            linePages.append(contentsOf: recognized.lines.map { _ in index })
            confidences.append(contentsOf: recognized.confidences)
        }

        guard !lines.isEmpty else { throw TextRecognitionError.couldNotRenderPDF }
        return makeDocument(
            lines: lines,
            linePages: linePages,
            confidences: confidences,
            pageCount: document.pageCount,
            source: .pdfImport
        )
    }

    // MARK: - Private

    private func makeDocument(
        lines: [String],
        linePages: [Int],
        confidences: [Double],
        pageCount: Int,
        source: DocumentSource
    ) -> RecognizedDocument {
        let average = confidences.isEmpty
            ? 0
            : confidences.reduce(0, +) / Double(confidences.count)
        return RecognizedDocument(
            rawText: lines.joined(separator: "\n"),
            lines: lines,
            linePages: linePages,
            averageRecognitionConfidence: average,
            pageCount: pageCount,
            source: source
        )
    }

    private func render(page: PDFPage) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        // Rendered at roughly 200 dpi equivalent, capped, which is where recognition of 8pt
        // invoice type becomes reliable without producing a 60 MB bitmap. A page smaller than the
        // cap is scaled *up* rather than left at its native size: a 612×792 point invoice
        // rendered 1:1 gives Vision 8pt type at 8 pixels tall, which it cannot read.
        let scale = min(maxDimension / max(bounds.width, bounds.height), 4)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }

    private func recognizeOne(_ image: UIImage) throws -> (lines: [String], confidences: [Double]) {
        guard let cgImage = image.cgImage else {
            throw TextRecognitionError.recognitionFailed("no bitmap")
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // US English only in v1; adding languages here without testing them would produce
        // confident nonsense on documents the app has never seen.
        request.recognitionLanguages = ["en-US"]
        request.customWords = Self.customWords
        // Rental paperwork is full of short lines — a unit number on its own, a rate in a table
        // cell. The default minimum height discards text under 1/32 of the frame, which on a
        // 2400px scan is 75px: taller than most invoice type. Lowering it is the difference
        // between reading a rate table and reading only the letterhead.
        request.minimumTextHeight = 0.008

        // The orientation, passed rather than assumed.
        //
        // `UIImage.cgImage` is the raw sensor bitmap: a photo taken in portrait carries
        // `.right` and its `cgImage` is on its side. `downscaled` happens to normalise that,
        // but only when the image is larger than the cap — so a small photo, or a screenshot,
        // reached Vision sideways and came back as nothing at all. Nothing said why.
        let handler = VNImageRequestHandler(
            cgImage: cgImage, orientation: Self.cgOrientation(image.imageOrientation), options: [:]
        )
        do {
            try handler.perform([request])
        } catch {
            Self.logger.error("Vision failed: \(String(describing: error), privacy: .private)")
            throw TextRecognitionError.recognitionFailed(String(describing: error))
        }

        let observations = request.results ?? []
        var lines: [String] = []
        var confidences: [Double] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            lines.append(text)
            confidences.append(Double(candidate.confidence))
        }
        return (lines, confidences)
    }

    /// Words language correction would otherwise "fix" into something else.
    ///
    /// Rental paperwork is full of `SS-2214`, `CR-44821` and `28 DAY RATE`, and a corrector that
    /// has never seen a rental agreement turns half of those into English. Everything here is a
    /// term that appears on real construction rental documents; nothing here is a value.
    private static let customWords = [
        "off-rent", "offrent", "off rent", "skid", "skidsteer", "hrs", "PO", "Qty",
        "excavator", "telehandler", "manlift", "scissorlift", "compactor", "genset",
        "attachment", "bucket", "auger", "breaker", "hammer", "trencher",
        "RPO", "DOT", "CDW", "LDW", "enviro", "surcharge", "prorate", "prorated",
        "rehandling", "restocking", "refueling", "cycle billing", "min charge",
        "day rate", "week rate", "4 week rate", "28 day", "monthly rate",
        "billed thru", "billed through", "contract no", "agreement no", "unit no",
    ]

    /// UIKit's orientation to Core Graphics', which is what Vision takes.
    private static func cgOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}

/// Returns fixture text. Used by previews and by the UI test suite, so that a test of the review
/// sheet is a test of the review sheet rather than of the camera.
struct StubTextRecognizer: DocumentTextRecognizing {
    var document: RecognizedDocument

    init(document: RecognizedDocument) { self.document = document }

    init(rawText: String, confidence: Double = 0.95, source: DocumentSource = .documentCamera) {
        self.document = RecognizedDocument(
            rawText: rawText, averageRecognitionConfidence: confidence, source: source
        )
    }

    func recognize(imageData: [Data], source: DocumentSource) async throws -> RecognizedDocument {
        document
    }

    func recognize(pdf data: Data) async throws -> RecognizedDocument { document }

    /// The fixture the UI test suite scans. Kept in sync with
    /// `OffRentLedger/Resources/OCRFixtures/contract_skidsteer_clean.txt` by
    /// `OffRentLedgerTests/FixtureParityTests`.
    static let skidSteerContract = StubTextRecognizer(
        rawText: """
            CEDAR RIDGE EQUIPMENT RENTAL LLC
            4820 Foundry Road, Bay 3
            Marlin Falls, TX 76541
            (940) 555-0148

            RENTAL AGREEMENT NO: CR-44821

            EQUIPMENT: Skid Steer Loader 75HP Closed Cab
            UNIT #: SS-2214
            SERIAL NUMBER: A9KT4417732

            DATE OUT: 05/04/2026
            ESTIMATED RETURN: 05/18/2026

            DAILY RATE: $285.00
            7 DAY RATE: $985.00
            4 WEEK RATE: $2,450.00
            """
    )

    /// The contract the App Store capture scans.
    ///
    /// Kept in sync with `OffRentLedger/Resources/OCRFixtures/contract_appstore_excavator.txt` by
    /// `OffRentLedgerTests/FixtureParityTests`, exactly as the skid-steer one is.
    ///
    /// It is the *same machine* as `AppStoreCaptureFixture.miniExcavator` — Summit Rental Co.,
    /// EX-118, $425.00 a day, out on 5 May. The whole point of a six-frame gallery is that it is
    /// six frames of one product, and a scan review quoting a different yard and a different rate
    /// from the dashboard two frames earlier undoes that in the one place a reader is looking
    /// closely at the numbers.
    ///
    /// The layout is deliberately identical to the skid-steer fixture's, label for label. That
    /// file is the one every parser test is written against, so a copy of it with different
    /// values exercises the same rules and cannot quietly depend on a parsing path nothing else
    /// covers.
    static let appStoreExcavatorContract = StubTextRecognizer(
        rawText: """
            SUMMIT RENTAL CO.
            1180 Bexley Yard Road
            Fairhaven, TX 76109
            (972) 555-0142

            RENTAL AGREEMENT NO: SR-58204

            CUSTOMER: Halloway Sitework
            JOB / PO: PO-4471

            EQUIPMENT: Mini Excavator 6000 LB Rubber Track
            UNIT #: EX-118
            SERIAL NUMBER: 5KX2290741

            DATE OUT: 05/05/2026
            ESTIMATED RETURN: 05/19/2026

            DAILY RATE: $425.00
            7 DAY RATE: $1,450.00
            4 WEEK RATE: $3,600.00

            INCLUDED HOURS: 8 hrs/day, 40 hrs/week. Excess hours billed at 1/8 of day rate.
            DELIVERY AND PICKUP QUOTED SEPARATELY.

            Renter is responsible for fuel, daily walkaround, and reporting damage.
            """
    )

    /// A document with nothing about an equipment rental on it.
    ///
    /// The negative test: OCR reads it perfectly, and the extractor must find nothing, because
    /// nothing on it is a rate, a machine or a rental date. This is the document in the
    /// screenshot that produced a `Use 0 values` button.
    static let residentialLease = StubTextRecognizer(
        rawText: """
            RESIDENTIAL LEASE AGREEMENT

            THIS LEASE is made this 14th day of March, 2026, between
            HARLAN PROPERTIES, Landlord, and the Tenant named below.

            PREMISES: Apartment 4B, 118 Sycamore Street

            TERM: Twelve (12) months commencing April 1, 2026.

            SECURITY DEPOSIT: The Tenant shall deposit the sum of one
            month's rent to be held in accordance with state law.

            QUIET ENJOYMENT: The Landlord covenants that the Tenant
            shall peaceably hold and enjoy the Premises.

            PETS: No animals shall be kept on the Premises without the
            prior written consent of the Landlord.
            """
    )
}
