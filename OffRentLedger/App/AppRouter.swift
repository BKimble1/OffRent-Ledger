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

    func handle(url: URL) -> Bool {
        guard let link = DeepLink(url: url) else { return false }
        handle(link)
        return true
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
            presentedSheet = .addRental

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
            presentedSheet = .recordConfirmation(itemID: itemID)

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
    case recordConfirmation(itemID: UUID)
    case recordPickup(itemID: UUID)
    case attachInvoice(itemID: UUID)
    case paywall(reason: PaywallReason)

    var id: String {
        switch self {
        case .addRental: "addRental"
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
    case widget
    case advancedReminders
    case historyExport
    case settings

    var headline: String {
        switch self {
        case .openItemLimit: "You already have an open rental"
        case .invoiceAudit: "Invoice audit is part of Pro"
        case .evidenceExport: "Evidence packets are part of Pro"
        case .widget: "The widget is part of Pro"
        case .advancedReminders: "These reminders are part of Pro"
        case .historyExport: "Full history export is part of Pro"
        case .settings: "\(AppConfiguration.displayName) Pro"
        }
    }
}
