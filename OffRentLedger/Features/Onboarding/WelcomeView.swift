import SwiftUI

/// The first screen of a first run.
///
/// One screen, not a carousel. The things that make onboarding work are well established and
/// mostly subtractive:
///
/// - Say what the app does in one sentence, in the user's words, not the product's.
/// - Offer the real first action, not "Continue". Somebody who came here to log a machine should
///   be able to start logging it from this screen.
/// - Make skipping obvious and cheap. A tour you cannot leave is a wall.
/// - Ask for nothing. No account, no notification permission, no email. Permission prompts belong
///   at the moment the feature is used, where the answer means something.
/// - Never repeat. Once dismissed, by any route, it does not come back.
struct WelcomeView: View {

    let onAddRental: () -> Void
    let onTakeTour: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.roomy) {
                    header
                    points
                }
                .padding(.horizontal, Space.roomy)
                .padding(.top, Space.section)
                .padding(.bottom, Space.roomy)
            }

            actions
        }
        .offRentScreen()
        // `children: .contain` before the identifier, not the identifier alone. An accessibility
        // modifier on a plain layout container is pushed down onto everything inside it, so the
        // bare identifier put "onboarding.welcome" on all three buttons and left the screen
        // itself with no element at all. `.contain` makes this view a real container that owns
        // the identifier while its children keep their own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.Onboarding.welcomeRoot)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.base) {
            Image("LaunchMark")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .accessibilityHidden(true)

            Text("Know what your rentals are costing you")
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            Text("""
                \(AppConfiguration.displayName) keeps the record: what is on rent, what it is \
                costing, and the confirmation number you got when you called it off.
                """)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var points: some View {
        VStack(alignment: .leading, spacing: Space.comfortable) {
            point(
                "clock.badge.exclamationmark",
                "See the running cost",
                "Estimated from the rates and dates you confirm."
            )
            point(
                "phone.badge.waveform",
                "Never lose a confirmation number",
                "You call the yard. This writes down what they told you, and when."
            )
            point(
                "list.clipboard",
                "Check the final invoice",
                "Laid out next to your confirmed terms, so a difference is easy to see."
            )
        }
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Space.base) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(Palette.accentText)
                .frame(width: 30, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: Space.base) {
            // The real first action, not "Continue". Somebody who opened this app to log a
            // machine can log it from here without reading anything else.
            Button("Add your first rental", action: onAddRental)
                .buttonStyle(.offRentPrimary)
                .accessibilityIdentifier(A11yID.Onboarding.welcomeAddRental)

            Button("Take a quick tour", action: onTakeTour)
                .buttonStyle(.offRentSecondary)
                .accessibilityIdentifier(A11yID.Onboarding.welcomeTour)

            Button("Skip for now", action: onSkip)
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
                .minimumTapTarget()
                .accessibilityIdentifier(A11yID.Onboarding.welcomeSkip)

            Text("No account. Everything stays on this iPhone.")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Space.roomy)
        .padding(.top, Space.base)
        .padding(.bottom, Space.snug)
        .background(Palette.background)
    }
}

#Preview {
    WelcomeView(onAddRental: {}, onTakeTour: {}, onSkip: {})
}
