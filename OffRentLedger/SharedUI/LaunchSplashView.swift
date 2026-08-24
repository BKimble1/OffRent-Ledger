import SwiftUI

/// The load-in screen, and the layer that finishes it.
///
/// Two things paint this moment, and they have to agree exactly.
///
/// `UILaunchScreen` in `Config/OffRentLedger-Info.plist` paints `LaunchBackground` and centres
/// `LaunchMark` before a single line of Swift runs. That is what stops the app opening on a white
/// flash, and it is all iOS will do — the dictionary takes a colour and an image and nothing else,
/// no text and no layout.
///
/// So the credit line comes from here. This view draws the same colour and the same mark at the
/// same fraction of the screen, adds "Powered by Idlery" underneath, and fades out once the app
/// is up. Because the mark does not move between the two layers, the handover is invisible: the
/// only thing the eye sees appear is the credit.
///
/// `markFraction` is the contract between the two. `LaunchMark.png` is a square canvas with the
/// tag occupying 76% of it (see `scripts/prepare_launch_assets.py`), and iOS fits that square to
/// the screen's narrower dimension. Drawing the same square at the same fraction here is what
/// keeps them in step; changing one without the other makes the tag jump at launch.
struct LaunchSplashView: View {

    /// Width of the mark's square canvas, as a fraction of the screen's narrower side.
    static let markFraction: CGFloat = 0.52

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * Self.markFraction
            ZStack {
                Color("LaunchBackground").ignoresSafeArea()

                Image("LaunchMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .accessibilityHidden(true)

                VStack {
                    Spacer()
                    credit
                        .padding(.bottom, Space.section)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(AppConfiguration.displayName), an Idlery Services app")
    }

    private var credit: some View {
        HStack(spacing: Space.snug - 2) {
            Text("Powered by")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            Image("IdleryWordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 14)
        }
        .accessibilityHidden(true)
    }
}

/// Holds the splash over the app until it has something to show, then fades it away.
///
/// Deliberately short and deliberately not a spinner. The work behind it — opening the store,
/// reading the entitlement — is usually finished before the first frame, so this is a fade rather
/// than a wait, and Reduce Motion turns it into a plain cross-dissolve.
struct LaunchSplashOverlay<Content: View>: View {

    @ViewBuilder var content: Content

    @State private var isFinished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long the mark holds before it starts to go. Long enough to read as deliberate, short
    /// enough that nobody waiting on a jobsite notices it.
    private static var hold: Duration { .milliseconds(650) }

    var body: some View {
        ZStack {
            content
            if !isFinished {
                LaunchSplashView()
                    .transition(.opacity)
            }
        }
        .task {
            // Under UI test the splash is 900ms of nothing to assert against, on every launch of
            // every test. It reuses the existing `-offrent-disable-animations` flag rather than
            // adding a hook of its own, and like every one of those it is compiled out of Release.
            if AppDependencies.testOverrides().disableAnimations {
                isFinished = true
                return
            }
            try? await Task.sleep(for: Self.hold)
            withAnimation(reduceMotion ? .default : Motion.standard) { isFinished = true }
        }
    }
}

#Preview {
    LaunchSplashView()
}
