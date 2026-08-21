# OffRentLedgerTests

XCTest cases that need Apple frameworks: SwiftData persistence, the workflow service, the file
store, the notification scheduler adapter, and StoreKit entitlement behaviour.

**These were written but NOT executed.** The build environment had no macOS, no Xcode and no iOS
SDK, so `xcodebuild test` could not be run. See `TEST_MATRIX.md` for the precise distinction
between what was written, what was executed, and what passed.

Everything that could be moved out of this target and into the Foundation-only `Domain` layer was,
precisely so that the untested surface here is as small as possible. `Tests/OffRentDomainTests`
holds 163 tests that **did** run.
