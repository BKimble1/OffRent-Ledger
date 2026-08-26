import PDFKit
import SwiftUI
import UIKit

/// The generated packet, on screen, before it goes anywhere.
///
/// Two reasons this exists rather than a Share button on its own.
///
/// Sending a document you have not read to a rental company is how a small mistake becomes
/// correspondence, and the packet is assembled from records the user may have entered weeks
/// apart.
///
/// And it is the only way to notice, on the device, that the packet rendered at all. For several
/// builds it did not: every line was drawn with a dynamic colour that resolves to white in dark
/// mode, onto a PDF page with no background of its own. The file was the right size, the text was
/// extractable, and what came out of the share sheet was a blank sheet of paper. Nothing in the
/// app would have shown that, because nothing in the app ever displayed the thing it had made.
struct EvidencePDFPreview: View {

    let url: URL

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFDocumentView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Evidence packet")
                .navigationBarTitleDisplayMode(.inline)
                .accessibilityIdentifier(A11yID.EvidenceExport.preview)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier(A11yID.EvidenceExport.previewClose)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier(A11yID.EvidenceExport.previewShare)
                    }
                }
        }
    }
}

/// PDFKit's own view. There is no SwiftUI equivalent, and re-implementing paged zoomable
/// document rendering to avoid one `UIViewRepresentable` would be the wrong trade.
private struct PDFDocumentView: UIViewRepresentable {

    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        // The document is white paper. A pale surround is what gives the page an edge, and it is
        // the app's own sunken surface rather than PDFKit's default grey.
        view.backgroundColor = UIColor(red: 0.937, green: 0.925, blue: 0.898, alpha: 1)
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard view.document?.documentURL != url else { return }
        view.document = PDFDocument(url: url)
    }
}
