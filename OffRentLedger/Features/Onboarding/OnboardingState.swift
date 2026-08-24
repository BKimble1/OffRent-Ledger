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
    }

    private let defaults: UserDefaults

    /// True once the welcome screen has been dismissed by any route.
    private(set) var hasBeenWelcomed: Bool

    /// True once the tour has been finished or skipped.
    private(set) var hasSeenTour: Bool

    /// Set while the tour is on screen. Not persisted — it is a presentation, not a preference.
    var isShowingTour = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasBeenWelcomed = defaults.bool(forKey: Key.welcomed)
        hasSeenTour = defaults.bool(forKey: Key.tourFinished)
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

    /// Lets a UI test start from a clean first run without touching the real defaults suite.
    func reset() {
        hasBeenWelcomed = false
        hasSeenTour = false
        defaults.removeObject(forKey: Key.welcomed)
        defaults.removeObject(forKey: Key.tourFinished)
    }
}
