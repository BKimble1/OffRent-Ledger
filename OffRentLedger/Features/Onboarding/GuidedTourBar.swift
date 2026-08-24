import SwiftData
import SwiftUI

/// The guided walkthrough, drawn as a bar above the tab bar rather than as coach marks.
///
/// Coach marks — bubbles pinned to controls — were rejected for the first tour and are rejected
/// here for the same reasons, plus one more that only applies to a walkthrough of a real
/// workflow: the control this step is about is often not on screen. "Record the pickup" lives on
/// a rental detail screen the user may not have opened yet. A bubble cannot point at it; a bar
/// can name it, and can take you there.
///
/// It knows which step it is on by reading the rental's status through `GuidedTourStep`, so it
/// cannot desync from the app, cannot skip ahead, and needs no hooks in any of the buttons it
/// talks about.
struct GuidedTourBar: View {

    @Environment(OnboardingState.self) private var onboarding

    /// The `@Query` lives one level down, in `ActiveGuidedTourBar`, so it is only ever created
    /// while the walkthrough is running. A `@Query` declared here would fetch every rental on
    /// every render of the root view for every user, almost all of whom will never see this bar.
    var body: some View {
        if onboarding.isGuidedTourActive {
            ActiveGuidedTourBar()
        }
    }
}

private struct ActiveGuidedTourBar: View {

    @Environment(OnboardingState.self) private var onboarding
    @Environment(AppRouter.self) private var router

    @Query(sort: \RentalItem.createdAt, order: .reverse) private var items: [RentalItem]

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: Layout.hairline)
            content
                .padding(.horizontal, Space.comfortable)
                .padding(.vertical, Space.base)
                .background(.bar)
        }
        // `.contain` before the identifier, as on the welcome screen. Without it the bar's
        // identifier is pushed down onto Skip and the action button and both lose their own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.Onboarding.guideBar)
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.snug) {
            HStack(alignment: .firstTextBaseline, spacing: Space.snug) {
                Image(systemName: step.symbol)
                    .font(Typography.rowDetail.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                Text(step.isFinished ? step.title : "Step \(step.number) of \(GuidedTourStep.count) · \(step.title)")
                    .font(Typography.rowTitle.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.snug)
                Button(step.isFinished ? "Done" : "Skip") {
                    onboarding.endGuidedTour()
                }
                .font(Typography.rowDetail)
                .foregroundStyle(step.isFinished ? Palette.accent : .secondary)
                .accessibilityIdentifier(A11yID.Onboarding.guideSkip)
            }

            Text(step.instruction)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !step.isFinished {
                progress
            }

            if let action {
                Button(action.title) { action.perform() }
                    .buttonStyle(.offRentSecondary)
                    .accessibilityIdentifier(A11yID.Onboarding.guideAction)
            }
        }
    }

    /// Ticks rather than a bar: eight steps is a small enough number to count, and a filled bar
    /// at 3/8 does not tell anybody which three.
    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(GuidedTourStep.walkable, id: \.self) { candidate in
                Capsule()
                    .fill(candidate.number <= step.number ? Palette.accent : Palette.hairline)
                    .frame(height: 3)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(step.number) of \(GuidedTourStep.count)")
    }

    // MARK: - State

    /// The rental being followed: the one created during the walkthrough if there is one, and
    /// otherwise whatever is open, so somebody who already had rentals is not asked to make
    /// another before the guide will say anything useful.
    private var followed: RentalItem? {
        if let id = onboarding.guidedTourItemID, let match = items.first(where: { $0.id == id }) {
            return match
        }
        return items.first { $0.status.isOpen }
    }

    private var step: GuidedTourStep {
        GuidedTourStep.step(for: followed?.status)
    }

    private struct GuideAction {
        let title: String
        let perform: () -> Void
    }

    /// One button, and only where the app can honestly take somebody to the right place. The
    /// steps that need a phone call to the rental company deliberately have none — this app does
    /// not make that call and must not offer a button that looks like it does.
    private var action: GuideAction? {
        switch step {
        case .createRental:
            return GuideAction(title: "Open Add rental") {
                router.handle(.addRental)
            }
        case .finished:
            return nil
        default:
            guard let followed else { return nil }
            return GuideAction(title: "Open \(followed.equipmentName)") {
                // The deep link the notifications and App Intents already use, so the guide
                // arrives the same way everything else does.
                router.handle(.rentalItem(id: followed.id))
            }
        }
    }
}
