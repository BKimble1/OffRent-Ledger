import Foundation
import SwiftUI

/// What the app remembers about a first run.
///
/// Two facts, not one. "Has this person been welcomed" and "which version of the walkthrough have
/// they completed" are different questions: somebody can skip the walkthrough on day one and ask
/// for it from Settings in week three, and the welcome must not come back when they do.
///
/// The walkthrough is stored as a *version* rather than a flag. A flag can only answer "have they
/// seen it"; a version can answer "have they seen *this* one", which is what lets the app show a
/// materially rewritten walkthrough once without showing the same one twice.
///
/// Stored in `UserDefaults` rather than SwiftData on purpose. It has to be readable before the
/// store opens, because the welcome is still the right screen to show when the store failed.
@MainActor
@Observable
final class OnboardingState {

    private enum Key {
        static let welcomed = "com.idlery.offrent.onboarding.welcomed"
        /// The old boolean. Read once, on upgrade, and then never written again.
        static let legacyTourFinished = "com.idlery.offrent.onboarding.tourFinished"
        static let tourVersion = "com.idlery.offrent.onboarding.tourVersion"
        /// Written by the guided walkthrough that no longer exists. Cleared on launch so a phone
        /// upgrading from build 7 does not carry a flag nothing reads.
        static let retiredGuideActive = "com.idlery.offrent.onboarding.guidedTourActive"
        static let retiredGuideItem = "com.idlery.offrent.onboarding.guidedTourItem"
    }

    private let defaults: UserDefaults

    /// True once the welcome screen has been dismissed by any route.
    private(set) var hasBeenWelcomed: Bool

    /// The walkthrough version this person has finished or skipped, if any.
    private(set) var completedTourVersion: Int?

    /// Set while the walkthrough is on screen. Not persisted — it is a presentation, not a
    /// preference.
    var isShowingTour = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasBeenWelcomed = defaults.bool(forKey: Key.welcomed)

        if let stored = defaults.object(forKey: Key.tourVersion) as? Int {
            completedTourVersion = stored
        } else if defaults.bool(forKey: Key.legacyTourFinished) {
            // Upgrading from a build that only had a boolean. Somebody who finished the old tour
            // has finished *a* tour; treating that as version 1 means they see the rewritten one
            // exactly once rather than never or every launch.
            completedTourVersion = 1
        } else {
            completedTourVersion = nil
        }

        // The guided walkthrough is gone. Its keys are cleared so an upgrade does not leave a
        // half-finished guide recorded against a rental that nothing will ever point at again.
        defaults.removeObject(forKey: Key.retiredGuideActive)
        defaults.removeObject(forKey: Key.retiredGuideItem)
    }

    var shouldShowWelcome: Bool { !hasBeenWelcomed }

    /// Whether the walkthrough should present itself. False once this version has been completed
    /// or skipped, however many times the app relaunches.
    var shouldPresentTour: Bool {
        WalkthroughScript.shouldPresent(seenVersion: completedTourVersion)
    }

    /// True once the current walkthrough has been finished or skipped.
    var hasSeenTour: Bool { !shouldPresentTour }

    func markWelcomed() {
        hasBeenWelcomed = true
        defaults.set(true, forKey: Key.welcomed)
    }

    /// Finishing and skipping record the same thing. The stored version answers "should this open
    /// by itself again", and after a skip the answer is no — a walkthrough that reappears because
    /// you declined it has stopped being optional.
    func markTourSeen() {
        completedTourVersion = WalkthroughScript.version
        defaults.set(WalkthroughScript.version, forKey: Key.tourVersion)
        isShowingTour = false
    }

    func startTour() {
        isShowingTour = true
    }

    /// Lets a UI test start from a clean first run without touching the real defaults suite.
    func reset() {
        hasBeenWelcomed = false
        completedTourVersion = nil
        isShowingTour = false
        defaults.removeObject(forKey: Key.welcomed)
        defaults.removeObject(forKey: Key.legacyTourFinished)
        defaults.removeObject(forKey: Key.tourVersion)
    }
}
