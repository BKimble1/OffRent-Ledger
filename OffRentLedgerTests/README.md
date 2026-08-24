# OffRentLedgerTests

Test cases that need Apple frameworks: SwiftData persistence, the workflow service, the file
store, the notification scheduler adapter, and StoreKit entitlement behaviour.

**These run on the simulator, in CI.** They cannot run on the machine this app was written on —
Linux, no Xcode, no iOS SDK — so for most of the build they were written but unexecuted. The
The GitHub Actions `Verify` workflow runs them now. `TEST_MATRIX.md` keeps the precise
distinction between what is written, what was executed, where, and what passed.

Everything that could be moved out of this target and into the Foundation-only `Domain` layer
was, precisely so that what depends on a Mac is as small as possible. `Tests/OffRentDomainTests`
holds 168 tests that run anywhere.

That split earns its keep in both directions. The first simulator run of this target found a
path-traversal defect that 163 passing domain tests, a call-site checker and a review pass had
all missed — because the defect was in the one layer nothing could execute. The fix moved the
logic *into* `Domain`, where it is now covered by tests that run on any machine.
