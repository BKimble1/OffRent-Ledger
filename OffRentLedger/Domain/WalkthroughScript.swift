import Foundation

/// Which part of the app a walkthrough page is about.
///
/// The tab, not a control. A coach mark pinned to a specific button breaks the moment that
/// button moves, and cannot be read by VoiceOver in any sensible order; naming the tab is
/// durable, and it is what somebody actually needs to be told — *where* the thing lives.
enum WalkthroughFocus: String, Sendable, Equatable, CaseIterable {
    case today
    case rentals
    case audit
    case settings
    case none
}

/// One page of the walkthrough.
struct WalkthroughPage: Sendable, Equatable, Identifiable {
    var id: Int
    var title: String
    var body: String
    var symbol: String
    var focus: WalkthroughFocus
}

/// The walkthrough, as data.
///
/// This replaces a guide that read the rental's status and asked the user to perform each real
/// step of the workflow — create a rental, ring the yard, record a pickup, accept an invoice —
/// before it would advance. That design had one virtue, that it could not desync from the app,
/// and three faults that outweighed it:
///
/// 1. It could not be finished without doing real work in a real store. Somebody wanting to know
///    what the app *is* had to make a record they would then have to delete.
/// 2. It could not be finished at all by somebody who does not have a machine off rent today,
///    which is most people on the day they install it.
/// 3. `Skip` was the only exit, so the guide's own progress bar was a promise it could not keep.
///
/// A page sequence advances on its own controls. It writes nothing, waits for nothing, and
/// `Finish` on the last page is a real end.
enum WalkthroughScript {

    /// Bumped only when the pages change enough that somebody who has seen the old ones should
    /// be shown the new ones. Not bumped for a typo — a walkthrough that reappears is worse than
    /// one that is slightly out of date.
    static let version = 2

    static let pages: [WalkthroughPage] = [
        WalkthroughPage(
            id: 0,
            title: "What it is costing right now",
            body: """
                Today adds up the rentals still accruing and shows one figure: estimated rent \
                running. It comes from the rates and dates you confirmed, so it is an estimate — \
                never an invoice.
                """,
            symbol: "sun.horizon",
            focus: .today
        ),
        WalkthroughPage(
            id: 1,
            title: "Every machine, and where it stands",
            body: """
                The Rentals tab lists them all. Each one carries its own state — on rent, waiting \
                on a phone call, awaiting pickup, waiting on the invoice — so you can see what \
                needs doing without opening anything.
                """,
            symbol: "shippingbox",
            focus: .rentals
        ),
        WalkthroughPage(
            id: 2,
            title: "Companies and jobsites are reusable",
            body: """
                The plus button on Rentals also creates a rental company or a jobsite on its own. \
                Add the yard once and pick it from then on; put a jobsite on the map once and \
                every rental there shows up on it.
                """,
            symbol: "building.2",
            focus: .rentals
        ),
        WalkthroughPage(
            id: 3,
            title: "You make the call",
            body: """
                When you finish with a machine you mark it done. That stops the running estimate \
                and reminds you to ring the yard. \(SharedBranding.displayName) never contacts \
                the rental company and never ends a rental for you — only the yard can do that.
                """,
            symbol: "phone.badge.waveform",
            focus: .rentals
        ),
        WalkthroughPage(
            id: 4,
            title: "Confirmation and pickup are separate",
            body: """
                The yard agreeing a stop date and the truck actually collecting are two different \
                facts, usually on two different days. Both get recorded, with whatever the yard \
                gave you: a confirmation number, a name, a time.
                """,
            symbol: "checkmark.rectangle.stack",
            focus: .rentals
        ),
        WalkthroughPage(
            id: 5,
            title: "Check the final invoice",
            body: """
                The Audit tab lays your confirmed terms next to what you were billed. A \
                difference is a prompt to look at a charge — never a claim that it is wrong.
                """,
            symbol: "checklist",
            focus: .audit
        ),
        WalkthroughPage(
            id: 6,
            title: "It all stays on this iPhone",
            body: """
                No account, no server, no analytics. Documents are read on the device. Settings \
                is where you back everything up, move it to a new phone, or delete the lot.
                """,
            symbol: "lock.iphone",
            focus: .settings
        ),
    ]

    static var count: Int { pages.count }

    static func page(at index: Int) -> WalkthroughPage? {
        pages.indices.contains(index) ? pages[index] : nil
    }

    static func isLast(_ index: Int) -> Bool { index >= count - 1 }
    static func isFirst(_ index: Int) -> Bool { index <= 0 }

    /// What the forward button says. `Finish` on the last page, and it means finish: the caller
    /// records the version and dismisses, with nothing else to tap.
    static func forwardTitle(at index: Int) -> String {
        isLast(index) ? "Finish" : "Next"
    }

    /// Whether somebody who last completed `seenVersion` should be shown this again.
    ///
    /// A user who has never seen it (`nil`) should. A user who saw version 2 should not see
    /// version 2 again, however many times they relaunch.
    static func shouldPresent(seenVersion: Int?) -> Bool {
        guard let seenVersion else { return true }
        return seenVersion < version
    }
}
