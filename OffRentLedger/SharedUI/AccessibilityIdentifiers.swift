import Foundation

/// Accessibility identifiers, in one place.
///
/// The UI suite asserts against these constants rather than against literal strings, so renaming
/// a control breaks the compile instead of a test three weeks later. `verify_repository.py`
/// checks that every identifier declared here is used somewhere in the app, which catches the
/// other direction: a test written against an identifier nothing sets.
enum A11yID {

    // Tabs are addressed by their visible title, not by an identifier: `.tabItem` builds the
    // tab-bar button itself, and XCUITest exposes that button by label. The titles live on
    // `AppTab.title`, which is the same constant the tab bar draws.

    enum Today {
        static let root = "today.root"
        static let estimatedRentRunning = "today.estimatedRentRunning"
        static let upcomingRateChanges = "today.upcomingRateChanges"
        static let actionQueue = "today.actionQueue"
        static let emptyState = "today.emptyState"
        static let addRental = "today.addRental"
        static let map = "today.map"
        static let mapSelection = "today.map.selection"
    }

    enum Rentals {
        /// The List itself is the screen root here, so there is one identifier rather
        /// than a `root` and a `list` addressing the same view.
        static let root = "rentals.root"
        static let addRental = "rentals.addRental"
        static let searchField = "rentals.search"
        static let filterMenu = "rentals.filterMenu"
        static func row(_ id: UUID) -> String { "rentals.row.\(id.uuidString)" }
        static let jobSiteRow = "rentals.jobSite.row"
        static let jobSiteName = "rentals.jobSite.name"
        static let jobSiteSave = "rentals.jobSite.save"
    }

    enum AddRental {
        static let root = "addRental.root"
        static let equipmentName = "addRental.equipmentName"
        static let vendorPicker = "addRental.vendorPicker"
        static let newVendorName = "addRental.newVendorName"
        static let jobSitePicker = "addRental.jobSitePicker"
        static let newJobSiteName = "addRental.newJobSiteName"
        static let agreementNumber = "addRental.agreementNumber"
        static let deliveryDate = "addRental.deliveryDate"
        static let dailyRate = "addRental.dailyRate"
        static let weeklyRate = "addRental.weeklyRate"
        static let fourWeekRate = "addRental.fourWeekRate"
        static let billingBasis = "addRental.billingBasis"
        static let nextRollover = "addRental.nextRollover"
        static let expectedIncrement = "addRental.expectedIncrement"
        static let save = "addRental.save"
        static let cancel = "addRental.cancel"
        static let scanButton = "addRental.scan"
    }

    enum ItemDetail {
        static let root = "itemDetail.root"
        static let status = "itemDetail.status"
        static let estimate = "itemDetail.estimate"
        static let markDone = "itemDetail.markDone"
        static let recordConfirmation = "itemDetail.recordConfirmation"
        static let recordPickup = "itemDetail.recordPickup"
        static let attachInvoice = "itemDetail.attachInvoice"
        static let resolve = "itemDetail.resolve"
        static let reopen = "itemDetail.reopen"
        static let exportEvidence = "itemDetail.exportEvidence"
        static let timeline = "itemDetail.timeline"
        static let disclosure = "itemDetail.disclosure"
    }

    enum ContactVendor {
        static let root = "contactVendor.root"
        static let disclosure = "contactVendor.disclosure"
        static let call = "contactVendor.call"
        static let email = "contactVendor.email"
        static let openLink = "contactVendor.openLink"
        static let logAttempt = "contactVendor.logAttempt"
        static let recordConfirmation = "contactVendor.recordConfirmation"
    }

    enum Confirmation {
        static let root = "confirmation.root"
        static let disclosure = "confirmation.disclosure"
        static let number = "confirmation.number"
        static let noNumberToggle = "confirmation.noNumberToggle"
        static let representative = "confirmation.representative"
        static let method = "confirmation.method"
        static let confirmedAt = "confirmation.confirmedAt"
        static let affirmation = "confirmation.affirmation"
        static let meterReading = "confirmation.meterReading"
        static let fuelLevel = "confirmation.fuelLevel"
        static let addLocation = "confirmation.addLocation"
        static let save = "confirmation.save"
        static let validationMessage = "confirmation.validationMessage"
    }

    enum Pickup {
        static let root = "pickup.root"
        static let pickedUpAt = "pickup.pickedUpAt"
        static let observedBy = "pickup.observedBy"
        static let finalMeter = "pickup.finalMeter"
        static let finalFuel = "pickup.finalFuel"
        static let notes = "pickup.notes"
        static let save = "pickup.save"
    }

    enum Scan {
        static let root = "scan.root"
        static let reviewRoot = "scan.review.root"
        static let explanation = "scan.review.explanation"
        static let saveButton = "scan.review.save"
        static let cancelButton = "scan.review.cancel"
        static let rawTextToggle = "scan.review.rawText"
        static func field(_ field: SuggestedField) -> String { "scan.review.field.\(field.rawValue)" }
        static func toggle(_ field: SuggestedField) -> String { "scan.review.toggle.\(field.rawValue)" }
    }

    enum Audit {
        static let root = "audit.root"
        static let awaitingReview = "audit.awaitingReview"
        static let possibleMismatches = "audit.possibleMismatches"
        static let followUps = "audit.followUps"
        static let resolvedHistory = "audit.resolvedHistory"
        static let possibleVariance = "audit.possibleVariance"
        static let comparisonTable = "audit.comparisonTable"
        static let acceptMismatch = "audit.acceptMismatch"
        static let recordFollowUp = "audit.recordFollowUp"
        static let followUpReason = "audit.followUpReason"
        static let resolveInvoice = "audit.resolveInvoice"
        static let saveInvoice = "audit.saveInvoice"
        static func line(_ id: UUID) -> String { "audit.line.\(id.uuidString)" }
    }

    enum Paywall {
        static let root = "paywall.root"
        static let monthly = "paywall.monthly"
        static let annual = "paywall.annual"
        static let purchase = "paywall.purchase"
        static let restore = "paywall.restore"
        static let manage = "paywall.manage"
        static let terms = "paywall.terms"
        static let privacy = "paywall.privacy"
        static let dismiss = "paywall.dismiss"
        static let entitlementStatus = "paywall.entitlementStatus"
        static let dataReassurance = "paywall.dataReassurance"
    }

    enum Place {
        static let root = "place.root"
        static let searchField = "place.search"
        static let result = "place.result"
        static let cancel = "place.cancel"
        static let choose = "place.choose"
        static let clear = "place.clear"
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
        static let replayTour = "settings.replayTour"
    }

    enum Settings {
        static let root = "settings.root"
        static let subscription = "settings.subscription"
        static let reminders = "settings.reminders"
        static let remindersRoot = "settings.reminders.root"
        static let remindersPermission = "settings.reminders.permission"
        static let remindersEnable = "settings.reminders.enable"
        static let remindersOpenSystemSettings = "settings.reminders.openSystemSettings"
        static let remindersTest = "settings.reminders.test"
        static let remindersQuietHours = "settings.reminders.quietHours"
        static let remindersScheduled = "settings.reminders.scheduled"
        static let appearance = "settings.appearance"
        static let dataAndPrivacy = "settings.dataAndPrivacy"
        static let backupAndTransfer = "settings.backupAndTransfer"
        static let backupRoot = "settings.backup.root"
        static let privacyPolicy = "settings.privacyPolicy"
        static let terms = "settings.terms"
        static let support = "settings.support"
        static let supportRoot = "settings.support.root"
        static let supportEmail = "settings.support.email"
        static let supportWebsite = "settings.support.website"
        static let supportSearch = "settings.support.search"
        static let copyDiagnostics = "settings.support.copyDiagnostics"
        static let about = "settings.about"
        static let aboutRoot = "settings.about.root"
        static let aboutWebsite = "settings.about.website"
        static let legalWebLink = "settings.legal.webLink"
        static let versionLabel = "settings.version"
        static let exportCSV = "settings.exportCSV"
        static let exportBackup = "settings.exportBackup"
        static let importBackup = "settings.importBackup"
        static let importPreview = "settings.importPreview"
        static let deleteAllData = "settings.deleteAllData"
        static let deleteAllConfirm = "settings.deleteAllConfirm"
    }
}
