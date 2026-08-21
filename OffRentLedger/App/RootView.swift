import SwiftData
import SwiftUI

struct RootView: View {

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearanceSetting.storageKey) private var appearance = AppearanceSetting.system

    var body: some View {
        @Bindable var router = router

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
        .task { await prepare() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // An App Intent is constructed outside the SwiftUI environment, so it parks its
            // destination in IntentRouter and this picks it up once the app is on screen.
            if let pending = IntentRouter.shared.consume() { router.handle(pending) }
            // Estimates are a function of "now": a phone left in a truck overnight comes back
            // showing yesterday's figure unless this runs.
            Task { await refresh() }
        }
    }

    @ViewBuilder
    private func sheetContent(for sheet: AppSheet) -> some View {
        switch sheet {
        case .addRental:
            AddRentalView()
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
        guard overrides.wantsSeeding else { return }
        // Only ever into a store the test asked to be fresh, so a seed cannot land on top of a
        // real user's rentals.
        guard overrides.useInMemoryStore || overrides.resetState else { return }
        if overrides.seedWalkthrough || overrides.seedFreeLimit {
            SeedFixtures.seedWalkthrough(context: context, clock: dependencies.clock)
            try? context.save()
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
        try? context.save()

        publishSnapshot(items: items)
        publishIntentIndex(items: items)
        await rescheduleReminders(items: items)
    }

    private func publishSnapshot(items: [RentalItem]) {
        let entitlement = dependencies.effectiveEntitlement
        // The widget is a Pro feature, so a free user's snapshot is cleared rather than published
        // — the widget then shows its "Pro" placeholder instead of stale real numbers.
        guard EntitlementPolicy.isAllowed(.widget, entitlement: entitlement) else {
            dependencies.snapshotPublisher.clear()
            return
        }
        let inputs = items.map { item in
            SnapshotItemInput(
                status: item.status,
                terms: item.terms,
                hasInvoiceAwaitingReview: (item.agreement?.invoices ?? [])
                    .contains { $0.reviewStatus == .notReviewed || $0.reviewStatus == .inReview }
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
        let invoice = (item.agreement?.invoices ?? [])
            .filter { $0.primaryItemID == nil || $0.primaryItemID == item.id }
            .max(by: { $0.attachedAt < $1.attachedAt })

        self.init(
            itemID: item.id,
            equipmentName: item.equipmentName,
            status: item.status,
            terms: item.terms,
            markedDoneAt: events.last { $0.type == .equipmentMarkedDone }?.timestamp,
            confirmationRecordedAt: events.last { $0.type == .vendorConfirmationRecorded }?.timestamp,
            pickupRecordedAt: events.last { $0.type == .pickupRecorded }?.timestamp,
            invoiceAttachedAt: invoice?.attachedAt,
            invoiceReviewed: invoice.map { $0.reviewStatus == .accepted || $0.reviewStatus == .followUpRecorded } ?? false,
            disputeWindowDaysOverride: item.agreement?.disputeWindowDaysOverride
        )
    }
}
