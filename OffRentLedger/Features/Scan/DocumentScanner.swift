import SwiftUI
import VisionKit

/// VisionKit's document camera, wrapped for SwiftUI.
///
/// It hands back images and nothing else. Recognition happens afterwards, in
/// `VisionTextRecognizer`, and interpretation happens after that, in `DocumentTextParser`. Keeping
/// the camera ignorant of what it is looking at is what lets the whole parsing path be tested
/// without one.
struct DocumentScannerView: UIViewControllerRepresentable {

    let onFinish: ([UIImage]) -> Void
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

    /// Whether the document camera is available at all. The simulator has no camera, and a UI
    /// test must be able to reach the review sheet without one.
    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        let onCancel: () -> Void
        let onError: (Error) -> Void

        init(
            onFinish: @escaping ([UIImage]) -> Void,
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
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            onFinish(images)
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
