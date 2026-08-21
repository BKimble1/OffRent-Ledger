import SwiftUI
import VisionKit

/// VisionKit's document camera, wrapped for SwiftUI.
///
/// It hands back images and nothing else. Recognition happens afterwards, in
/// `VisionTextRecognizer`, and interpretation happens after that, in `DocumentTextParser`. Keeping
/// the camera ignorant of what it is looking at is what lets the whole parsing path be tested
/// without one.
struct DocumentScannerView: UIViewControllerRepresentable {

    /// Hands back encoded JPEG data, not `UIImage`. Everything downstream — the recogniser and
    /// the file store — is an actor, and a bitmap cannot cross into one.
    let onFinish: ([Data]) -> Void
    let onCancel: () -> Void
    let onError: (Error) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel, onError: onError)
    }

    /// Quality for the scanned page handed downstream. High, because this is the input to text
    /// recognition: JPEG artefacts around 8pt invoice type cost real accuracy, and the file store
    /// re-encodes at its own quality afterwards anyway.
    static let scanEncodingQuality: CGFloat = 0.95

    /// Whether the document camera is available at all. The simulator has no camera, and a UI
    /// test must be able to reach the review sheet without one.
    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([Data]) -> Void
        let onCancel: () -> Void
        let onError: (Error) -> Void

        init(
            onFinish: @escaping ([Data]) -> Void,
            onCancel: @escaping () -> Void,
            onError: @escaping (Error) -> Void
        ) {
            self.onFinish = onFinish
            self.onCancel = onCancel
            self.onError = onError
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let pages = (0..<scan.pageCount).compactMap {
                scan.imageOfPage(at: $0).jpegData(compressionQuality: DocumentScannerView.scanEncodingQuality)
            }
            onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController, didFailWithError error: Error
        ) {
            onError(error)
        }
    }
}
