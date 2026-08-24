import Foundation
import SwiftUI

/// What the app remembers about a first run.
///
/// Two flags, not one. "Has this person been welcomed" and "has this person seen the tour" are
/// different questions: somebody can skip the tour on day one and ask for it from Settings in
/// week three, and the welcome must not come back when they do.
///
/// Stored in `UserDefaults` rather than SwiftData on purpose. It has to be readable before the
/// store opens, because the welcome is still the right screen to show when the store failed.
@MainActor
@Observable
final class OnboardingState {

    private enum Key {
        static let welcomed = "com.idlery.offrent.onboarding.welcomed"
        static let tourFinished = "com.idlery.offrent.onboarding.tourFinished"
        static let guidedTourActive = "com.idlery.offrent.onboarding.guidedTourActive"
        static let guidedTourItem = "com.idlery.offrent.onboarding.guidedTourItem"
    }

    private let defaults: UserDefaults

    /// True once the welcome screen has been dismissed by any route.
    private(set) var hasBeenWelcomed: Bool

    /// True once the tour has been finished or skipped.
    private(set) var hasSeenTour: Bool

    /// Set while the tour is on screen. Not persisted — it is a presentation, not a preference.
    var isShowingTour = false

    /// The hands-on walkthrough, which runs *in* the app rather than over it.
    ///
    /// Persisted, unlike `isShowingTour`: somebody halfway through recording a confirmation may
    /// put the phone down for a day, and coming back to no guide at all would read as the app
    /// having forgotten. Skipping clears it.
    private(set) var isGuidedTourActive: Bool

    /// The rental the guide is following. Set when the user creates one during the walkthrough,
    /// so the bar keeps pointing at the same machine rather than jumping to whatever is newest.
    private(set) var guidedTourItemID: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasBeenWelcomed = defaults.bool(forKey: Key.welcomed)
        hasSeenTour = defaults.bool(forKey: Key.tourFinished)
        isGuidedTourActive = defaults.bool(forKey: Key.guidedTourActive)
        guidedTourItemID = defaults.string(forKey: Key.guidedTourItem).flatMap(UUID.init(uuidString:))
    }

    var shouldShowWelcome: Bool { !hasBeenWelcomed }

    func markWelcomed() {
        hasBeenWelcomed = true
        defaults.set(true, forKey: Key.welcomed)
    }

    /// Finishing and skipping record the same thing. The flag answers "should this open by
    /// itself again", and after a skip the answer is no — a tour that reappears because you
    /// declined it has stopped being optional.
    func markTourSeen() {
        hasSeenTour = true
        defaults.set(true, forKey: Key.tourFinished)
        isShowingTour = false
    }

    func startTour() {
        isShowingTour = true
    }

    // MARK: - The guided walkthrough

    func startGuidedTour() {
        isShowingTour = false
        markTourSeen()
        isGuidedTourActive = true
        defaults.set(true, forKey: Key.guidedTourActive)
    }

    /// Ends it, by finishing or by skipping. Both clear the followed rental: the guide is over
    /// either way, and a stale identifier would put the bar back on the next launch.
    func endGuidedTour() {
        isGuidedTourActive = false
        guidedTourItemID = nil
        defaults.removeObject(forKey: Key.guidedTourActive)
        defaults.removeObject(forKey: Key.guidedTourItem)
    }

    /// Called once, when a rental is created while the guide is running.
    func followGuidedTourItem(_ id: UUID) {
        guard isGuidedTourActive, guidedTourItemID == nil else { return }
        guidedTourItemID = id
        defaults.set(id.uuidString, forKey: Key.guidedTourItem)
    }

    /// Lets a UI test start from a clean first run without touching the real defaults suite.
    func reset() {
        hasBeenWelcomed = false
        hasSeenTour = false
        defaults.removeObject(forKey: Key.welcomed)
        defaults.removeObject(forKey: Key.tourFinished)
        endGuidedTour()
    }
}
