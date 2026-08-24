import Foundation

/// The UI suite's copy of the accessibility identifiers.
///
/// The UI test target cannot `@testable import` the app — it drives it as a black box — so it
/// cannot see `A11yID`. `scripts/verify_repository.py` compares the two lists and fails the build
/// when they drift, which is what stops a renamed identifier turning into a silent timeout three
/// weeks later.
enum A11yUI {
    /// Tab-bar buttons are found by their visible title rather than by an identifier — see the
    /// note in the app's AccessibilityIdentifiers.swift. These are titles, not identifiers, which
    /// is why the drift check skips them (identifiers are dotted; titles are not).
    enum Tab {
        static let today = "Today"
        static let rentals = "Rentals"
        static let audit = "Audit"
        static let settings = "Settings"
    }

    enum Today {
        static let root = "today.root"
        static let estimatedRentRunning = "today.estimatedRentRunning"
        static let emptyState = "today.emptyState"
        static let addRental = "today.addRental"
    }

    enum Rentals {
        static let root = "rentals.root"
        static let addRental = "rentals.addRental"
        static let searchField = "rentals.search"
    }

    enum AddRental {
        static let root = "addRental.root"
        static let equipmentName = "addRental.equipmentName"
        static let newVendorName = "addRental.newVendorName"
        static let dailyRate = "addRental.dailyRate"
        static let save = "addRental.save"
        static let cancel = "addRental.cancel"
        static let scanButton = "addRental.scan"
    }

    enum ItemDetail {
        static let root = "itemDetail.root"
        static let status = "itemDetail.status"
        static let markDone = "itemDetail.markDone"
        static let recordConfirmation = "itemDetail.recordConfirmation"
        static let recordPickup = "itemDetail.recordPickup"
        static let attachInvoice = "itemDetail.attachInvoice"
        static let disclosure = "itemDetail.disclosure"
    }

    enum Confirmation {
        static let disclosure = "confirmation.disclosure"
        static let number = "confirmation.number"
        static let affirmation = "confirmation.affirmation"
        static let save = "confirmation.save"
    }

    enum Pickup {
        static let save = "pickup.save"
    }

    enum Scan {
        static let reviewRoot = "scan.review.root"
        static let explanation = "scan.review.explanation"
        static let saveButton = "scan.review.save"
        static let cancelButton = "scan.review.cancel"
    }

    enum Onboarding {
        static let welcomeRoot = "onboarding.welcome"
        static let welcomeAddRental = "onboarding.welcome.addRental"
        static let welcomeTour = "onboarding.welcome.tour"
        static let welcomeSkip = "onboarding.welcome.skip"
        static let tourRoot = "onboarding.tour"
        static let tourSkip = "onboarding.tour.skip"
        static let tourNext = "onboarding.tour.next"
        static let tourDone = "onboarding.tour.done"
    }

    enum Audit {
        static let possibleMismatches = "audit.possibleMismatches"
        static let possibleVariance = "audit.possibleVariance"
        static let recordFollowUp = "audit.recordFollowUp"
        static let followUpReason = "audit.followUpReason"
        static let resolveInvoice = "audit.resolveInvoice"
        static let saveInvoice = "audit.saveInvoice"
    }

    enum Paywall {
        static let root = "paywall.root"
        static let monthly = "paywall.monthly"
        static let annual = "paywall.annual"
        static let purchase = "paywall.purchase"
        static let restore = "paywall.restore"
        static let terms = "paywall.terms"
        static let privacy = "paywall.privacy"
    }

    enum Settings {
        static let subscription = "settings.subscription"
        static let dataAndPrivacy = "settings.dataAndPrivacy"
        static let backupAndTransfer = "settings.backupAndTransfer"
        static let exportBackup = "settings.exportBackup"
        static let deleteAllData = "settings.deleteAllData"
    }
}
