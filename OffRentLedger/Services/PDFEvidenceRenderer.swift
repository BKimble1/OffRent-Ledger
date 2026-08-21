import Foundation
import OSLog
import PDFKit
import UIKit

protocol EvidenceRendering: Sendable {
    /// - Parameter imageLoader: resolves an asset's relative path to bytes. Injected so the
    ///   renderer never touches the file system directly and can be exercised with fixtures.
    func render(
        packet: EvidencePacket,
        imageLoader: @Sendable (String) async -> Data?
    ) async throws -> Data
}

enum EvidenceRenderError: Error, Equatable {
    case renderFailed
}

/// Draws the evidence packet.
///
/// Layout only. Everything the document *says* is decided in `EvidencePacketBuilder`, which is
/// pure and tested; this file decides where it goes on the page. That split is why the disclaimer
/// wording is covered by tests on a machine with no PDFKit.
struct PDFEvidenceRenderer: EvidenceRendering {

    private static let logger = Logger(subsystem: "com.idlery.offrent", category: "pdf")

    // US Letter at 72 dpi.
    private let pageSize = CGSize(width: 612, height: 792)
    private let margin: CGFloat = 48

    func render(
        packet: EvidencePacket,
        imageLoader: @Sendable (String) async -> Data?
    ) async throws -> Data {

        // Images are loaded up front, off the drawing path: the renderer block is synchronous
        // and cannot await, and reading a dozen JPEGs inside it would block the caller anyway.
        var images: [String: UIImage] = [:]
        for asset in packet.selectedAssets where asset.mediaType == .image {
            if let data = await imageLoader(asset.relativePath), let image = UIImage(data: data) {
                images[asset.relativePath] = image.downscaled(toMaxDimension: 1_100)
            }
        }

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: pageSize),
            format: metadata(for: packet)
        )

        let data = renderer.pdfData { context in
            var layout = PageLayout(context: context, pageSize: pageSize, margin: margin)
            layout.beginPage()

            draw(header: packet, into: &layout)
            draw(parties: packet, into: &layout)
            draw(equipment: packet, into: &layout)
            draw(terms: packet, into: &layout)
            draw(timeline: packet, into: &layout)
            draw(confirmation: packet, into: &layout)
            draw(pickup: packet, into: &layout)
            draw(invoice: packet, into: &layout)
            draw(assets: packet, images: images, into: &layout)
            draw(notes: packet, into: &layout)
            draw(disclaimer: packet, into: &layout)
        }

        guard !data.isEmpty else { throw EvidenceRenderError.renderFailed }
        return data
    }

    private func metadata(for packet: EvidencePacket) -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: EvidencePacketBuilder.headline(for: packet),
            kCGPDFContextCreator as String: "\(packet.appDisplayName) \(packet.appVersion)",
            kCGPDFContextAuthor as String: packet.companyName,
            // Deliberately not "Evidence" or "Proof". The document's own disclaimer says what it
            // is; its metadata must not overclaim in a preview pane.
            kCGPDFContextSubject as String: "Rental record assembled from user-entered information",
        ]
        return format
    }

    // MARK: - Sections

    private func draw(header packet: EvidencePacket, into layout: inout PageLayout) {
        layout.title("Rental record")
        layout.subtitle(EvidencePacketBuilder.headline(for: packet))
        layout.caption(
            "Assembled by \(packet.appDisplayName) \(packet.appVersion) on "
                + Formatters.dateAndTime(packet.generatedAt)
        )
        layout.rule()
    }

    private func draw(parties packet: EvidencePacket, into layout: inout PageLayout) {
        layout.heading("Rental company")
        layout.field("Name", packet.vendor.name)
        if let branch = packet.vendor.branch { layout.field("Branch", branch) }
        if let phone = packet.vendor.phone { layout.field("Phone", phone) }
        if let email = packet.vendor.email { layout.field("Email", email) }

        if let site = packet.jobSite {
            layout.heading("Jobsite")
            layout.field("Name", site.name)
            if let project = site.projectIdentifier { layout.field("Project", project) }
            if let address = site.address { layout.field("Address", address) }
        }

        layout.heading("Agreement")
        layout.field("Agreement number", packet.agreementNumber ?? "Not recorded")
        layout.field("Start date", Formatters.mediumDate(packet.agreementStartDate))
        if let end = packet.agreementScheduledEndDate {
            layout.field("Scheduled end", Formatters.mediumDate(end))
        }
    }

    private func draw(equipment packet: EvidencePacket, into layout: inout PageLayout) {
        layout.heading("Equipment")
        layout.field("Description", packet.equipmentName)
        if let equipmentClass = packet.equipmentClass { layout.field("Class", equipmentClass) }
        if let identifier = packet.vendorEquipmentIdentifier {
            layout.field("Vendor equipment ID", identifier)
        }
        if let serial = packet.serialNumber { layout.field("Serial number", serial) }
        layout.field("Status", packet.status.displayName)
    }

    private func draw(terms packet: EvidencePacket, into layout: inout PageLayout) {
        layout.heading("Rates you confirmed")
        let card = packet.terms.rateCard
        layout.field("Daily", card.daily.map(Formatters.currency) ?? "Not confirmed")
        layout.field("Weekly", card.weekly.map(Formatters.currency) ?? "Not confirmed")
        layout.field("4-week", card.fourWeek.map(Formatters.currency) ?? "Not confirmed")
        layout.field("Billing basis", packet.terms.billingBasis.displayName)
        layout.field("Delivered", Formatters.mediumDate(packet.terms.deliveryDate))

        layout.heading("Estimated rent")
        if packet.estimate.isComplete {
            layout.field(
                "Estimate",
                "\(Formatters.currency(packet.estimate.estimatedTotal)) (estimate)"
            )
            layout.field(
                "How it was reached",
                "\(packet.estimate.periodsStarted) × \(Formatters.currency(packet.estimate.amountPerPeriod)) "
                    + "per \(packet.terms.billingBasis.shortName), \(Formatters.dayCount(packet.estimate.daysOnRent)) on rent."
            )
        } else {
            layout.field(
                "Estimate",
                "Not available — " + (packet.estimate.blockingIssue?.message ?? "rates are incomplete.")
            )
        }
        layout.note(AppCopy.estimateExplanation)

        if let usage = packet.terms.includedUsageNotes, !usage.isEmpty {
            layout.field("Included usage (recorded, not calculated)", usage)
        }
    }

    private func draw(timeline packet: EvidencePacket, into layout: inout PageLayout) {
        guard !packet.timeline.isEmpty else { return }
        layout.heading("Timeline")
        for entry in packet.timeline.sorted(by: { $0.timestamp < $1.timestamp }) {
            var line = "\(Formatters.dateAndTime(entry.timestamp)) — \(entry.title)"
            if let method = entry.contactMethod { line += " (\(method.displayName))" }
            if let representative = entry.vendorRepresentative { line += ", spoke to \(representative)" }
            if let number = entry.confirmationNumber { line += ", confirmation \(number)" }
            layout.bullet(line)
            if let detail = entry.detail, !detail.isEmpty { layout.indentedNote(detail) }
        }
    }

    private func draw(confirmation packet: EvidencePacket, into layout: inout PageLayout) {
        layout.heading("Off-rent confirmation")
        guard let confirmation = packet.confirmation else {
            layout.note("No vendor confirmation was recorded for this item.")
            return
        }
        layout.field(
            "Confirmation number",
            confirmation.trimmedConfirmationNumber
                ?? (confirmation.acknowledgedNoConfirmationNumber
                    ? "User recorded that the vendor gave no number"
                    : "Not recorded")
        )
        layout.field("Recorded as confirmed at", Formatters.dateAndTime(confirmation.confirmedAt))
        layout.field("Contact method", confirmation.contactMethod.displayName)
        if let representative = confirmation.vendorRepresentative {
            layout.field("Vendor representative", representative)
        }
        if let meter = confirmation.meterReading {
            layout.field("Meter at off-rent", Formatters.meterReading(meter, unit: packet.meterUnit))
        }
        if let fuel = confirmation.fuelLevel { layout.field("Fuel at off-rent", fuel.displayName) }
        if let notes = confirmation.notes, !notes.isEmpty { layout.field("Notes", notes) }
        layout.note(
            "The user recorded that they contacted the rental company. "
                + "\(packet.appDisplayName) did not contact anyone."
        )
    }

    private func draw(pickup packet: EvidencePacket, into layout: inout PageLayout) {
        layout.heading("Pickup")
        guard let pickup = packet.pickup else {
            layout.note("No pickup was recorded for this item.")
            return
        }
        layout.field("Picked up", Formatters.dateAndTime(pickup.pickedUpAt))
        if let observer = pickup.observedBy { layout.field("Observed by", observer) }
        if let meter = pickup.finalMeterReading {
            layout.field("Final meter", Formatters.meterReading(meter, unit: packet.meterUnit))
        }
        if let fuel = pickup.finalFuelLevel { layout.field("Final fuel", fuel.displayName) }
        if let notes = pickup.notes, !notes.isEmpty { layout.field("Notes", notes) }
    }

    private func draw(invoice packet: EvidencePacket, into layout: inout PageLayout) {
        guard let invoice = packet.invoice else { return }
        layout.heading("Final invoice")
        layout.field("Invoice number", invoice.invoiceNumber ?? "Not recorded")
        layout.field("Received", Formatters.mediumDate(invoice.receivedDate))
        if let through = invoice.billedThroughDate {
            layout.field("Billed through", Formatters.mediumDate(through))
        }
        for line in invoice.lines {
            var text = "\(line.category.displayName): \(Formatters.currency(line.amount))"
            if !line.detail.isEmpty { text += " — \(line.detail)" }
            if line.reviewState != .unreviewed { text += " [\(line.reviewState.displayName)]" }
            layout.bullet(text)
        }
        layout.field("Invoice total", Formatters.currency(invoice.invoiceTotal))

        guard let comparison = packet.comparison else { return }
        layout.heading("Comparison against the terms you confirmed")
        layout.field(
            "Expected rental amount",
            comparison.expectedRentalSubtotal.map(Formatters.currency) ?? "Could not be formed"
        )
        layout.field("How it was reached", comparison.expectationBasis)
        layout.field("Invoiced rental amount", Formatters.currency(comparison.invoicedRentalSubtotal))
        layout.field("Possible variance", "\(Formatters.currency(comparison.possibleVariance)) (estimate)")

        if comparison.findings.isEmpty {
            layout.note("No possible mismatch was found against the terms recorded here.")
        } else {
            for finding in comparison.findings {
                layout.bullet("\(finding.type.displayName) — \(finding.status.displayName)")
                layout.indentedNote(finding.explanation)
            }
            layout.note(AppCopy.possibleMismatchExplanation)
        }
    }

    private func draw(
        assets packet: EvidencePacket, images: [String: UIImage], into layout: inout PageLayout
    ) {
        guard !packet.selectedAssets.isEmpty else { return }
        layout.heading("Attachments")
        for asset in packet.selectedAssets {
            layout.bullet(
                "\(asset.displayName) — \(asset.mediaType.displayName), captured "
                    + Formatters.dateAndTime(asset.capturedAt)
            )
            if let caption = asset.caption, !caption.isEmpty { layout.indentedNote(caption) }
            if let digest = asset.sha256 {
                layout.indentedNote("SHA-256 \(digest)")
            }
            if let image = images[asset.relativePath] { layout.image(image) }
        }
        layout.note(AppCopy.checksumExplanation)
    }

    private func draw(notes packet: EvidencePacket, into layout: inout PageLayout) {
        guard let notes = packet.userNotes, !notes.isEmpty else { return }
        layout.heading("Your notes")
        layout.paragraph(notes)
    }

    private func draw(disclaimer packet: EvidencePacket, into layout: inout PageLayout) {
        layout.pageBreak()
        layout.heading("About this document")
        layout.paragraph(packet.disclaimer)
    }
}

/// Cursor-based page layout. Advances down the page and starts a new one before it overflows.
private struct PageLayout {
    let context: UIGraphicsPDFRendererContext
    let pageSize: CGSize
    let margin: CGFloat
    var y: CGFloat = 0

    private var contentWidth: CGFloat { pageSize.width - margin * 2 }
    private var bottom: CGFloat { pageSize.height - margin }

    mutating func beginPage() {
        context.beginPage()
        y = margin
    }

    mutating func pageBreak() { beginPage() }

    private mutating func ensure(_ height: CGFloat) {
        if y + height > bottom { beginPage() }
    }

    private mutating func draw(_ text: String, font: UIFont, colour: UIColor, indent: CGFloat = 0) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
        let width = contentWidth - indent
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        ensure(bounding.height + 4)
        (text as NSString).draw(
            with: CGRect(x: margin + indent, y: y, width: width, height: bounding.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        y += bounding.height + 4
    }

    mutating func title(_ text: String) {
        draw(text, font: .systemFont(ofSize: 22, weight: .bold), colour: .label)
    }

    mutating func subtitle(_ text: String) {
        draw(text, font: .systemFont(ofSize: 13, weight: .semibold), colour: .label)
    }

    mutating func caption(_ text: String) {
        draw(text, font: .systemFont(ofSize: 9), colour: .secondaryLabel)
    }

    mutating func heading(_ text: String) {
        y += 10
        draw(text.uppercased(), font: .systemFont(ofSize: 10, weight: .bold), colour: .secondaryLabel)
    }

    mutating func field(_ label: String, _ value: String) {
        draw("\(label): \(value)", font: .systemFont(ofSize: 11), colour: .label)
    }

    mutating func bullet(_ text: String) {
        draw("•  \(text)", font: .systemFont(ofSize: 11), colour: .label)
    }

    mutating func indentedNote(_ text: String) {
        draw(text, font: .systemFont(ofSize: 9), colour: .secondaryLabel, indent: 16)
    }

    mutating func note(_ text: String) {
        draw(text, font: .italicSystemFont(ofSize: 9), colour: .secondaryLabel)
    }

    mutating func paragraph(_ text: String) {
        draw(text, font: .systemFont(ofSize: 10), colour: .label)
    }

    mutating func rule() {
        ensure(12)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y + 4))
        path.addLine(to: CGPoint(x: pageSize.width - margin, y: y + 4))
        UIColor.separator.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        y += 12
    }

    mutating func image(_ image: UIImage) {
        let maxWidth = contentWidth
        let maxHeight: CGFloat = 260
        let scale = min(maxWidth / max(image.size.width, 1), maxHeight / max(image.size.height, 1), 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        ensure(size.height + 8)
        image.draw(in: CGRect(x: margin, y: y, width: size.width, height: size.height))
        y += size.height + 8
    }
}
