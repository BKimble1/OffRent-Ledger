import SwiftUI

/// The walkthrough: a sequence of pages, advanced by its own controls and nothing else.
///
/// It replaces two things. The five-page tour it grew out of, and — more importantly — the
/// hands-on guide that followed it: a bar above the tab bar that read the newest rental's status
/// and asked the user to perform each real step of the workflow before it would advance. That
/// design could not desync from the app, which was its one virtue, and it had three faults:
///
/// 1. It could not be finished without creating a rental, ringing a rental company, recording a
///    pickup and accepting an invoice. Somebody wanting to know what the app *is* had to make
///    records they would then delete.
/// 2. On the day it matters most — installation day — the user has none of those things, so the
///    guide sat on step one indefinitely.
/// 3. `Skip` was its only exit, which made its own progress bar a promise it could not keep.
///
/// So: `Next`, `Back`, `Skip`, `Finish`. It blocks on nothing, writes nothing, and `Finish` on
/// the last page dismisses immediately with nothing else to tap.
struct WalkthroughView: View {

    let onFinish: () -> Void
    let onSkip: () -> Void

    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header

            TabView(selection: $index) {
                ForEach(WalkthroughScript.pages) { page in
                    pageView(page).tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            progressDots
            footer
        }
        .offRentScreen()
        // `.contain` before the identifier. Without it this lands on Skip, Back and Next instead
        // of on the walkthrough, and all three lose their own — which is exactly what a previous
        // accessibility dump showed.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.Onboarding.tourRoot)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Text("\(index + 1) of \(WalkthroughScript.count)")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Button("Skip", action: onSkip)
                .font(.body)
                .foregroundStyle(Palette.accentText)
                .minimumTapTarget()
                .accessibilityIdentifier(A11yID.Onboarding.tourSkip)
        }
        .padding(.horizontal, Space.roomy)
        .padding(.top, Space.snug)
    }

    private var progressDots: some View {
        HStack(spacing: Space.tight + 2) {
            ForEach(WalkthroughScript.pages) { page in
                Capsule()
                    .fill(page.id <= index ? Palette.accent : Palette.hairline)
                    .frame(width: page.id == index ? 18 : 6, height: 6)
                    .animation(reduceMotion ? nil : Motion.quick, value: index)
            }
        }
        .padding(.bottom, Space.base)
        .accessibilityElement()
        .accessibilityLabel("Page \(index + 1) of \(WalkthroughScript.count)")
    }

    private var footer: some View {
        VStack(spacing: Space.snug) {
            Button(WalkthroughScript.forwardTitle(at: index)) { advance() }
                .buttonStyle(.offRentPrimary)
                .accessibilityIdentifier(A11yID.Onboarding.tourNext)

            // Back is present from the second page on, and absent rather than disabled on the
            // first: a greyed control that has never been usable is a control that teaches
            // nothing.
            if !WalkthroughScript.isFirst(index) {
                Button("Back") { retreat() }
                    .buttonStyle(.offRentSecondary)
                    .accessibilityIdentifier(A11yID.Onboarding.tourBack)
            }
        }
        .padding(.horizontal, Space.roomy)
        .padding(.bottom, Space.comfortable)
    }

    // MARK: - Pages

    private func pageView(_ page: WalkthroughPage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.roomy) {
                // The illustration is a real component drawn with obviously illustrative
                // figures, never a screenshot and never a record. Nothing on these pages is
                // written anywhere, which is the property the UI test asserts.
                illustration(for: page)

                VStack(alignment: .leading, spacing: Space.snug) {
                    Text(page.title)
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(page.body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let tab = tabName(page.focus) {
                    Label("Find it under \(tab)", systemImage: page.symbol)
                        .font(Typography.caption.weight(.semibold))
                        .foregroundStyle(Palette.accentText)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.roomy)
            .padding(.top, Space.base)
            .padding(.bottom, Space.section)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.Onboarding.tourPage)
    }

    @ViewBuilder
    private func illustration(for page: WalkthroughPage) -> some View {
        switch page.id {
        case 0:
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

        case 1:
            VStack(alignment: .leading, spacing: Space.base) {
                StatusChip(status: .active)
                StatusChip(status: .contactVendor)
                StatusChip(status: .awaitingPickup)
                StatusChip(status: .invoiceReview)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .offRentCard()

        case 2:
            VStack(spacing: Space.base) {
                illustrationRow("building.2", "Rental companies", "Added once, picked from then on")
                illustrationRow("mappin.and.ellipse", "Jobsites", "On the map, with a real address")
            }

        case 3:
            OffRentDisclosureBanner(identifier: "tour.disclosure")

        case 4:
            VStack(spacing: Space.base) {
                illustrationRow("checkmark.rectangle.stack", "Off-rent confirmation", "What the yard told you")
                illustrationRow("truck.box", "Pickup", "When it actually left the site")
            }

        case 5:
            VariancePanel(expected: 1710, invoiced: 1995, variance: 285, isMatch: false)

        default:
            VStack(spacing: Space.base) {
                illustrationRow("lock.iphone", "On this iPhone", "No account, no server, no analytics")
                illustrationRow("arrow.up.doc", "Backup and transfer", "In Settings, whenever you want it")
            }
        }
    }

    private func illustrationRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
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

    private func tabName(_ focus: WalkthroughFocus) -> String? {
        switch focus {
        case .today: AppTab.today.title
        case .rentals: AppTab.rentals.title
        case .audit: AppTab.audit.title
        case .settings: AppTab.settings.title
        case .none: nil
        }
    }

    // MARK: - Navigation

    private func advance() {
        guard !WalkthroughScript.isLast(index) else {
            onFinish()
            return
        }
        withAnimation(reduceMotion ? nil : Motion.standard) { index += 1 }
    }

    private func retreat() {
        guard !WalkthroughScript.isFirst(index) else { return }
        withAnimation(reduceMotion ? nil : Motion.standard) { index -= 1 }
    }
}

#Preview {
    WalkthroughView(onFinish: {}, onSkip: {})
}
