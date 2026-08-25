import SwiftData
import SwiftUI

struct RootView: View {

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(OnboardingState.self) private var onboarding
    @AppStorage(AppearanceSetting.storageKey) private var appearance = AppearanceSetting.system

    /// Guards the once-per-launch check below. Without it, every `.task` re-entry would
    /// re-present a walkthrough the user has just dismissed.
    /// What the welcome screen asked for, held until its cover has actually closed.
    private enum WelcomeAction { case addRental, takeTour }
    @State private var pendingWelcomeAction: WelcomeAction?
    @State private var hasCheckedWalkthrough = false

    var body: some View {
        @Bindable var router = router
        @Bindable var onboarding = onboarding

        // The classic `.tabItem` form rather than iOS 18's `Tab` builder.
        //
        // `Tab` produces `TabContent`, not a `View`, and `TabContent` does not accept view
        // modifiers — an accessibility identifier on a `Tab` does not compile. `.tabItem` does
        // accept them, and the UI suite addresses tabs by their visible title anyway, which is
        // what XCUITest exposes on a tab bar button regardless of how the tab was built.
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: router.path(for: .today)) { TodayView() }
                .tabItem { Label(AppTab.today.title, systemImage: AppTab.today.symbolName) }
                .tag(AppTab.today)

            NavigationStack(path: router.path(for: .rentals)) { RentalsView() }
                .tabItem { Label(AppTab.rentals.title, systemImage: AppTab.rentals.symbolName) }
                .tag(AppTab.rentals)

            NavigationStack(path: router.path(for: .audit)) { AuditView() }
                .tabItem { Label(AppTab.audit.title, systemImage: AppTab.audit.symbolName) }
                .tag(AppTab.audit)

            NavigationStack(path: router.path(for: .settings)) { SettingsView() }
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.symbolName) }
                .tag(AppTab.settings)
        }
        .tint(Palette.accent)
        .preferredColorScheme(AppearanceSetting.colorScheme(for: appearance))
        .sheet(item: $router.presentedSheet) { sheet in
            sheetContent(for: sheet)
        }
        // The welcome covers the shell rather than replacing it, so dismissing it reveals an app
        // already loaded rather than mounting one.
        //
        // Its two actions do *not* present anything from inside the closure. Dismissing this
        // cover and presenting a sheet — or a second cover — in one state update asks SwiftUI to
        // unwind two presentations in one turn of the run loop, which it does not reliably do;
        // `CompanyPickerView` learned that the hard way and parks its result the same way. Here
        // the closure records what was asked for, and `.onChange` acts on it once the cover has
        // actually gone. Both buttons are the only two things a new user can do, and a dropped
        // presentation leaves them on an empty Rentals tab having tapped a button that appeared
        // to do nothing.
        .fullScreenCover(isPresented: .constant(onboarding.shouldShowWelcome)) {
            WelcomeView(
                onAddRental: {
                    pendingWelcomeAction = .addRental
                    onboarding.markWelcomed()
                    onboarding.markTourSeen()
                },
                onTakeTour: {
                    pendingWelcomeAction = .takeTour
                    onboarding.markWelcomed()
                },
                onSkip: {
                    onboarding.markWelcomed()
                    onboarding.markTourSeen()
                }
            )
        }
        .onChange(of: onboarding.shouldShowWelcome) { _, showing in
            guard !showing, let action = pendingWelcomeAction else { return }
            pendingWelcomeAction = nil
            switch action {
            case .addRental:
                router.selectedTab = .rentals
                router.presentedSheet = .addRental
            case .takeTour:
                onboarding.startTour()
            }
        }
        // Finish and Skip do the same thing here: record the version and dismiss. `markTourSeen`
        // sets `isShowingTour` to false itself, so the cover closes on the same run loop as the
        // tap — there is nothing else for the user to dismiss, which is what §10 asks for.
        .fullScreenCover(isPresented: $onboarding.isShowingTour) {
            WalkthroughView(
                onFinish: { finishWalkthrough() },
                onSkip: { finishWalkthrough() }
            )
        }
        .task { await prepare() }
        // §10: re-present only when the app intentionally advances the walkthrough version.
        //
        // A returning user who completed version 1 sees version 2 once, and then never again;
        // somebody who has not yet been welcomed sees the welcome first and reaches the
        // walkthrough through it. `markTourSeen` stamps the current version either way, so a
        // relaunch cannot bring it back.
        .task {
            guard !hasCheckedWalkthrough else { return }
            hasCheckedWalkthrough = true
            guard !onboarding.shouldShowWelcome, onboarding.shouldPresentTour else { return }
            onboarding.startTour()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // An App Intent is constructed outside the SwiftUI environment, so it parks its
            // destination in IntentRouter and this picks it up once the app is on screen.
            if let pending = IntentRouter.shared.consume() { router.handle(pending) }
            // Estimates are a function of "now": a phone left in a truck overnight comes back
            // showing yesterday's figure unless this runs.
            Task { await refresh() }
        }
        .onChange(of: dependencies.derivedStateGeneration) { _, _ in
            // A screen has just written something the estimates, the widget, the Shortcuts index
            // or the reminders are derived from. Recomputing here rather than in that screen
            // keeps one path: the same four things are rebuilt from scratch whether the trigger
            // was a save, a launch or a return to the foreground.
            Task { await refresh() }
        }
    }

    /// Ends the walkthrough and puts the user where it said it would: Today.
    private func finishWalkthrough() {
        onboarding.markTourSeen()
        router.selectedTab = .today
    }

    @ViewBuilder
    private func sheetContent(for sheet: AppSheet) -> some View {
        switch sheet {
        case .addRental:
            AddRentalView()
        case .scanRental:
            AddRentalView(startScanning: true)
        case let .recordConfirmation(itemID):
            RecordConfirmationSheet(itemID: itemID)
        case let .recordPickup(itemID):
            RecordPickupSheet(itemID: itemID)
        case let .attachInvoice(itemID):
            AttachInvoiceSheet(itemID: itemID)
        case let .paywall(reason):
            PaywallView(reason: reason)
        }
    }

    // MARK: - Lifecycle work

    private func prepare() async {
        seedIfRequested()
        await refresh()
    }

    private func seedIfRequested() {
        #if DEBUG
        let overrides = AppDependencies.testOverrides()
        // Only ever a store the test asked to be fresh, so neither the wipe nor the seed can
        // land on a real user's rentals.
        guard overrides.useInMemoryStore || overrides.resetState else { return }
        // The wipe happens whether or not a fixture follows, because a scenario that asks for a
        // fresh store and seeds nothing is asking to start from nothing. Before this,
        // `-offrent-reset-state` deleted precisely nothing, and every on-disk scenario inherited
        // whatever the last one left behind.
        if overrides.resetState { SeedFixtures.wipe(context: context) }
        if overrides.seedWalkthrough || overrides.seedFreeLimit {
            SeedFixtures.seedWalkthrough(context: context, clock: dependencies.clock)
            PersistentStore.saveDerived(context, describing: "the walkthrough fixtures")
        }
        #endif
    }

    /// Recomputes the cached estimates, republishes the widget snapshot and re-plans reminders.
    ///
    /// All three are derived state. Recomputing them from scratch on foreground and after every
    /// mutation is what keeps them from drifting; there is no incremental path to get wrong.
    private func refresh() async {
        let workflow = RentalWorkflowService(context: context, clock: dependencies.clock)
        guard let items = try? context.fetch(StoreQueries.allItems()) else { return }
        workflow.refreshEstimates(for: items)
        PersistentStore.saveDerived(context, describing: "the cached estimates")

        publishSnapshot(items: items)
        publishIntentIndex(items: items)
        await rescheduleReminders(items: items)
    }

    private func publishSnapshot(items: [RentalItem]) {
        let entitlement = dependencies.effectiveEntitlement
        // The widget is a Pro feature, so a free user's snapshot is withheld rather than
        // published. `withhold`, not `clear`: clearing produced a widget that read "No rentals
        // yet" on a phone with four machines on rent, which is the app misreporting the user's
        // own data back to them rather than saying the feature is behind a subscription.
        guard EntitlementPolicy.isAllowed(.widget, entitlement: entitlement) else {
            dependencies.snapshotPublisher.withhold()
            return
        }
        var inputs: [SnapshotItemInput] = []
        for item in items {
            let invoices: [VendorInvoice] = item.agreement?.invoices ?? []
            var awaitingReview = false
            for invoice in invoices {
                let status: InvoiceReviewStatus = invoice.reviewStatus
                if status == .notReviewed || status == .inReview {
                    awaitingReview = true
                    break
                }
            }
            inputs.append(
                SnapshotItemInput(
                    status: item.status,
                    terms: item.terms,
                    hasInvoiceAwaitingReview: awaitingReview
                )
            )
        }
        dependencies.snapshotPublisher.publish(
            SnapshotBuilder.build(
                items: inputs, now: dependencies.clock.now, calendar: dependencies.clock.calendar
            )
        )
    }

    /// Publishes the open-item list Shortcuts picks from. Machine and vendor only.
    private func publishIntentIndex(items: [RentalItem]) {
        let open = items.filter(\.status.isOpen)
        guard !open.isEmpty else { return IntentItemIndex.clear() }
        IntentItemIndex.publish(
            open.map {
                IntentItemIndex.Entry(
                    id: $0.id,
                    equipmentName: $0.equipmentName,
                    vendorName: $0.agreement?.vendor?.name ?? "Rental company"
                )
            }
        )
    }

    private func rescheduleReminders(items: [RentalItem]) async {
        let settings = dependencies.reminderSettings
        guard !settings.enabledKinds.isEmpty else {
            await dependencies.notifications.cancelAll()
            return
        }
        let contexts = items.map { ReminderContext(item: $0) }
        let planned = ReminderPlanner.plan(
            contexts: contexts,
            settings: settings,
            entitlement: dependencies.effectiveEntitlement,
            now: dependencies.clock.now,
            calendar: dependencies.clock.calendar
        )
        await dependencies.notifications.synchronise(to: planned)
    }
}

extension ReminderContext {
    /// Builds the planner's input from a stored item.
    init(item: RentalItem) {
        let events = item.sortedEvents
        let invoice: VendorInvoice? = item.latestInvoice

        // Each timestamp is its own annotated local rather than a `.last { }?.timestamp` inside
        // the argument list: three trailing-closure searches plus an optional `.map` in one
        // initialiser call is the shape the type checker gives up on.
        let markedDoneAt: Date? = events.last { $0.type == .equipmentMarkedDone }?.timestamp
        let confirmedAt: Date? = events.last { $0.type == .vendorConfirmationRecorded }?.timestamp
        let pickedUpAt: Date? = events.last { $0.type == .pickupRecorded }?.timestamp

        var invoiceReviewed = false
        if let invoice {
            let status: InvoiceReviewStatus = invoice.reviewStatus
            invoiceReviewed = status == .accepted || status == .followUpRecorded
        }

        self.init(
            itemID: item.id,
            equipmentName: item.equipmentName,
            status: item.status,
            terms: item.terms,
            markedDoneAt: markedDoneAt,
            confirmationRecordedAt: confirmedAt,
            pickupRecordedAt: pickedUpAt,
            invoiceAttachedAt: invoice?.attachedAt,
            invoiceDate: invoice?.receivedDate,
            invoiceReviewed: invoiceReviewed,
            disputeWindowDaysOverride: item.agreement?.disputeWindowDaysOverride
        )
    }
}
