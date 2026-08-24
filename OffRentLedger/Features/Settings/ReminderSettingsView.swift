import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// Reminders: whether iOS will deliver them, what to be reminded about, when, and what is
/// actually scheduled right now.
///
/// The old version was a stack of steppers with no answer to the only question anybody asks of a
/// reminders screen — *is this working?* Permission state was invisible until a toggle failed,
/// nothing showed what had been scheduled, and there was no way to see a reminder arrive without
/// waiting days for one. All three are on this screen now.
struct ReminderSettingsView: View {

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @Query private var items: [RentalItem]

    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var testMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                PermissionCard(
                    status: status,
                    scheduledCount: plan.count,
                    testMessage: testMessage,
                    onEnable: { Task { await requestPermission() } },
                    onOpenSettings: openSystemSettings,
                    onTest: { Task { await sendTestReminder() } }
                )
                KindsCard(dependencies: dependencies, router: router, onChanged: refreshStatus)
                TimingCard(dependencies: dependencies)
                scheduled
            }
            .padding(.horizontal, Space.comfortable)
            .padding(.top, Space.base)
            .padding(.bottom, Space.screenBottom)
        }
        .offRentScreen()
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(A11yID.Settings.remindersRoot)
        .task { await refreshStatusAsync() }
        // Somebody who leaves to change the iOS switch has to come back to a screen that agrees
        // with what they just did.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshStatus() }
        }
    }

    // MARK: - What is scheduled

    /// Recomputed from the same planner the app schedules with, so this cannot drift from what
    /// iOS actually holds. Showing the OS's own pending requests instead would show opaque
    /// identifiers; showing the plan shows sentences.
    private var plan: [PlannedReminder] {
        let settings = dependencies.reminderSettings
        guard !settings.enabledKinds.isEmpty else { return [] }
        return ReminderPlanner.plan(
            contexts: items.map { ReminderContext(item: $0) },
            settings: settings,
            entitlement: dependencies.effectiveEntitlement,
            now: dependencies.clock.now,
            calendar: dependencies.clock.calendar
        )
    }

    private var scheduled: some View {
        VStack(alignment: .leading, spacing: Space.base) {
            CardHeader(
                title: "Scheduled now",
                subtitle: plan.isEmpty
                    ? "Nothing is waiting to fire. Reminders appear here as rentals reach a stage that needs one."
                    : "\(plan.count) reminder\(plan.count == 1 ? "" : "s") waiting. Tap one to open the rental."
            )

            if !plan.isEmpty {
                ListGroup {
                    ForEach(Array(plan.prefix(12).enumerated()), id: \.element.id) { index, reminder in
                        if index > 0 { RowDivider() }
                        NavigationLink(value: RentalDestination.item(id: reminder.itemID)) {
                            NavigationRow(
                                title: reminder.title,
                                subtitle: Formatters.dateAndTime(reminder.fireDate),
                                symbol: "bell",
                                tint: Palette.accent
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                if plan.count > 12 {
                    Text("and \(plan.count - 12) more")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard(padding: Space.base)
        .accessibilityIdentifier(A11yID.Settings.remindersScheduled)
    }

    // MARK: - Permission

    private func refreshStatus() {
        Task { await refreshStatusAsync() }
    }

    private func refreshStatusAsync() async {
        status = await dependencies.notifications.authorizationStatus()
    }

    private func requestPermission() async {
        let current = await dependencies.notifications.authorizationStatus()
        if current == .notDetermined {
            _ = await dependencies.notifications.requestAuthorization()
        } else if current == .denied {
            openSystemSettings()
        }
        await refreshStatusAsync()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func sendTestReminder() async {
        let sent = await dependencies.notifications.scheduleTestReminder(after: TestReminder.delay)
        testMessage = sent
            ? "A test reminder will arrive in about \(Int(TestReminder.delay)) seconds. Leave this screen to see it."
            : "iOS is not allowing reminders yet, so there was nothing to send."
    }
}

// MARK: - Permission card

private struct PermissionCard: View {
    let status: UNAuthorizationStatus
    let scheduledCount: Int
    let testMessage: String?
    let onEnable: () -> Void
    let onOpenSettings: () -> Void
    let onTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.base) {
            CardHeader(title: headline, subtitle: detail, symbol: symbol, tint: tint)

            switch status {
            case .notDetermined:
                Button("Turn on reminders", action: onEnable)
                    .buttonStyle(.offRentPrimary)
                    .accessibilityIdentifier(A11yID.Settings.remindersEnable)
            case .denied:
                Button("Open iOS Settings", action: onOpenSettings)
                    .buttonStyle(.offRentPrimary)
                    .accessibilityIdentifier(A11yID.Settings.remindersOpenSystemSettings)
            default:
                Button("Send me a test reminder", action: onTest)
                    .buttonStyle(.offRentSecondary)
                    .accessibilityIdentifier(A11yID.Settings.remindersTest)
            }

            if let testMessage {
                InlineAlert(message: testMessage, kind: .info)
            }

            Text(AppCopy.notificationsExplanation)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard()
        .accessibilityIdentifier(A11yID.Settings.remindersPermission)
    }

    private var headline: String {
        switch status {
        case .notDetermined: "Reminders are off"
        case .denied: "iOS is blocking reminders"
        default: scheduledCount == 0 ? "Reminders are on" : "Reminders are on · \(scheduledCount) waiting"
        }
    }

    private var detail: String {
        switch status {
        case .notDetermined:
            "Nothing has been asked for yet. Turning these on lets \(AppConfiguration.displayName) tell you when a rate is about to change or a confirmation is still missing."
        case .denied:
            "Notifications are switched off for \(AppConfiguration.displayName) in iOS Settings. Nothing will arrive until you turn them back on there."
        default:
            "iOS will deliver these. They are scheduled on this iPhone — there is no server, so they arrive whether or not you have signal."
        }
    }

    private var symbol: String {
        switch status {
        case .denied: "bell.slash"
        case .notDetermined: "bell.badge"
        default: "bell"
        }
    }

    private var tint: Color {
        switch status {
        case .denied: Palette.attention
        case .notDetermined: .secondary
        default: Palette.settled
        }
    }
}

// MARK: - What to be reminded about

private struct KindsCard: View {
    @Bindable var dependencies: AppDependencies
    let router: AppRouter
    let onChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.base) {
            CardHeader(title: "Remind me about")
            ListGroup {
                ForEach(Array(ReminderKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { RowDivider() }
                    row(kind)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard(padding: Space.base)
    }

    private func row(_ kind: ReminderKind) -> some View {
        let locked = kind.requiresPro && !dependencies.effectiveEntitlement.isPro
        return Toggle(isOn: binding(for: kind, locked: locked)) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.tight) {
                    Text(kind.displayName).font(Typography.rowTitle)
                    if locked {
                        Label("Pro", systemImage: "lock.fill")
                            .font(Typography.micro)
                            .foregroundStyle(Palette.accent)
                    }
                }
                Text(kind.explanation)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Space.comfortable)
        .padding(.vertical, Space.snug)
        .accessibilityIdentifier("settings.reminders.kind.\(kind.rawValue)")
    }

    private func binding(for kind: ReminderKind, locked: Bool) -> Binding<Bool> {
        Binding(
            get: { dependencies.reminderSettings.isEnabled(kind) },
            set: { enabled in
                guard !locked else {
                    router.presentedSheet = .paywall(reason: .advancedReminders)
                    return
                }
                Task { await setEnabled(enabled, for: kind) }
            }
        )
    }

    private func setEnabled(_ enabled: Bool, for kind: ReminderKind) async {
        if enabled {
            // Permission is requested here and nowhere else — only after the user has actually
            // asked for a reminder. An app that prompts on launch gets denied on launch.
            let status = await dependencies.notifications.authorizationStatus()
            if status == .notDetermined {
                let granted = await dependencies.notifications.requestAuthorization()
                onChanged()
                guard granted else { return }
            } else if status == .denied {
                onChanged()
                return
            }
            dependencies.reminderSettings.enabledKinds.insert(kind)
        } else {
            dependencies.reminderSettings.enabledKinds.remove(kind)
        }
        onChanged()
    }
}

// MARK: - When they arrive

private struct TimingCard: View {
    @Bindable var dependencies: AppDependencies

    var body: some View {
        VStack(alignment: .leading, spacing: Space.base) {
            CardHeader(title: "When they arrive")

            ListGroup {
                if dependencies.reminderSettings.isEnabled(.rateRollover) {
                    stepper(
                        "Before a rate change",
                        value: $dependencies.reminderSettings.rolloverLeadHours,
                        range: 0...168, step: 6,
                        format: { $0 == 0 ? "At the change" : "\($0)h before" }
                    )
                    RowDivider()
                }
                if dependencies.reminderSettings.isEnabled(.confirmationOutstanding) {
                    stepper(
                        "After marking done",
                        value: $dependencies.reminderSettings.confirmationNagAfterHours,
                        range: 1...72, step: 1,
                        format: { "\($0)h later" }
                    )
                    RowDivider()
                }
                stepper(
                    "Day reminders arrive around",
                    value: $dependencies.reminderSettings.preferredHour,
                    range: 5...21, step: 1,
                    format: { Self.hourLabel($0) }
                )
                RowDivider()
                Toggle(isOn: $dependencies.reminderSettings.quietHoursEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quiet hours").font(Typography.rowTitle)
                        Text("Nothing fires between these times.")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, Space.comfortable)
                .padding(.vertical, Space.snug)
                .accessibilityIdentifier(A11yID.Settings.remindersQuietHours)

                if dependencies.reminderSettings.quietHoursEnabled {
                    RowDivider()
                    stepper(
                        "Quiet from",
                        value: $dependencies.reminderSettings.quietHoursStart,
                        range: 0...23, step: 1,
                        format: { Self.hourLabel($0) }
                    )
                    RowDivider()
                    stepper(
                        "Quiet until",
                        value: $dependencies.reminderSettings.quietHoursEnd,
                        range: 0...23, step: 1,
                        format: { Self.hourLabel($0) }
                    )
                }
            }

            Text("""
                A reminder that would land inside your quiet hours moves earlier, to just before \
                they start — not later. A warning that arrives after the thing it warned about is \
                worse than one that arrives a few hours early.
                """)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            CardHeader(title: "Invoice review window")
            ListGroup {
                stepper(
                    "Default window",
                    value: $dependencies.reminderSettings.defaultDisputeWindowDays,
                    range: 0...90, step: 1,
                    format: { $0 == 0 ? "Off" : "\($0) days" }
                )
            }
            Text("""
                This is a number you enter, not something \(AppConfiguration.displayName) knows. \
                Check each vendor's own terms — you can override it per agreement.
                """)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard(padding: Space.base)
    }

    private func stepper(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        format: @escaping (Int) -> String
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title).font(Typography.rowTitle)
                Spacer(minLength: Space.snug)
                Text(format(value.wrappedValue))
                    .font(Typography.rowDetail.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Space.comfortable)
        .padding(.vertical, Space.snug)
        .accessibilityValue(format(value.wrappedValue))
    }

    /// "8am", "9pm" — a 12-hour label, because a stepper showing "21:00" reads as a duration.
    static func hourLabel(_ hour: Int) -> String {
        let clamped = min(23, max(0, hour))
        switch clamped {
        case 0: return "midnight"
        case 12: return "noon"
        case 1...11: return "\(clamped)am"
        default: return "\(clamped - 12)pm"
        }
    }
}
