import Foundation
import SwiftData
import SwiftUI

/// Everything the app depends on that is not pure computation.
///
/// One container, injected into the SwiftUI environment, resolved at the root. There is no global
/// mutable business state anywhere in the app; the closest thing is this object, and it holds
/// services rather than rentals.
@MainActor
@Observable
final class AppDependencies {

    let clock: any Clock
    let fileStore: any FileStoring
    let textRecognizer: any DocumentTextRecognizing
    let documentIntelligence: any DocumentIntelligence
    let notifications: any NotificationScheduling
    let location: any OneTimeLocationProviding
    let evidenceRenderer: any EvidenceRendering
    let snapshotPublisher: any SnapshotPublishing
    let subscriptions: any SubscriptionProviding

    var reminderSettings: ReminderSettings {
        didSet { ReminderSettingsStore.save(reminderSettings) }
    }

    /// What the scanner may do without asking. Off by default; see `ScanSettings`.
    var scanSettings: ScanSettings {
        didSet { ScanSettingsStore.save(scanSettings) }
    }

    /// Set when the store could not be opened. The root view shows a recovery screen rather than
    /// the app crashing on launch and taking a contractor's records with it.
    var storeFailure: String?

    /// Bumped by a screen that has just written something the app's *derived* state depends on:
    /// the cached estimates, the widget snapshot, the Shortcuts index and the reminder schedule.
    ///
    /// Those four were recomputed on launch and on returning to the foreground, and nowhere else.
    /// So a rental created and then edited in one sitting had no reminder until the next time the
    /// app came back from the background — which for the one user who adds a rental and puts the
    /// phone down is the run where the reminder mattered. §9 requires an edit to reach the
    /// reminders, and this is the signal that carries it.
    ///
    /// A counter rather than a closure: `RootView` owns the recomputation and observes this, so
    /// nothing downstream needs a reference to it, and there is no path by which recomputing can
    /// trigger another recomputation.
    private(set) var derivedStateGeneration = 0

    func derivedStateNeedsRefresh() { derivedStateGeneration += 1 }

    init(
        clock: any Clock,
        fileStore: any FileStoring,
        textRecognizer: any DocumentTextRecognizing,
        documentIntelligence: any DocumentIntelligence = UnavailableDocumentIntelligence(),
        notifications: any NotificationScheduling,
        location: any OneTimeLocationProviding,
        evidenceRenderer: any EvidenceRendering,
        snapshotPublisher: any SnapshotPublishing,
        subscriptions: any SubscriptionProviding,
        reminderSettings: ReminderSettings = ReminderSettingsStore.load(),
        scanSettings: ScanSettings = ScanSettingsStore.load()
    ) {
        self.scanSettings = scanSettings
        self.clock = clock
        self.fileStore = fileStore
        self.textRecognizer = textRecognizer
        self.documentIntelligence = documentIntelligence
        self.notifications = notifications
        self.location = location
        self.evidenceRenderer = evidenceRenderer
        self.snapshotPublisher = snapshotPublisher
        self.subscriptions = subscriptions
        self.reminderSettings = reminderSettings
    }

    // MARK: - Production

    static func live() -> AppDependencies {
        let overrides = testOverrides()
        let clock: any Clock = overrides.fixedNow.map { FixedClock(now: $0) } ?? SystemClock()

        return AppDependencies(
            clock: clock,
            fileStore: AppFileStore.applicationSupport(),
            textRecognizer: overrides.stubTextRecogniser
                ? StubTextRecognizer.skidSteerContract
                : VisionTextRecognizer(),
            // Off under test. A model's output is not deterministic, and a UI test that depends
            // on one is a UI test that fails on a Tuesday.
            documentIntelligence: overrides.stubTextRecogniser
                ? UnavailableDocumentIntelligence(unavailableReason: "Disabled for testing.")
                : DocumentIntelligenceFactory.make(),
            notifications: UserNotificationScheduler(),
            location: CoreLocationOneShotProvider(),
            evidenceRenderer: PDFEvidenceRenderer(),
            snapshotPublisher: AppGroupSnapshotPublisher(),
            subscriptions: StoreKitSubscriptionService(clock: clock)
        )
    }

    /// In-memory everything. Previews and unit tests.
    static func preview(
        entitlement: EntitlementState = .pro(),
        clock: any Clock = FixedClock(2026, 5, 9, 10)
    ) -> AppDependencies {
        AppDependencies(
            clock: clock,
            fileStore: AppFileStore(
                containerRoot: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            textRecognizer: StubTextRecognizer.skidSteerContract,
            notifications: RecordingNotificationScheduler(),
            location: StubLocationProvider.jobsite,
            evidenceRenderer: PDFEvidenceRenderer(),
            snapshotPublisher: InMemorySnapshotPublisher(),
            subscriptions: StubSubscriptionService(entitlement: entitlement)
        )
    }

    // MARK: - Test overrides

    struct TestOverrides {
        var useInMemoryStore = false
        var resetState = false
        var seedWalkthrough = false
        var seedFreeLimit = false
        var forcedEntitlement: EntitlementState?
        var disableAnimations = false
        var stubTextRecogniser = false
        var fixedNow: Date?

    }

    /// Reads the UI test launch arguments.
    ///
    /// **Release builds ignore every one of them.** A test hook that survives into the App Store
    /// is a way for a reviewer — or anyone else — to reach a state no customer can, and there is
    /// no version of that which ends well. `#if DEBUG` makes it impossible rather than unlikely.
    static func testOverrides() -> TestOverrides {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        func has(_ flag: String) -> Bool { arguments.contains(flag) }

        var overrides = TestOverrides()
        overrides.useInMemoryStore = has(LaunchArgument.useInMemoryStore)
        overrides.resetState = has(LaunchArgument.resetState)
        overrides.seedWalkthrough = has(LaunchArgument.seedWalkthroughFixture)
        overrides.seedFreeLimit = has(LaunchArgument.seedFreeLimitFixture)
        overrides.disableAnimations = has(LaunchArgument.disableAnimations)
        overrides.stubTextRecogniser = has(LaunchArgument.stubTextRecogniser)

        if has(LaunchArgument.forceProEntitlement) {
            overrides.forcedEntitlement = .pro(reason: .active)
        } else if has(LaunchArgument.forceFreeEntitlement) {
            overrides.forcedEntitlement = .free
        }

        if let index = arguments.firstIndex(of: LaunchArgument.fixedNow),
           arguments.count > index + 1,
           let parsed = ISO8601DateFormatter().date(from: arguments[index + 1]) {
            overrides.fixedNow = parsed
        }
        return overrides
        #else
        return TestOverrides()
        #endif
    }

    /// The entitlement the app should act on, honouring a UI-test override in Debug only.
    var effectiveEntitlement: EntitlementState {
        #if DEBUG
        if let forced = Self.testOverrides().forcedEntitlement { return forced }
        #endif
        return subscriptions.entitlement
    }
}

/// Reminder settings live in `UserDefaults` rather than SwiftData: they are device preferences,
/// not rental records, and they must be readable before the store opens.
enum ReminderSettingsStore {
    private static let key = "com.idlery.offrent.reminderSettings.v1"

    static func load() -> ReminderSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(ReminderSettings.self, from: data)
        else { return .default }
        return settings
    }

    static func save(_ settings: ReminderSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

