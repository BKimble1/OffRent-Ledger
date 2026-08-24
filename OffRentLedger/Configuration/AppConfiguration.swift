import Foundation
import SwiftUI

/// The single source for the product's identity, its URLs and its product identifiers.
///
/// `displayName` is the only place the working name is written. Everything user-facing
/// interpolates it, and `scripts/verify_repository.py` fails the build if another Swift file
/// hardcodes the string. Renaming the product is this line plus `OFFRENT_DISPLAY_NAME` in
/// `Config/Identifiers.xcconfig`.
enum AppConfiguration {

    // MARK: - Identity

    /// Re-exported from `SharedBranding` so app code has one obvious place to reach for it.
    /// The literal itself lives in `OffRentShared/SharedBranding.swift`, which the widget
    /// and the portable domain package can also see.
    static let displayName = SharedBranding.displayName
    static let companyName = SharedBranding.companyName
    static let companyShortName = SharedBranding.companyShortName

    /// Shown once, in About. The product is OffRent Ledger; the company is a footnote, not a
    /// co-brand running through the workflow.
    static let poweredByLine = "Powered by \(companyShortName)"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var versionAndBuild: String { "\(version) (\(build))" }

    // MARK: - Subscription

    static let monthlyProductIdentifier = "com.idlery.offrent.pro.monthly"
    static let annualProductIdentifier = "com.idlery.offrent.pro.annual"

    static var subscriptionProductIdentifiers: [String] {
        [monthlyProductIdentifier, annualProductIdentifier]
    }

    /// No price appears here. Everything the user sees comes from `Product.displayPrice`, so a
    /// price change in App Store Connect needs no app update and the app cannot show a stale
    /// figure next to a real charge.

    // MARK: - Links

    /// **UNVERIFIED — nothing has confirmed these resolve.**
    ///
    /// While this is `false` the app renders its bundled legal text instead of linking out, and
    /// the paywall's Privacy and Terms controls open in-app screens. Flip it only once each URL
    /// has actually been loaded in a browser; `scripts/verify_repository.py` fails the build if
    /// it is `true` while any URL below still points at a host that has not been signed off in
    /// `RELEASE_CHECKLIST.md`.
    static let legalURLsAreLive = false

    static let plannedWebsiteURL = URL(string: "https://offrent.idlery.com")
    static let plannedPrivacyURL = URL(string: "https://offrent.idlery.com/privacy")
    static let plannedTermsURL = URL(string: "https://offrent.idlery.com/terms")
    static let plannedSupportURL = URL(string: "https://offrent.idlery.com/support")

    /// Support address. Reachable without a website.
    static let supportEmail = "support@idlery.com"

    static var supportMailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "\(displayName) support"),
        ]
        return components.url
    }

    /// Apple's own manage-subscriptions destination. Used as the fallback when StoreKit's
    /// in-app sheet is unavailable.
    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")

    // MARK: - Behaviour

    /// How far ahead Today looks for "upcoming rate changes". Fixed by the product spec.
    static let upcomingRateChangeWindow: TimeInterval = 48 * 60 * 60

    /// Rows rendered before the rentals list starts paging.
    static let rentalsPageSize = 60

    /// Longest edge for a stored evidence photo. Full-resolution camera frames are 12MP; storing
    /// them whole fills a phone and makes list scrolling decode 4 MB images.
    static let evidenceImageMaxDimension: CGFloat = 2_048
    static let evidenceImageCompressionQuality: CGFloat = 0.8
    static let thumbnailMaxDimension: CGFloat = 320
}

/// Launch arguments the UI test suite uses to make the app deterministic.
///
/// Reading them is confined to `AppDependencies`, and every one of them is ignored in a Release
/// build — see `AppDependencies.testOverrides`. A test hook that survives into the App Store is a
/// way for a reviewer to see a screen no customer ever will.
enum LaunchArgument {
    static let useInMemoryStore = "-offrent-in-memory-store"
    static let resetState = "-offrent-reset-state"
    static let seedWalkthroughFixture = "-offrent-seed-walkthrough"
    static let seedFreeLimitFixture = "-offrent-seed-free-limit"
    static let forceProEntitlement = "-offrent-force-pro"
    static let forceFreeEntitlement = "-offrent-force-free"
    static let disableAnimations = "-offrent-disable-animations"
    static let stubTextRecogniser = "-offrent-stub-ocr"
    /// ISO-8601 instant to freeze the clock at, as `-offrent-fixed-now <value>`.
    static let fixedNow = "-offrent-fixed-now"
    /// Start from a clean first run, so the welcome screen appears.
    static let resetOnboarding = "-offrent-reset-onboarding"
    /// Start as a returning user, so the welcome screen does not sit in front of every test.
    static let skipOnboarding = "-offrent-skip-onboarding"
}

/// The user's appearance choice.
///
/// Applied once, at the root, because `preferredColorScheme` affects the view it is attached to
/// and its children — setting it on the settings screen would change the settings screen and
/// nothing else.
enum AppearanceSetting {
    static let storageKey = "com.idlery.offrent.appearance"
    static let system = "system"
    static let light = "light"
    static let dark = "dark"

    static func colorScheme(for value: String) -> ColorScheme? {
        switch value {
        case light: .light
        case dark: .dark
        default: nil   // nil means "match iOS"
        }
    }
}
