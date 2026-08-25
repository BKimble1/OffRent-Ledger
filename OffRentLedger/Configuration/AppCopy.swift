import Foundation

/// User-facing text whose exact wording is a product requirement rather than a style choice.
///
/// Anything in here is load-bearing: it is the difference between a ledger and a claim the app
/// cannot support. `scripts/verify_repository.py` checks the banned phrasing list against the
/// whole repository, and `OffRentLedgerTests/CopyTests` asserts the required strings are present.
enum AppCopy {

    // MARK: - The disclosure

    /// The sentence the product exists to keep true. Rendered on every screen that could be read
    /// as the app doing the contacting.
    static let offRentDisclosure = """
        \(AppConfiguration.displayName) does not notify the rental company or end your rental. \
        Contact the vendor directly and obtain its confirmation number.
        """

    static let offRentDisclosureShort =
        "\(AppConfiguration.displayName) does not contact your vendor."

    /// Shown under the Mark-equipment-done action, before anything moves.
    static let markDoneExplanation = """
        Marking this done moves it to Contact Vendor and stops the running estimate. It does not \
        tell the rental company anything.
        """

    static let confirmationAffirmation =
        "I contacted the rental company about this equipment."

    static let confirmationAffirmationHint = """
        Tick this only if you actually spoke to, emailed or messaged the vendor. \
        \(AppConfiguration.displayName) records what you tell it; it has no way to check.
        """

    // MARK: - Estimates

    static let estimateQualifier = "Estimate"

    static let estimateExplanation = """
        Estimated from the rates and dates you confirmed. It is not an invoice and not a statement \
        of what you owe.
        """

    static let basedOnConfirmedTerms = "Based on the terms you confirmed"

    // MARK: - Invoice review

    static let possibleMismatchExplanation = """
        A possible mismatch means this invoice differs from the terms you confirmed. It is not a \
        determination that any charge is incorrect. Check your agreement and talk to the vendor.
        """

    static let reviewThisCharge = "Review this charge"

    // MARK: - Scanning

    static let scanReviewExplanation = """
        Nothing is saved until you tap Save. Check every value against the document — text read \
        from a scan can be wrong.
        """

    static let ocrLocalOnly = """
        Scanning and text recognition happen entirely on this iPhone. No image or text leaves the \
        device.
        """

    static let lowConfidenceExplanation = """
        These were read with lower confidence and are not selected. Tick the ones you want after \
        checking them.
        """

    // MARK: - Evidence

    static let checksumExplanation = """
        File checksum, included as an integrity aid so you can tell whether an attachment has \
        changed. It is not a chain of custody and proves nothing about where a file came from.
        """

    // MARK: - Privacy

    static let localOnlySummary = """
        Everything you enter stays on this iPhone. \(AppConfiguration.displayName) has no account, \
        no server and no analytics, and it does not send your rentals, documents or photos anywhere.
        """

    static let locationExplanation = """
        Used once, when you tap Add current location, to record where equipment was. \
        \(AppConfiguration.displayName) never tracks you in the background and keeps no route history.
        """

    static let notificationsExplanation = """
        Reminders are scheduled on this iPhone by \(AppConfiguration.displayName) itself. There is \
        no server, so no reminder can arrive because something changed somewhere else.
        """

    // MARK: - Subscription

    static let entitlementLossReassurance = """
        Your existing rentals, photos, documents and exports stay exactly as they are. Without Pro \
        you can still edit, resolve, export and delete everything — you just cannot open a new \
        rental beyond the free limit.
        """

    static let subscriptionTerms = """
        Payment is charged to your Apple Account at confirmation. The subscription renews \
        automatically unless you turn off auto-renew at least 24 hours before the period ends. \
        Manage or cancel it in your Apple Account settings.
        """

    // MARK: - Legal

    static let generalDisclaimer = """
        \(AppConfiguration.displayName) is a record-keeping tool. It does not provide legal, \
        accounting, insurance or contract advice, and your rental company's own agreement governs \
        your rental. You are responsible for reviewing anything you generate here before relying \
        on it or sending it to anyone.
        """

    /// The Settings footer under the auto-fill toggle.
    ///
    /// Says what "automatically" does *not* mean, because that is the part worth knowing: a scan
    /// the app was unsure about still stops, and nothing reaches the store until the user saves
    /// the rental themselves. §7 spends its length on not applying a value nobody looked at, and
    /// an opt-in that quietly relaxed that would undo it.
    static let autoFillScansExplanation = """
        On to begin with. A scan that reads at least three fields clearly and leaves nothing \
        uncertain goes straight into the form; anything the app was unsure about still stops for \
        you to check, and nothing is saved until you tap Save on the rental. Switch this off and \
        every scan opens a review screen first.
        """

    /// The footer under "Delete this rental".
    ///
    /// Says what deleting does *not* do, because on this app that is the load-bearing half:
    /// removing your own record is not an act at the rental yard, and §1.1 forbids implying it.
    static let deleteRentalExplanation = """
        Removes it from this iPhone completely. The rental company is not told anything, and \
        nothing about your agreement with them changes.
        """
}
