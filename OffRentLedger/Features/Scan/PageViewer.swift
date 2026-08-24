import SwiftUI
import UIKit

/// One scanned page, large enough to read.
///
/// Zoom matters more here than anywhere else in the app: the whole reason somebody opens this is
/// to check a figure the app says it read, and a rate printed in six-point type on a photograph
/// of a contract is not legible at page width.
struct PageViewer: View {

    let data: Data
    let pageNumber: Int
    let onClose: () -> Void

    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    private static let maximumScale: CGFloat = 6

    var body: some View {
        NavigationStack {
            Group {
                if let image = UIImage(data: data) {
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale * pinch)
                            .gesture(
                                MagnifyGesture()
                                    .updating($pinch) { value, state, _ in state = value.magnification }
                                    .onEnded { value in
                                        scale = min(Self.maximumScale, max(1, scale * value.magnification))
                                    }
                            )
                            // Double tap is the shortcut that needs no explaining, and it is the
                            // only way to get back to fit once you are zoomed in.
                            .onTapGesture(count: 2) {
                                withAnimation(Motion.standard) { scale = scale > 1 ? 1 : 2.5 }
                            }
                    }
                } else {
                    EmptyStateView(
                        symbol: "photo",
                        title: "That page could not be shown",
                        message: "The text it contains was still read."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Page \(pageNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
        .accessibilityIdentifier(A11yID.Scan.pageViewer)
    }
}
