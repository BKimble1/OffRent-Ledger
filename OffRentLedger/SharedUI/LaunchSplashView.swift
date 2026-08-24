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
/// `markPoints` is the contract between the two. The asset ships at 1x, 2x and 3x of that one
/// point size (see `scripts/prepare_launch_assets.py`), and `UILaunchScreen` draws it at that
/// size without scaling. Drawing the same number here is what keeps them in step, and
/// `LaunchScreenTests` fails if they ever drift apart.
struct LaunchSplashView: View {

    /// The mark's size in points, matching `MARK_POINTS` in `scripts/prepare_launch_assets.py`.
    ///
    /// A fixed size, not a fraction of the screen. `UILaunchScreen` draws its image at the
    /// image's own point size and does not scale it, so the only way the two layers can agree on
    /// every device is for this one to use that same number. The previous version drew a
    /// fraction of the screen against a single 1024-pixel asset in the 1x slot — which iOS read
    /// as 1024 *points*, two and a half screens wide. That is the giant tag that appeared and
    /// then jumped.
    static let markPoints: CGFloat = 204

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()

            Image("LaunchMark")
                .resizable()
                .scaledToFit()
                .frame(width: Self.markPoints, height: Self.markPoints)
                .accessibilityHidden(true)

            VStack {
                Spacer()
                credit
                    .padding(.bottom, Space.section)
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

    /// How long the mark holds after the app is ready.
    ///
    /// Short, and it is a cross-fade rather than a cut. The first version held for 650ms and then
    /// animated — which, on top of a launch image that was the wrong size, read as two separate
    /// screens rather than one. The static launch screen and this now draw the identical mark at
    /// the identical size, so all this does is fade the credit line away.
    private static var hold: Duration { .milliseconds(240) }

    var body: some View {
        ZStack {
            content
            if !isFinished {
                LaunchSplashView()
                    .transition(.opacity)
            }
        }
        .task {
            // Under UI test the splash is time spent with nothing to assert against, on every
            // launch of every test. It reuses the existing `-offrent-disable-animations` flag
            // rather than adding a hook of its own, and like every one of those it is compiled
            // out of Release.
            if AppDependencies.testOverrides().disableAnimations {
                isFinished = true
                return
            }
            try? await Task.sleep(for: Self.hold)
            withAnimation(reduceMotion ? .default : .easeOut(duration: 0.28)) { isFinished = true }
        }
    }
}

#Preview {
    LaunchSplashView()
}
