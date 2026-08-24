import SwiftData
import SwiftUI

struct SettingsView: View {

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.roomy) {
                planPanel

                ListGroup {
                    settingsRow(
                        .reminders, title: "Reminders", symbol: "bell",
                        identifier: A11yID.Settings.reminders
                    )
                    RowDivider()
                    settingsRow(
                        .appearance, title: "Appearance", symbol: "textformat.size",
                        identifier: A11yID.Settings.appearance
                    )
                    RowDivider()
                    settingsRow(
                        .dataAndPrivacy, title: "Data and privacy", symbol: "lock.shield",
                        subtitle: "Everything stays on this iPhone",
                        identifier: A11yID.Settings.dataAndPrivacy
                    )
                }

                VStack(alignment: .leading, spacing: Space.base) {
                    SectionHeader(title: "Legal and support")
                    ListGroup {
                        settingsRow(
                            .privacyPolicy, title: "Privacy Policy", symbol: "hand.raised",
                            identifier: A11yID.Settings.privacyPolicy
                        )
                        RowDivider()
                        settingsRow(
                            .terms, title: "Terms of Use", symbol: "doc.text",
                            identifier: A11yID.Settings.terms
                        )
                        RowDivider()
                        settingsRow(
                            .support, title: "Support", symbol: "questionmark.circle",
                            identifier: A11yID.Settings.support
                        )
                        RowDivider()
                        settingsRow(
                            .about, title: "About", symbol: "info.circle",
                            identifier: A11yID.Settings.about
                        )
                    }
                }

                VStack(alignment: .leading, spacing: Space.hair) {
                    Text("\(AppConfiguration.displayName) \(AppConfiguration.versionAndBuild)")
                        .accessibilityIdentifier(A11yID.Settings.versionLabel)
                    Text(AppConfiguration.poweredByLine)
                }
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.tight)
            }
            .padding(.horizontal, Space.comfortable)
            .padding(.top, Space.screenTop)
            .padding(.bottom, Space.screenBottom)
        }
        .offRentScreen()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .accessibilityIdentifier(A11yID.Settings.root)
        .offRentNavigationDestinations()
    }

    /// The plan, stated rather than tucked into a trailing grey word on a list row.
    private var planPanel: some View {
        let isPro: Bool = dependencies.effectiveEntitlement.isPro
        return NavigationLink(value: SettingsDestination.subscription) {
            VStack(alignment: .leading, spacing: Space.base) {
                Text("Your plan")
                    .font(Typography.micro.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(Palette.onGraphiteSecondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(isPro ? "\(AppConfiguration.displayName) Pro" : "Free plan")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Palette.onGraphite)
                    Spacer(minLength: Space.snug)
                    Text(isPro ? "Manage" : "See Pro")
                        .font(Typography.caption.weight(.semibold))
                        .foregroundStyle(Palette.onGraphite)
                        .padding(.horizontal, Space.base)
                        .padding(.vertical, Space.tight + 1)
                        .background(Palette.onGraphite.opacity(0.14), in: Capsule())
                }
                Text(
                    isPro
                        ? "Unlimited open rentals, invoice audit and evidence export."
                        : "One open rental at a time. Everything you have already entered stays."
                )
                .font(Typography.caption)
                .foregroundStyle(Palette.onGraphiteSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .offRentPanel(padding: Space.roomy - 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11yID.Settings.subscription)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Subscription. \(isPro ? "Pro" : "Free")")
    }

    private func settingsRow(
        _ destination: SettingsDestination, title: String, symbol: String,
        subtitle: String? = nil, identifier: String
    ) -> some View {
        NavigationLink(value: destination) {
            NavigationRow(title: title, subtitle: subtitle, symbol: symbol)
        }
        .buttonStyle(.plain)
        .minimumTapTarget()
        .accessibilityIdentifier(identifier)
    }
}

struct SubscriptionSettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var restoreMessage: String?

    var body: some View {
        List {
            Section {
                let entitlement = dependencies.effectiveEntitlement
                DetailRow(label: "Plan", value: entitlement.isPro ? "Pro" : "Free")
                DetailRow(label: "Status", value: entitlement.reason.displayName)
                if let date = entitlement.renewalOrExpirationDate {
                    DetailRow(
                        label: entitlement.isPro ? "Renews or expires" : "Expired",
                        value: Formatters.mediumDate(date)
                    )
                }
                if let product = entitlement.productIdentifier {
                    DetailRow(label: "Product", value: product)
                }
            } header: {
                Text("Your plan")
            } footer: {
                Text(
                    dependencies.effectiveEntitlement.renewalOrExpirationDate == nil
                        ? "The App Store has not told \(AppConfiguration.displayName) a renewal date, so none is shown. It is in your Apple Account settings."
                        : AppCopy.subscriptionTerms
                )
            }

            Section("Free plan") {
                DetailRow(
                    label: "Open rentals",
                    value: "\(EntitlementPolicy.freeOpenItemLimit) at a time"
                )
                Text(AppCopy.entitlementLossReassurance)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Button("See Pro options") { router.presentedSheet = .paywall(reason: .settings) }
                    .minimumTapTarget()
                Button("Restore purchases") {
                    Task {
                        await dependencies.subscriptions.restore()
                        restoreMessage = dependencies.effectiveEntitlement.isPro
                            ? "Pro is active on this Apple Account."
                            : "No active subscription was found on this Apple Account."
                    }
                }
                .minimumTapTarget()
                if let url = AppConfiguration.manageSubscriptionsURL {
                    Button("Manage subscription") { openURL(url) }.minimumTapTarget()
                }
            }
        }
        .offRentFormBackground()
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Restore purchases",
            isPresented: Binding(
                get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
    }
}

struct ReminderSettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @State private var authorizationDenied = false

    var body: some View {
        @Bindable var dependencies = dependencies

        return List {
            Section {
                Text(AppCopy.notificationsExplanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Remind me about") {
                ForEach(ReminderKind.allCases, id: \.self) { kind in
                    reminderToggle(kind)
                }
            }

            if dependencies.reminderSettings.isEnabled(.rateRollover) {
                Section("Rate changes") {
                    Stepper(
                        "\(dependencies.reminderSettings.rolloverLeadHours) hours before",
                        value: $dependencies.reminderSettings.rolloverLeadHours,
                        in: 0...168, step: 6
                    )
                    .minimumTapTarget()
                }
            }

            if dependencies.reminderSettings.isEnabled(.confirmationOutstanding) {
                Section("Missing confirmation") {
                    Stepper(
                        "\(dependencies.reminderSettings.confirmationNagAfterHours) hours after marking done",
                        value: $dependencies.reminderSettings.confirmationNagAfterHours,
                        in: 1...72, step: 1
                    )
                    .minimumTapTarget()
                }
            }

            Section("When reminders arrive") {
                Stepper(
                    "Around \(dependencies.reminderSettings.preferredHour):00",
                    value: $dependencies.reminderSettings.preferredHour,
                    in: 5...21, step: 1
                )
                .minimumTapTarget()
                Text("Day-scale reminders are pinned to this hour so none of them wakes you at 3am.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(
                    "Default review window: \(dependencies.reminderSettings.defaultDisputeWindowDays) days",
                    value: $dependencies.reminderSettings.defaultDisputeWindowDays,
                    in: 0...90, step: 1
                )
                .minimumTapTarget()
            } header: {
                Text("Invoice review window")
            } footer: {
                Text("""
                    This is a number you enter, not something \(AppConfiguration.displayName) knows. \
                    Check each vendor's own terms — you can override it per agreement.
                    """)
            }

            if authorizationDenied {
                Section {
                    Label(
                        "Notifications are turned off for \(AppConfiguration.displayName) in iOS Settings. Reminders will not appear until you turn them back on.",
                        systemImage: "bell.slash"
                    )
                    .font(.footnote)
                    .foregroundStyle(Palette.attention)
                }
            }
        }
        .offRentFormBackground()
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reminderToggle(_ kind: ReminderKind) -> some View {
        let entitlement = dependencies.effectiveEntitlement
        let locked = kind.requiresPro && !entitlement.isPro

        return Toggle(isOn: Binding(
            get: { dependencies.reminderSettings.isEnabled(kind) },
            set: { enabled in
                guard !locked else {
                    router.presentedSheet = .paywall(reason: .advancedReminders)
                    return
                }
                Task { await setEnabled(enabled, for: kind) }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(kind.displayName)
                    if locked {
                        Label("Pro", systemImage: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(Palette.accent)
                    }
                }
                Text(kind.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .minimumTapTarget()
    }

    private func setEnabled(_ enabled: Bool, for kind: ReminderKind) async {
        if enabled {
            // Permission is requested here and nowhere else — only after the user has actually
            // asked for a reminder. An app that prompts on launch gets denied on launch.
            let status = await dependencies.notifications.authorizationStatus()
            if status == .notDetermined {
                let granted = await dependencies.notifications.requestAuthorization()
                authorizationDenied = !granted
                guard granted else { return }
            } else if status == .denied {
                authorizationDenied = true
                return
            }
            dependencies.reminderSettings.enabledKinds.insert(kind)
        } else {
            dependencies.reminderSettings.enabledKinds.remove(kind)
        }
    }
}

struct AppearanceSettingsView: View {
    @AppStorage(AppearanceSetting.storageKey) private var appearance = AppearanceSetting.system

    var body: some View {
        List {
            Section {
                Picker("Appearance", selection: $appearance) {
                    Text("Match iOS").tag(AppearanceSetting.system)
                    Text("Light").tag(AppearanceSetting.light)
                    Text("Dark").tag(AppearanceSetting.dark)
                }
                .pickerStyle(.inline)
            } footer: {
                Text("""
                    \(AppConfiguration.displayName) follows the iOS text size you have set, \
                    including the accessibility sizes. Change it in iOS Settings › Accessibility › \
                    Display & Text Size.
                    """)
            }
        }
        .offRentFormBackground()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        // The scheme itself is applied at the root, not here: `.preferredColorScheme` affects the
        // view it is attached to and its children, so applying it on this screen would change
        // this screen and nothing else.
    }
}
