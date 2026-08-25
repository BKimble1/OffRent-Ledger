import Foundation

/// Everything the accept decision depends on, gathered into one value.
struct InvoiceAcceptanceInput: Sendable, Equatable {
    /// Discrepancies already written down against this invoice that are still open.
    var openRecordedDiscrepancies: Int
    /// Findings on the screen right now that nothing has been recorded against.
    var unaddressedFindings: Int
    /// How many lines the user entered.
    var lineCount: Int
    var invoiceTotal: Decimal
    var currentStatus: InvoiceReviewStatus

    init(
        openRecordedDiscrepancies: Int,
        unaddressedFindings: Int,
        lineCount: Int,
        invoiceTotal: Decimal,
        currentStatus: InvoiceReviewStatus
    ) {
        self.openRecordedDiscrepancies = openRecordedDiscrepancies
        self.unaddressedFindings = unaddressedFindings
        self.lineCount = lineCount
        self.invoiceTotal = invoiceTotal
        self.currentStatus = currentStatus
    }
}

/// Why accepting is not available, and what the user can do instead.
enum InvoiceAcceptanceBlock: Error, Sendable, Equatable {
    /// Nothing was entered: no lines and no total. There is no invoice here to be satisfied by.
    case nothingRecorded
    /// Possible mismatches are still open. They are resolved on this screen, not elsewhere.
    case openFindings(count: Int)
    /// Already accepted. Not an error — the button simply has nothing left to do.
    case alreadyAccepted

    /// What the screen says under the disabled control. Specific in every case: "you cannot do
    /// that" with no reason is the thing this type exists to prevent.
    var explanation: String {
        switch self {
        case .nothingRecorded:
            return """
                This invoice has no total and no lines yet, so there is nothing to compare it \
                against. Add what the vendor billed and it can be reviewed.
                """
        case let .openFindings(count):
            return count == 1
                ? "One possible mismatch above is still open. Accept it or record a follow-up, then this becomes available."
                : "\(count) possible mismatches above are still open. Accept them or record a follow-up, then this becomes available."
        case .alreadyAccepted:
            return "You accepted this invoice already. Reopen the rental if you need to change that."
        }
    }

    /// The route out. `nil` when the fix is on the screen the user is already looking at.
    var editRouteTitle: String? {
        switch self {
        case .nothingRecorded: "Edit invoice"
        case .openFindings, .alreadyAccepted: nil
        }
    }
}

/// Whether this invoice can be accepted, and if not, why not.
///
/// Split out of the view because the screenshot showed the failure mode a view cannot be trusted
/// with: a bright, enabled `Accept this invoice` that produced nothing at all when tapped. The
/// old code decided inside the button's action, so "refused" and "accepted with no visible
/// effect" looked identical from outside — and one of them was a silent no-op.
///
/// Here the decision is a value. The button asks for it *before* it draws itself, so a blocked
/// invoice is disabled with its reason printed underneath, and a ready one is a control that is
/// going to do something when it is pressed.
enum InvoiceAcceptance {

    static func decide(_ input: InvoiceAcceptanceInput) -> Result<Void, InvoiceAcceptanceBlock> {
        if input.currentStatus == .accepted {
            return .failure(.alreadyAccepted)
        }
        let open = input.openRecordedDiscrepancies + input.unaddressedFindings
        if open > 0 {
            return .failure(.openFindings(count: open))
        }
        // A zero-dollar invoice with lines is a real thing — a vendor confirming there is nothing
        // further to pay — and it is accepted. A zero-dollar invoice with *no* lines is an empty
        // record, and accepting it would mean the user affirmed they checked something that is
        // not there.
        if input.lineCount == 0, input.invoiceTotal == .zero {
            return .failure(.nothingRecorded)
        }
        return .success(())
    }

    static func canAccept(_ input: InvoiceAcceptanceInput) -> Bool {
        if case .success = decide(input) { return true }
        return false
    }

    /// What the primary control reads. Never a lie about what pressing it will do.
    static func actionTitle(_ input: InvoiceAcceptanceInput) -> String {
        input.currentStatus == .accepted ? "Accepted" : "Accept this invoice"
    }

    /// The line shown after a successful acceptance.
    ///
    /// In the user's records, not at the yard. Closing a rental out is an act between a
    /// contractor and a rental company, and this app does not talk to the rental company — §1.1
    /// is the reason it exists in the shape it does. What actually happened is that the user
    /// finished reviewing an invoice and their own record moved to Resolved, which is what the
    /// sentence says.
    ///
    /// The old wording is in the banned list now. It reached a shipped screen, which is what
    /// that list is for.
    static let confirmation = "Invoice accepted. This rental is now resolved in your records."
}
