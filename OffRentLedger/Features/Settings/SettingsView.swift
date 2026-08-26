import SwiftData
import SwiftUI

struct SettingsView: View {

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(OnboardingState.self) private var onboarding

    var body: some View {
        // A real inset-grouped `List`. The hand-built version of this screen had to reimplement
        // rows, separators, insets and highlight-on-tap, and got all four slightly wrong.
        List {
            Section {
                NavigationLink(value: SettingsDestination.subscription) {
                    LabeledContent("Subscription") {
                        Text(dependencies.effectiveEntitlement.isPro ? "Pro" : "Free")
                    }
                }
                .accessibilityIdentifier(A11yID.Settings.subscription)
            }

            Section {
                settingsRow(.reminders, "Reminders", "bell", A11yID.Settings.reminders)
                settingsRow(.appearance, "Appearance", "textformat.size", A11yID.Settings.appearance)
                settingsRow(
                    .backupAndTransfer, "Backup and transfer", "arrow.down.doc",
                    A11yID.Settings.backupAndTransfer
                )
                settingsRow(
                    .dataAndPrivacy, "Data and privacy", "lock.shield",
                    A11yID.Settings.dataAndPrivacy
                )
            }

            Section {
                Toggle(
                    "Fill the form automatically",
                    isOn: Binding(
                        get: { dependencies.scanSettings.autoFillConfidentScans },
                        set: { dependencies.scanSettings.autoFillConfidentScans = $0 }
                    )
                )
                .accessibilityIdentifier(A11yID.Settings.autoFillScans)
            } header: {
                Text("Scanning")
            } footer: {
                Text(AppCopy.autoFillScansExplanation)
            }

            Section {
                // One entry, and it runs the same walkthrough the app presents on a first
                // launch. There used to be two — a page tour and a hands-on guide that asked
                // the user to work through the real workflow — and the second one could not be
                // finished without creating records to practise on.
                Button {
                    onboarding.startTour()
                } label: {
                    Label("Replay the walkthrough", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier(A11yID.Onboarding.replayTour)
            } footer: {
                Text("Seven pages. It explains the workflow without changing anything.")
            }

            Section("Legal and support") {
                settingsRow(.privacyPolicy, "Privacy Policy", "hand.raised", A11yID.Settings.privacyPolicy)
                settingsRow(.terms, "Terms of Use", "doc.text", A11yID.Settings.terms)
                settingsRow(.support, "Support", "questionmark.circle", A11yID.Settings.support)
                settingsRow(.about, "About", "info.circle", A11yID.Settings.about)
            }

            Section {
                EmptyView()
            } footer: {
                VStack(alignment: .leading, spacing: Space.hair) {
                    Text("\(AppConfiguration.displayName) \(AppConfiguration.versionAndBuild)")
                        .accessibilityIdentifier(A11yID.Settings.versionLabel)
                    Text(AppConfiguration.poweredByLine)
                }
            }
        }
        .listStyle(.insetGrouped)
        .offRentFormBackground()
        .navigationTitle("Settings")
        .accessibilityIdentifier(A11yID.Settings.root)
        .offRentNavigationDestinations()
    }

    private func settingsRow(
        _ destination: SettingsDestination, _ title: String, _ symbol: String, _ identifier: String
    ) -> some View {
        NavigationLink(value: destination) {
            Label(title, systemImage: symbol)
        }
        .accessibilityIdentifier(identifier)
    }
}

/// Settings › Subscription.
///
/// It was a list of `DetailRow`s, one of which printed the raw StoreKit product identifier —
/// `com.idlery.offrent.pro.monthly` — at a user who has no use for it and at a reviewer who reads
/// it as an unfinished screen. What somebody actually wants here is four things: what they are on,
/// what it costs them next and when, what Pro would add, and how to change or restore it.
///
/// The renewal date is still only ever shown when StoreKit has provided one. This app does not
/// compute a renewal date of its own; a wrong date beside a real charge is indefensible.
struct SubscriptionSettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL

    @State private var restoreMessage: String?
    @State private var isRestoring = false

    private var entitlement: EntitlementState { dependencies.effectiveEntitlement }

    /// The plan in words. The identifier is a build detail and belongs nowhere near a person.
    private var planName: String {
        switch entitlement.productIdentifier {
        case AppConfiguration.monthlyProductIdentifier: "Pro, billed monthly"
        case AppConfiguration.annualProductIdentifier: "Pro, billed yearly"
        default: entitlement.isPro ? "Pro" : "Free"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                statusCard
                whatProAdds
                freePlan
                actions
                terms
            }
            .padding(.horizontal, Space.comfortable)
            .padding(.top, Space.base)
            .padding(.bottom, Space.screenBottom)
        }
        .offRentScreen()
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(A11yID.Settings.subscriptionRoot)
    }

    // MARK: - Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: Space.base) {
            CardHeader(
                title: planName,
                subtitle: entitlement.reason.displayName,
                symbol: entitlement.isPro ? "checkmark.seal.fill" : "person.crop.circle",
                tint: entitlement.isPro ? Palette.settled : Palette.accent
            )

            if let date = entitlement.renewalOrExpirationDate {
                RowDivider()
                DetailRow(
                    label: entitlement.isPro ? "Renews or expires" : "Expired",
                    value: Formatters.mediumDate(date)
                )
            } else {
                RowDivider()
                Text("""
                    The App Store has not told \(AppConfiguration.displayName) a renewal date, so \
                    none is shown here. Your Apple Account settings always have it.
                    """)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.Settings.subscriptionPlan)
    }

    // MARK: - What Pro adds

    private var whatProAdds: some View {
        VStack(alignment: .leading, spacing: Space.base) {
            CardHeader(
                title: entitlement.isPro ? "What Pro gives you" : "What Pro would add",
                symbol: "sparkles",
                tint: Palette.accent
            )
            // Straight off `ProFeature`, so this list cannot drift from what the entitlement
            // check actually gates.
            ForEach(ProFeature.allCases, id: \.self) { feature in
                HStack(alignment: .firstTextBaseline, spacing: Space.snug) {
                    Image(systemName: entitlement.isPro ? "checkmark" : "lock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(entitlement.isPro ? Palette.settled : .secondary)
                        .frame(width: Layout.symbolInline, alignment: .leading)
                        .accessibilityHidden(true)
                    Text(feature.displayName)
                        .font(Typography.rowDetail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard()
    }

    // MARK: - Free plan

    private var freePlan: some View {
        VStack(alignment: .leading, spacing: Space.base) {
            CardHeader(title: "On the free plan", symbol: "shippingbox", tint: .secondary)
            DetailRow(
                label: "Open rentals",
                value: "\(EntitlementPolicy.freeOpenItemLimit) at a time"
            )
            Text(AppCopy.entitlementLossReassurance)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard()
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: Space.snug) {
            if !entitlement.isPro {
                Button("See Pro options") {
                    router.presentedSheet = .paywall(reason: .settings)
                }
                .buttonStyle(.offRentPrimary)
                .accessibilityIdentifier(A11yID.Settings.subscriptionSeePro)
            }

            Button(isRestoring ? "Restoring…" : "Restore purchases") {
                guard !isRestoring else { return }
                isRestoring = true
                Task {
                    await dependencies.subscriptions.restore()
                    isRestoring = false
                    restoreMessage = dependencies.effectiveEntitlement.isPro
                        ? "Pro is active on this Apple Account."
                        : "No active subscription was found on this Apple Account."
                }
            }
            .buttonStyle(.offRentSecondary)
            .disabled(isRestoring)
            .accessibilityIdentifier(A11yID.Settings.subscriptionRestore)

            if let url = AppConfiguration.manageSubscriptionsURL {
                Button("Manage or cancel in your Apple Account") { openURL(url) }
                    .buttonStyle(.offRentSecondary)
                    .accessibilityIdentifier(A11yID.Settings.subscriptionManage)
            }

            // On the actions, not on the screen: an alert sharing a chain with a sheet stops the
            // sheet presenting in this app, and `See Pro options` presents one through the router.
            if let restoreMessage {
                InlineAlert(message: restoreMessage)
            }
        }
        .frame(maxWidth: .infinity)
        .offRentCard()
    }

    // MARK: - Terms

    private var terms: some View {
        VStack(alignment: .leading, spacing: Space.snug) {
            Text(AppCopy.subscriptionTerms)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.section) {
                NavigationLink("Privacy Policy", value: SettingsDestination.privacyPolicy)
                NavigationLink("Terms of Use", value: SettingsDestination.terms)
            }
            .font(Typography.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.tight)
    }
}

struct AppearanceSettingsView: View {
    @AppStorage(AppearanceSetting.storageKey)
    private var appearance = AppearanceSetting.installDefault

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
