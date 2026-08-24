import SwiftUI

/// The skippable walkthrough.
///
/// Five pages, because the app has five things worth knowing and a sixth page is where people
/// start swiping without reading. What it deliberately does not do:
///
/// - **No coach marks.** Bubbles pinned to real controls break the moment a layout changes, and
///   they cannot be read by VoiceOver in any sensible order. Each page shows the *actual*
///   component instead — a real `StatusChip`, a real `VariancePanel` — so the tour cannot drift
///   away from the app it is describing.
/// - **No progress gate.** Skip is in the top right on every page, where iOS users already look
///   for it, and it is a full tap target rather than a 20pt word.
/// - **No permission prompts.** Notifications get asked for in Settings, at the moment somebody
///   turns a reminder on and the answer means something.
/// - **No fake data presented as real.** The figures on these pages are obviously illustrative
///   and never written anywhere.
struct TourView: View {

    let onFinish: () -> Void
    let onContinue: () -> Void

    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pageCount = 5

    var body: some View {
        VStack(spacing: 0) {
            header

            TabView(selection: $page) {
                todayPage.tag(0)
                rentalsPage.tag(1)
                offRentPage.tag(2)
                pickupPage.tag(3)
                invoicePage.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            footer
        }
        .offRentScreen()
        // See the note in WelcomeView: without `.contain` this identifier lands on Skip, Next
        // and Done rather than on the tour.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.Onboarding.tourRoot)
    }

    private var header: some View {
        HStack {
            Spacer()
            Button("Skip", action: onFinish)
                .font(.body)
                .foregroundStyle(Palette.accent)
                .minimumTapTarget()
                .padding(.horizontal, Space.comfortable)
                .accessibilityIdentifier(A11yID.Onboarding.tourSkip)
        }
        .padding(.top, Space.snug)
    }

    private var footer: some View {
        VStack(spacing: Space.snug) {
            if page < Self.pageCount - 1 {
                Button("Next") {
                    withAnimation(reduceMotion ? .default : Motion.standard) { page += 1 }
                }
                .buttonStyle(.offRentPrimary)
                .accessibilityIdentifier(A11yID.Onboarding.tourNext)
            } else {
                // The primary action on the last page is the hands-on half, not the exit. Five
                // pages of screenshots teach somebody what the app looks like; walking the
                // workflow once teaches them what it is for.
                Button("Continue tour — walk the workflow", action: onContinue)
                    .buttonStyle(.offRentPrimary)
                    .accessibilityIdentifier(A11yID.Onboarding.continueTour)

                Button("Start using \(AppConfiguration.displayName)", action: onFinish)
                    .buttonStyle(.offRentSecondary)
                    .accessibilityIdentifier(A11yID.Onboarding.tourDone)
            }
        }
        .padding(.horizontal, Space.roomy)
        .padding(.bottom, Space.comfortable)
    }

    // MARK: - Pages

    private var todayPage: some View {
        page(
            title: "What it is costing right now",
            detail: """
                Today adds up the rentals still accruing. It is an estimate from the rates and \
                dates you confirmed — not an invoice.
                """
        ) {
            VStack(alignment: .leading, spacing: Space.snug) {
                Text("Estimated rent running")
                    .font(Typography.rowDetail)
                    .foregroundStyle(Palette.onGraphiteSecondary)
                Text("$4,182.50")
                    .font(Typography.hero)
                    .monospacedDigit()
                    .foregroundStyle(Palette.onGraphite)
                Text(AppCopy.estimateQualifier)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.onGraphiteSecondary)
            }
            .offRentPanel()
        }
    }

    private var rentalsPage: some View {
        page(
            title: "Where every machine stands",
            detail: "Each rental carries its own state, so you can see what needs doing at a glance."
        ) {
            VStack(alignment: .leading, spacing: Space.base) {
                StatusChip(status: .active)
                StatusChip(status: .contactVendor)
                StatusChip(status: .awaitingPickup)
                StatusChip(status: .invoiceReview)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .offRentCard()
        }
    }

    private var offRentPage: some View {
        page(
            title: "You make the call",
            detail: """
                When you are done with a machine, mark it done. That stops the running estimate \
                and reminds you to ring the yard for a confirmation number.
                """
        ) {
            OffRentDisclosureBanner(identifier: "tour.disclosure")
        }
    }

    private var pickupPage: some View {
        page(
            title: "Confirmation and pickup are separate",
            detail: """
                The vendor agreeing a stop date and the truck actually collecting are two \
                different events, on two different days. Both get recorded.
                """
        ) {
            VStack(spacing: Space.base) {
                tourRow("checkmark.rectangle.stack", "Off-rent confirmation", "What the yard told you")
                tourRow("truck.box", "Pickup", "When it actually left the site")
            }
        }
    }

    private var invoicePage: some View {
        page(
            title: "Check the final invoice",
            detail: """
                Your confirmed terms next to what you were billed. A difference is a prompt to \
                look, never a claim that a charge is wrong.
                """
        ) {
            VariancePanel(expected: 1710, invoiced: 1995, variance: 285, isMatch: false)
        }
    }

    // MARK: - Page plumbing

    private func page(
        title: String, detail: String, @ViewBuilder illustration: () -> some View
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.roomy) {
                VStack(alignment: .leading, spacing: Space.snug) {
                    Text(title)
                        .font(.title.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                illustration()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.roomy)
            .padding(.top, Space.base)
            .padding(.bottom, Space.section)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private func tourRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: Space.base) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(Palette.waiting)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Typography.rowTitle)
                Text(detail).font(Typography.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .offRentCard()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    TourView(onFinish: {}, onContinue: {})
}
