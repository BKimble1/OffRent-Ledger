import Foundation
import SwiftUI

enum AppTab: String, Hashable, CaseIterable {
    case today
    case rentals
    case audit
    case settings

    var title: String {
        switch self {
        case .today: "Today"
        case .rentals: "Rentals"
        case .audit: "Audit"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .today: "sun.horizon"
        case .rentals: "shippingbox"
        case .audit: "checklist"
        case .settings: "gearshape"
        }
    }
}

/// Navigation state, and the one place a deep link turns into a destination.
///
/// Each tab keeps its own `NavigationPath` so switching tabs does not throw away where the user
/// was. A deep link resets only the path of the tab it targets.
@MainActor
@Observable
final class AppRouter {

    var selectedTab: AppTab = .today

    var todayPath = NavigationPath()
    var rentalsPath = NavigationPath()
    var auditPath = NavigationPath()
    var settingsPath = NavigationPath()

    /// Set when something asks for a modal that is not a navigation destination.
    var presentedSheet: AppSheet?

    /// A sheet asked for while another one was still up, waiting for it to go.
    private var queuedSheet: AppSheet?

    /// Presents a sheet, waiting for whatever is already up to close first.
    ///
    /// Assigning straight to `presentedSheet` is fine for a button: a button on the screen
    /// behind a sheet cannot be tapped, so there is never a sheet to replace. A tapped reminder
    /// is not a button. It arrives while the user is somewhere — possibly mid-sheet — and
    /// `.sheet(item:)` does not reliably swap one sheet for another; the binding changes and
    /// SwiftUI keeps showing the one it already has. That would be a notification that opens the
    /// app and then appears to ignore what it was about.
    ///
    /// So the request is parked and `sheetDidDismiss` delivers it, which is the same shape the
    /// welcome cover in `RootView` uses. No interval to tune, nothing to go flaky on a slower
    /// device: the handover happens when the dismissal has actually finished, not when a timer
    /// guesses it has.
    func present(_ sheet: AppSheet) {
        // `queuedSheet != nil` as well as `presentedSheet != nil`: between asking the sheet that
        // is up to close and its `onDismiss` arriving, `presentedSheet` is already nil while the
        // dismissal is still in flight. A second request in that window would assign straight
        // into the closing sheet's place and then be overwritten by the first one when the
        // handover finally ran. Queueing it instead means the last request wins, which is what
        // somebody who tapped two reminders in a row meant.
        guard presentedSheet == nil, queuedSheet == nil else {
            queuedSheet = sheet
            presentedSheet = nil
            return
        }
        presentedSheet = sheet
    }

    /// Called from the root sheet's `onDismiss`.
    func sheetDidDismiss() {
        guard let queued = queuedSheet else { return }
        queuedSheet = nil
        presentedSheet = queued
    }

    func handle(url: URL) -> Bool {
        guard let link = DeepLink(url: url) else { return false }
        handle(link)
        return true
    }

    /// Returns the tab the user is on to its root.
    ///
    /// For screens that delete the record they are showing. `RentalItemDetailView` used to clear
    /// `rentalsPath` unconditionally, but a rental is reachable from Today's map and from the
    /// Audit tab too — so deleting one from either left the user staring at "This rental is no
    /// longer here" while a tab they were not looking at quietly popped.
    func popToRoot() {
        switch selectedTab {
        case .today: todayPath = NavigationPath()
        case .rentals: rentalsPath = NavigationPath()
        case .audit: auditPath = NavigationPath()
        case .settings: settingsPath = NavigationPath()
        }
    }

    func handle(_ link: DeepLink) {
        switch link {
        case .today:
            selectedTab = .today
            todayPath = NavigationPath()

        case .rentals:
            selectedTab = .rentals
            rentalsPath = NavigationPath()

        case .audit:
            selectedTab = .audit
            auditPath = NavigationPath()

        case .addRental:
            selectedTab = .rentals
            present(.addRental)

        case let .rentalItem(id):
            selectedTab = .rentals
            rentalsPath = NavigationPath()
            rentalsPath.append(RentalDestination.item(id: id))

        case let .recordConfirmation(itemID):
            // Opens the *sheet*, on top of the item. An intent or a notification can bring the
            // user to the place where a confirmation is recorded; only the user, tapping Save
            // with the affirmation ticked, can record one.
            selectedTab = .rentals
            rentalsPath = NavigationPath()
            rentalsPath.append(RentalDestination.item(id: itemID))
            present(.recordConfirmation(itemID: itemID))

        case let .invoiceReview(invoiceID):
            selectedTab = .audit
            auditPath = NavigationPath()
            auditPath.append(AuditDestination.invoice(id: invoiceID))
        }
    }

    func path(for tab: AppTab) -> Binding<NavigationPath> {
        switch tab {
        case .today: Binding(get: { self.todayPath }, set: { self.todayPath = $0 })
        case .rentals: Binding(get: { self.rentalsPath }, set: { self.rentalsPath = $0 })
        case .audit: Binding(get: { self.auditPath }, set: { self.auditPath = $0 })
        case .settings: Binding(get: { self.settingsPath }, set: { self.settingsPath = $0 })
        }
    }
}

enum RentalDestination: Hashable {
    case item(id: UUID)
    case editItem(id: UUID)
    case agreement(id: UUID)
    case timeline(itemID: UUID)
    case vendors
    case jobSites
}

enum AuditDestination: Hashable {
    case invoice(id: UUID)
    case followUps
    case resolvedHistory
}

enum SettingsDestination: Hashable {
    case subscription
    case reminders
    case appearance
    case dataAndPrivacy
    case backupAndTransfer
    case privacyPolicy
    case terms
    case support
    case about
}

enum AppSheet: Identifiable, Hashable {
    case addRental
    /// New Rental with the camera already up.
    ///
    /// A separate case rather than an argument on `addRental`, so the two have different sheet
    /// identities: presenting one while the other is up must replace it, not be ignored as the
    /// same sheet.
    case scanRental
    case recordConfirmation(itemID: UUID)
    case recordPickup(itemID: UUID)
    case attachInvoice(itemID: UUID)
    case paywall(reason: PaywallReason)

    var id: String {
        switch self {
        case .addRental: "addRental"
        case .scanRental: "scanRental"
        case let .recordConfirmation(itemID): "confirm-\(itemID)"
        case let .recordPickup(itemID): "pickup-\(itemID)"
        case let .attachInvoice(itemID): "invoice-\(itemID)"
        case let .paywall(reason): "paywall-\(reason.rawValue)"
        }
    }
}

enum PaywallReason: String, Hashable {
    case openItemLimit
    case invoiceAudit
    case evidenceExport
    case advancedReminders
    case historyExport
    case settings

    var headline: String {
        switch self {
        case .openItemLimit: "You already have an open rental"
        case .invoiceAudit: "Invoice audit is part of Pro"
        case .evidenceExport: "Evidence packets are part of Pro"
        case .advancedReminders: "These reminders are part of Pro"
        case .historyExport: "Full history export is part of Pro"
        case .settings: "\(AppConfiguration.displayName) Pro"
        }
    }
}
