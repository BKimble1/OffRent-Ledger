import SwiftData
import SwiftUI

@main
struct OffRentLedgerApp: App {

    @State private var dependencies: AppDependencies
    @State private var router = AppRouter()
    @State private var onboarding = OnboardingState()
    private let container: ModelContainer?

    init() {
        let dependencies = AppDependencies.live()
        let overrides = AppDependencies.testOverrides()

        var container: ModelContainer?
        do {
            container = try ModelContainerFactory.make(inMemory: overrides.useInMemoryStore)
        } catch {
            // Never fatal. A store that cannot open is usually a store the app cannot read, and
            // crashing on launch would leave a contractor with no way to reach an export.
            dependencies.storeFailure = String(describing: error)
            container = nil
        }

        self.container = container

        // UI tests need to choose which first run they are exercising. Compiled out of Release
        // along with every other launch override.
        #if DEBUG
        let onboarding = OnboardingState()
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(LaunchArgument.resetOnboarding) {
            onboarding.reset()
        } else if arguments.contains(LaunchArgument.skipOnboarding) {
            onboarding.markWelcomed()
            onboarding.markTourSeen()
        }
        _onboarding = State(initialValue: onboarding)
        #endif
        _dependencies = State(initialValue: dependencies)
    }

    var body: some Scene {
        WindowGroup {
            LaunchSplashOverlay {
                Group {
                    if let container {
                        RootView()
                            .modelContainer(container)
                    } else {
                        StoreRecoveryView(detail: dependencies.storeFailure)
                    }
                }
            }
            .environment(dependencies)
            .environment(router)
            .environment(onboarding)
            .onOpenURL { url in
                _ = router.handle(url: url)
            }
            .task {
                dependencies.subscriptions.startObservingTransactions()
                await dependencies.subscriptions.refreshEntitlement()
                await dependencies.subscriptions.loadProducts()
            }
        }
    }
}

/// Shown when the store will not open.
///
/// It offers the two things that are still possible — try again, or start fresh — and says
/// plainly that starting fresh loses data. Anything else here would be pretending the app can
/// recover something it cannot reach.
struct StoreRecoveryView: View {
    let detail: String?
    @State private var showingReset = false
    @State private var didReset = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Palette.attentionText)
                .accessibilityHidden(true)

            Text(didReset ? "Data cleared" : "Your rental data could not be opened")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            if didReset {
                Text("Close \(AppConfiguration.displayName) completely and open it again.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
            }

            Text("""
                This usually means the app was updated or restored while the data file was in an \
                unexpected state. Your information has not been deleted.
                """)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("""
                Try relaunching first. If that does not work, contact support before resetting — \
                resetting deletes everything on this iPhone and cannot be undone.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let url = AppConfiguration.supportMailtoURL {
                Link("Contact support", destination: url)
                    .buttonStyle(.borderedProminent)
                    .minimumTapTarget()
            }

            Button("Reset all data", role: .destructive) { showingReset = true }
                .minimumTapTarget()

            if let detail {
                DisclosureGroup("Technical detail") {
                    Text(detail)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.footnote)
            }
        }
        .padding(28)
        .alert("Delete all data on this iPhone?", isPresented: $showingReset) {
            Button("Delete everything", role: .destructive) { resetStore() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every rental, photo and document in \(AppConfiguration.displayName) will be removed. This cannot be undone.")
        }
    }

    private func resetStore() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let support else { return }
        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            try? FileManager.default.removeItem(at: support.appendingPathComponent(name))
        }
        try? FileManager.default.removeItem(
            at: support.appendingPathComponent("OffRentLedger", isDirectory: true)
        )
        // Deliberately does not call exit(). Terminating yourself is grounds for App Store
        // rejection, and to the user it is indistinguishable from a crash at the exact moment
        // they were told the app was recovering. Asking them to reopen it is honest and works.
        didReset = true
    }
}
