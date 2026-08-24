# OffRent Ledger — Test matrix

Three columns, and the distinction between them is the whole point of this document.

| Column | Meaning |
|---|---|
| **Written** | The test exists in the repository and is committed. |
| **Executed** | The test was actually run, on this machine, in this build. |
| **Passed** | It ran and it passed. |

A test that is written but not executed proves nothing. This document never conflates the two.

**Environments.** Two, and every row below says which one it ran in.

| | |
|---|---|
| **This machine** | Ubuntu 24.04 x86_64, `Swift 6.0.3`. No macOS, no Xcode, no iOS SDK, no simulator, no device. `xcodebuild` does not exist here and cannot be installed. |
| **CI** | GitHub Actions `macos-15`, Xcode 16.4, iOS Simulator, the `Verify` workflow. Previously Codemagic `mac_mini_m2`, which reached green first on 2026-08-21 after four rounds of compile fixes. |

Everything in section A runs in both. Section B runs only in CI. Section D runs in neither.

---

## A. Executed and passed — the portable domain suite

Run with `swift test` against the root `Package.swift`, which compiles
`OffRentLedger/Domain` and `OffRentShared` — **the same files the Xcode app target compiles**,
not a copy. Swift language mode is pinned to v5 to match the Xcode project's `SWIFT_VERSION`.

**168 tests. 168 passed. 0 failed.**

| Suite | Tests | Result | What it covers |
|---|---:|---|---|
| `RentalRateEngineTests` | 26 | ✅ pass | Period counting, DST spring-forward and fall-back, time-zone stability, missing/negative/zero rates, manual vs scheduled rollover, override precedence, rounding drift over 400 periods |
| `DocumentTextParserTests` | 22 | ✅ pass | OCR parsing against 7 synthetic fixtures; "7 DAY RATE" not read as a daily rate; confidence degradation; provenance; determinism |
| `StatusTransitionTests` | 20 | ✅ pass | The whole transition table; **exhaustive proof that no intent reaches Confirmation Recorded without the user affirming contact**; reopen rules; banned vocabulary |
| `ReminderPlannerTests` | 20 | ✅ pass | Each reminder kind, opt-in default, closed items never nag, stable identifiers, entitlement gating, DST |
| `BackupArchiveTests` | 15 | ✅ pass | Round trip, byte stability, version gate, additive-only import, orphan handling, missing files |
| `InvoiceComparisonTests` | 14 | ✅ pass | Expectation runs to the confirmation not to pickup; zero variance; extra-day mismatch; review flags vs findings |
| `EntitlementPolicyTests` | 9 | ✅ pass | Free limit; **every guarantee that entitlement never removes access to existing records** |
| `CSVExportTests` | 8 | ✅ pass | RFC 4180 quoting, formula-injection neutralisation, blank-not-zero for incomplete estimates |
| `EvidencePacketTests` | 6 | ✅ pass | Disclaimer denies every prohibited claim; completeness reporting |
| `MoneyParsingTests` | 6 | ✅ pass | Accepted and rejected forms; banker's rounding; cent-level equality |
| `SnapshotBuilderTests` | 6 | ✅ pass | Aggregation; **the widget snapshot cannot carry identifying detail** |
| `DateTextParserTests` | 4 | ✅ pass | US paperwork formats; noon anchoring; implausible years rejected |
| `DeepLinkTests` | 4 | ✅ pass | Round trip of every case; foreign schemes and malformed IDs rejected |
| `FinancialWalkthroughTests` | 2 | ✅ pass | **§19 of the specification, both paths**, end to end through the engines |
| `SafePathTests` | 5 | ✅ pass | Filename sanitisation: traversal contained to one component, ordinary names unmangled, no input yields an unusable name |
| `StatusTransitionDocTests` | 1 | ✅ pass | The generated transition table matches the code |

### Also executed and passed

| Check | Result |
|---|---|
| `python3 scripts/verify_repository.py` | ✅ 41 invariant checks, 0 problems |
| `python3 scripts/check_swift_call_sites.py` | ✅ 91 types with initialisers and 117 static functions; **every call site in the repository resolves, by label and by arity**, across typealiases, extension initialisers and `@Model` classes. 0 findings. |
| `python3 scripts/generate_xcodeproj.py --check` | ✅ project.pbxproj matches its generator |
| `swift run offrent-docgen . --check` | ✅ generated docs current |
| `python3 scripts/generate_website.py --check` | ✅ the site matches its generator; privacy and terms render from the app's own Markdown |
| YAML parse of `.github/workflows/*.yml` | ✅ valid; asserts TestFlight is manual-only, actually uploads, reads its credentials from secrets, and never submits for review |
| plist / entitlements / .storekit / .xcscheme / asset-catalog JSON parse | ✅ all valid |
| Swift delimiter balance across every source file | ✅ balanced |
| Multi-line string indentation (Swift's own rule, on the targets `swift test` cannot compile) | ✅ clean |

### What the call-site checker is, and is not

It is the nearest thing to a type check this environment can run over the app layer. It matches
every `Type(...)` and `Type.staticFunc(...)` against the signatures declared in this repository —
so a stale argument label or a missing argument, the likeliest defect in never-compiled code that
calls into a compiled library, fails the build.

It says **nothing** about Apple's APIs, about whether a SwiftUI body type-checks, or about
anything the Swift compiler would catch beyond our own API surface. It was negative-tested:
planting a renamed label and a missing required argument makes it fail. Two of its rules were
established by compiling fixtures with the real Swift compiler rather than by reasoning about
Swift's memberwise-initialiser behaviour.

Section 1 of `RELEASE_CHECKLIST.md` — open it in Xcode and build — remains the real gate.

### What §19 actually verified

Both walkthrough paths ran as executed tests against the real engines:

| Step | Result |
|---|---|
| Skid-steer rental, daily rate, next rollover, expected increment confirmed | ✅ |
| Estimated running amount on day 5 = $1,425.00 (285 × 5 periods) | ✅ |
| Marking done routes to Contact Vendor, which offers exactly one way forward | ✅ |
| Confirmation number recorded; item moves to Awaiting Pickup | ✅ |
| Accrual stops at the confirmation, not at pickup; final estimate $2,280.00 | ✅ |
| Matching invoice → possible variance $0.00, item resolves | ✅ |
| Invoice with one extra day → variance $285.00, surfaced as a possible mismatch | ✅ |
| Resolve refused while a mismatch is open | ✅ |
| Follow-up recorded; recomputation after "relaunch" yields the identical result | ✅ |

The **persistence** half of steps 14–15 — that the record survives process termination — is in
`OffRentLedgerTests` and `OffRentLedgerUITests`. The `OffRentLedgerTests` half has since run on
the simulator (section B); the relaunch half is in the UI suite and has not (section C). What
section A proves on its own is that the comparison is a pure function of stored values, so a
correctly persisted store reproduces it exactly.

---

## B. Executed on the simulator — the app-target suite

Run by the `Verify` workflow, `xcodebuild test -only-testing:OffRentLedgerTests` against
the iOS 26.4 simulator. These need SwiftData, UIKit, UserNotifications and a bundle, so this
machine cannot run them; CI can.

**Run 1: 45 tests, 44 passed, 1 failed** — a real defect in the file store (below).
**Run 2: 45 tests, 41 passed, 4 failed** — the file-store fix held, and four tests that had
passed in run 1 failed in run 2 without any change to the code they cover. They waited on the
clock rather than on the condition; run 2's machine was slower (309s vs 200s for the same step)
and 200ms was no longer enough. Also below.

| Suite | Tests | Result | Covers |
|---|---:|---|---|
| `PersistenceTests` | 8 | ✅ pass | SwiftData relationships, cascade vs nullify, unknown-status degradation, archive round trip, additive import |
| `WorkflowServiceTests` | 8 | ✅ pass | Accrual stops on done and backdates to the vendor's time; refused transitions write no event; reopen restarts accrual; estimate cache |
| `FileStoreTests` | 7 | ⚠️ 6 pass, 1 failed | Downscaling, digests, **reconcile never removes a referenced file**, path traversal refused |
| `ScanReviewCommitTests` | 7 | ⚠️ run 1 pass, run 2 flaked | **Running the whole scan pipeline and discarding it writes nothing** |
| `EntitlementBehaviourTests` | 4 | ✅ pass | Free limit against a real store; resolving frees the slot; lapsed Pro keeps everything working |
| `NotificationSchedulerTests` | 5 | ✅ pass | Add/cancel diffing; no authorisation request from synchronising |
| `CopyTests` + `FixtureParityTests` | 6 | ✅ pass | Required copy present, banned copy absent, stub matches the committed fixture |

### The failure, and what it found

`FileStoreTests.pathTraversalIsRefused` failed with `writeFailed("-/-/-/etc/passwd")`.

The sanitiser allowed `/` in its alphabet. It neutralised `..` correctly, but the separators
survived, so `sanitise("../../../etc/passwd")` returned `-/-/-/etc/passwd` — a *path* three
directories deep, not a filename. It could not climb above the evidence root, so nothing could
escape; what it did do was aim a write at folders nobody had created, and the write threw.

The fix moved the logic out of `AppFileStore` and into `OffRentLedger/Domain/SafePathComponent.swift`,
where the portable suite can execute it on any machine, and dropped `/` from the allowed set.
`SafePathTests` in section A is the cover. The containment guard in `writeDataSynchronously` now
checks the destination as well as the directory.

The point worth keeping: this defect survived a code review, a call-site checker and 163 passing
tests. It was in the one layer nothing here could execute, and it stayed there until something
finally executed it.

### The second failure, and why it is not a flake

Run 2 reported four failures in `ScanReviewCommitTests`, in tests that had passed in run 1
against identical code. Two said the phase was `.recognising` where `.reviewing` was expected;
two said an accepted value was `.text("310.00")` where `.money(310)` was expected.

All four were one cause. The tests started recognition, slept 200ms, and asserted. Recognition
runs in a `Task`; when it has not finished, `result` is nil, so `suggestion(for:)` returns nil
and `acceptedValues()` falls through to its no-suggestion branch — which is exactly `.text`. Run
2's machine was slower, Swift Testing runs suites in parallel, and 200ms stopped being enough.

Calling that a flake and re-running would have been the wrong call twice over: it is a real
defect in the tests, and a test that fails when the machine is busy rather than when the code is
wrong trains everybody to ignore it. `ScanReviewViewModel` now exposes `awaitPendingWork()`, the
six sleeps are gone, and a repository check fails any `Task.sleep` in a test target.

Worth recording: the *product* invariant held throughout. `apply(scanned:)` matches on
`(field, value)` pairs, so a `.text` value for a money field hits `default: break` and is
discarded. The tests were wrong about when to look, not about what the app does.

**Not yet observed:** the re-run. The fix is verified by `SafePathTests` and by compiling and
running the real sanitiser standalone against the failing inputs; the simulator suite has not
been run again since.

---

## C. Written, NOT executed — the UI suite

**11 UI test methods.** They need a booted simulator running the app, which is the
UI scenarios below, and they have not been run.

| Suite | Tests | Status | Covers |
|---|---:|---|---|
| `CoreWorkflowUITests` | 2 | ⛔ not executed | Manual creation + relaunch; full workflow to resolution with zero variance |
| `MismatchUITests` | 2 | ⛔ not executed | Extra-day mismatch survives relaunch; **scan review never saves without confirmation** |
| `EntitlementUITests` | 3 | ⛔ not executed | Free limit, Pro unlock via the StoreKit test configuration, entitlement loss |
| `AccessibilityUITests` | 4 | ⛔ not executed | Tabs labelled, estimate spoken as an estimate, disclosure readable, status spoken |

To execute, on a Mac:

```
xcodebuild test -project OffRentLedger.xcodeproj -scheme OffRentLedger \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## D. Not verified anywhere yet

Every one of these is a human or device gate. Nothing in this repository is evidence for any
of them.

| Gate | Status |
|---|---|
| The Xcode project builds | ✅ **verified in CI** — `xcodebuild clean build`, app and widget, Xcode 26.4 |
| The SwiftUI / SwiftData / StoreKit code compiles | ✅ **verified in CI** — zero errors; `docs/RISK_REGISTER.md` R2 and R3 are closed |
| The Xcode project opens in the Xcode UI | ⛔ unverified — CI drives `xcodebuild`, which is not the same thing |
| Simulator run of the app | ⛔ unverified |
| Release archive, signing, export | ⛔ unverified |
| Live document camera | ⛔ unverified |
| Photo picker and PDF import on device | ⛔ unverified |
| OCR against real vendor contracts | ⛔ unverified |
| Local notification delivery | ⛔ unverified |
| Deep links from a delivered notification | ⛔ unverified |
| Location permission prompt, one-shot capture, denial path | ⛔ unverified |
| Widget rendering and refresh | ⛔ unverified |
| App Intents / Shortcuts | ⛔ unverified |
| PDF sharing via the share sheet | ⛔ unverified |
| StoreKit **Sandbox** purchase | ⛔ unverified |
| Restore purchases against a real Apple Account | ⛔ unverified |
| Cancellation, expiry, billing retry, refund behaviour | ⛔ unverified |
| TestFlight install and purchase | ⛔ unverified |
| App icon during the purchase flow | ⛔ unverified |
| Light / dark appearance on hardware | ⛔ unverified |
| Dynamic Type at accessibility sizes on hardware | ⛔ unverified |
| VoiceOver traversal | ⛔ unverified |
| Performance with 1,000 items; scrolling; cold launch | ⛔ **not measured** |
| Migration against a real existing store | ⛔ unverified |
| Legal URL liveness | ⛔ unverified — the app does not claim they are live |
| Bundle ID availability, Team ID, App Store Connect record | ⛔ unverified |

**A passing StoreKit configuration test says nothing about production purchases.** The
`.storekit` file is a local simulator fixture. Sandbox and TestFlight are separate real gates.
