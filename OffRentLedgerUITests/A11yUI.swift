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
        static let map = "today.map"
        static let mapEmptyOverlay = "today.map.empty"
    }

    enum Rentals {
        static let root = "rentals.root"
        static let addMenu = "rentals.addMenu"
        static let addRental = "rentals.addRental"
        static let addCompany = "rentals.addCompany"
        static let addJobSite = "rentals.addJobSite"
        static let companiesLink = "rentals.companiesLink"
        static let jobSitesLink = "rentals.jobSitesLink"
        static let searchField = "rentals.search"
    }

    enum Company {
        static let root = "company.editor"
        static let pickerRoot = "company.picker"
        static let listRoot = "company.list"
        static let listAdd = "company.list.add"
        static let addNew = "company.addNew"
        static let name = "company.name"
        static let branch = "company.branch"
        static let save = "company.save"
        static let cancel = "company.cancel"
    }

    enum Jobsite {
        static let root = "jobsite.editor"
        static let pickerRoot = "jobsite.picker"
        static let listRoot = "jobsite.list"
        static let listAdd = "jobsite.list.add"
        static let addNew = "jobsite.addNew"
        static let noJobsite = "jobsite.none"
        static let map = "jobsite.map"
        static let searchField = "jobsite.search"
        static let dropPin = "jobsite.dropPin"
        static let dropPinPanel = "jobsite.dropPinPanel"
        static let panel = "jobsite.panel"
        static let name = "jobsite.name"
        static let confirm = "jobsite.confirm"
        static let cancel = "jobsite.cancel"
    }

    enum OperationsMap {
        static let root = "map.root"
        static let close = "map.close"
        static let searchField = "map.search"
        static let searchResult = "map.searchResult"
        static let legendToggle = "map.legendToggle"
        static let legend = "map.legend"
        static let detailCard = "map.detail"
        static let openRecord = "map.open"
        static let editRecord = "map.edit"
        static let addLocation = "map.addLocation"
    }

    enum AddRental {
        static let root = "addRental.root"
        static let equipmentName = "addRental.equipmentName"
        static let companyRow = "addRental.companyRow"
        static let jobSiteRow = "addRental.jobSiteRow"
        static let moreDetails = "addRental.moreDetails"
        static let missingRequirement = "addRental.missingRequirement"
        static let dailyRate = "addRental.dailyRate"
        static let save = "addRental.save"
        static let cancel = "addRental.cancel"
        static let scanButton = "addRental.scan"
    }

    enum EditRental {
        static let root = "editRental.root"
        static let save = "editRental.save"
    }

    enum ItemDetail {
        static let root = "itemDetail.root"
        static let edit = "itemDetail.edit"
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
        static let nothingFound = "scan.review.nothingFound"
        static let enterManually = "scan.review.enterManually"
        static let rescan = "scan.review.rescan"
        static let rawTextToggle = "scan.review.rawText"
    }

    enum Onboarding {
        static let welcomeRoot = "onboarding.welcome"
        static let welcomeAddRental = "onboarding.welcome.addRental"
        static let welcomeTour = "onboarding.welcome.tour"
        static let welcomeSkip = "onboarding.welcome.skip"
        static let tourRoot = "onboarding.tour"
        static let tourSkip = "onboarding.tour.skip"
        static let tourNext = "onboarding.tour.next"
        static let tourBack = "onboarding.tour.back"
        static let tourPage = "onboarding.tour.page"
        static let replayTour = "settings.replayTour"
    }

    enum Audit {
        static let root = "audit.root"
        static let possibleMismatches = "audit.possibleMismatches"
        static let possibleVariance = "audit.possibleVariance"
        static let recordFollowUp = "audit.recordFollowUp"
        static let followUpReason = "audit.followUpReason"
        static let resolveInvoice = "audit.resolveInvoice"
        static let resolveBlockedReason = "audit.resolveBlocked"
        static let editInvoice = "audit.editInvoice"
        static let acceptedConfirmation = "audit.accepted"
        static let saveInvoice = "audit.saveInvoice"
        static let lineCategory = "audit.line.category"
        static let comparisonTable = "audit.comparisonTable"
        static let awaitingReview = "audit.awaitingReview"
        static let resolvedHistory = "audit.resolvedHistory"
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
