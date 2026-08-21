import SwiftData
import SwiftUI

struct SettingsView: View {

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router

    var body: some View {
        List {
            Section {
                NavigationLink(value: SettingsDestination.subscription) {
                    HStack {
                        Label("Subscription", systemImage: "star.circle")
                        Spacer()
                        Text(dependencies.effectiveEntitlement.isPro ? "Pro" : "Free")
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier(A11yID.Settings.subscription)
                .minimumTapTarget()
            }

            Section {
                NavigationLink(value: SettingsDestination.reminders) {
                    Label("Reminders", systemImage: "bell")
                }
                .accessibilityIdentifier(A11yID.Settings.reminders)
                .minimumTapTarget()

                NavigationLink(value: SettingsDestination.appearance) {
                    Label("Appearance", systemImage: "textformat.size")
                }
                .accessibilityIdentifier(A11yID.Settings.appearance)
                .minimumTapTarget()

                NavigationLink(value: SettingsDestination.dataAndPrivacy) {
                    Label("Data and privacy", systemImage: "lock.shield")
                }
                .accessibilityIdentifier(A11yID.Settings.dataAndPrivacy)
                .minimumTapTarget()
            }

            Section {
                NavigationLink(value: SettingsDestination.privacyPolicy) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                .accessibilityIdentifier(A11yID.Settings.privacyPolicy)
                .minimumTapTarget()

                NavigationLink(value: SettingsDestination.terms) {
                    Label("Terms of Use", systemImage: "doc.text")
                }
                .accessibilityIdentifier(A11yID.Settings.terms)
                .minimumTapTarget()

                NavigationLink(value: SettingsDestination.support) {
                    Label("Support", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier(A11yID.Settings.support)
                .minimumTapTarget()
            } header: {
                Text("Legal and support")
            }

            Section {
                NavigationLink(value: SettingsDestination.about) {
                    Label("About", systemImage: "info.circle")
                }
                .accessibilityIdentifier(A11yID.Settings.about)
                .minimumTapTarget()
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(AppConfiguration.displayName) \(AppConfiguration.versionAndBuild)")
                        .accessibilityIdentifier(A11yID.Settings.versionLabel)
                    Text(AppConfiguration.poweredByLine)
                }
                .font(.caption)
            }
        }
        .navigationTitle("Settings")
        .accessibilityIdentifier(A11yID.Settings.root)
        .navigationDestination(for: SettingsDestination.self) { destination in
            switch destination {
            case .subscription: SubscriptionSettingsView()
            case .reminders: ReminderSettingsView()
            case .appearance: AppearanceSettingsView()
            case .dataAndPrivacy: DataAndPrivacyView()
            case .privacyPolicy: LegalDocumentView(document: .privacy)
            case .terms: LegalDocumentView(document: .terms)
            case .support: SupportView()
            case .about: AboutView()
            }
        }
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
    @AppStorage("com.idlery.offrent.appearance") private var appearance = "system"

    var body: some View {
        List {
            Section {
                Picker("Appearance", selection: $appearance) {
                    Text("Match iOS").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
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
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(
            appearance == "light" ? .light : (appearance == "dark" ? .dark : nil)
        )
    }
}
