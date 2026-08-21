# OffRent Ledger — Test matrix

Three columns, and the distinction between them is the whole point of this document.

| Column | Meaning |
|---|---|
| **Written** | The test exists in the repository and is committed. |
| **Executed** | The test was actually run, on this machine, in this build. |
| **Passed** | It ran and it passed. |

A test that is written but not executed proves nothing. This document never conflates the two.

**Environment:** Ubuntu 24.04 x86_64. `Swift version 6.0.3 (swift-6.0.3-RELEASE)`.
No macOS, no Xcode, no iOS SDK, no simulator, no device. `xcodebuild` does not exist here and
cannot be installed.

---

## A. Executed and passed — the portable domain suite

Run with `swift test` against the root `Package.swift`, which compiles
`OffRentLedger/Domain` and `OffRentShared` — **the same files the Xcode app target compiles**,
not a copy. Swift language mode is pinned to v5 to match the Xcode project's `SWIFT_VERSION`.

**163 tests. 163 passed. 0 failed.**

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
| `StatusTransitionDocTests` | 1 | ✅ pass | The generated transition table matches the code |

### Also executed and passed

| Check | Result |
|---|---|
| `python3 scripts/verify_repository.py` | ✅ 30 invariant checks, 0 problems |
| `python3 scripts/check_swift_call_sites.py` | ✅ 91 types with initialisers and 117 static functions; **every call site in the repository resolves, by label and by arity**, across typealiases, extension initialisers and `@Model` classes. 0 findings. |
| `python3 scripts/generate_xcodeproj.py --check` | ✅ project.pbxproj matches its generator |
| `swift run offrent-docgen . --check` | ✅ generated docs current |
| `python3 scripts/generate_website.py --check` | ✅ website matches the bundled legal Markdown |
| YAML parse of `codemagic.yaml` | ✅ valid; asserts no automatic App Store submission |
| plist / entitlements / .storekit / .xcscheme / asset-catalog JSON parse | ✅ all valid |
| Swift delimiter balance across every source file | ✅ balanced |

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
`OffRentLedgerTests` and `OffRentLedgerUITests` and was **not executed**. What was proved here
is that the comparison is a pure function of stored values, so a correctly persisted store
reproduces it exactly.

---

## B. Written, NOT executed — needs Xcode

**56 tests: 45 XCTest cases and 11 UI test methods. None were run.**

45 XCTest cases in `OffRentLedgerTests/` and 11 UI test methods in
`OffRentLedgerUITests/`. They compile against Apple frameworks that do not exist on this machine.

| Suite | Tests | Status | Covers |
|---|---:|---|---|
| `PersistenceTests` | 8 | ⛔ not executed | SwiftData relationships, cascade vs nullify, unknown-status degradation, archive round trip, additive import |
| `WorkflowServiceTests` | 8 | ⛔ not executed | Accrual stops on done and backdates to the vendor's time; refused transitions write no event; reopen restarts accrual; estimate cache |
| `FileStoreTests` | 7 | ⛔ not executed | Downscaling, digests, **reconcile never removes a referenced file**, path traversal refused |
| `ScanReviewCommitTests` | 7 | ⛔ not executed | **Running the whole scan pipeline and discarding it writes nothing** |
| `EntitlementBehaviourTests` | 4 | ⛔ not executed | Free limit against a real store; resolving frees the slot; lapsed Pro keeps everything working |
| `NotificationSchedulerTests` | 5 | ⛔ not executed | Add/cancel diffing; no authorisation request from synchronising |
| `CopyTests` + `FixtureParityTests` | 6 | ⛔ not executed | Required copy present, banned copy absent, stub matches the committed fixture |
| `CoreWorkflowUITests` | 2 | ⛔ not executed | Manual creation + relaunch; full workflow to resolution with zero variance |
| `MismatchUITests` | 2 | ⛔ not executed | Extra-day mismatch survives relaunch; **scan review never saves without confirmation** |
| `EntitlementUITests` | 3 | ⛔ not executed | Free limit, Pro unlock via the StoreKit test configuration, entitlement loss |
| `AccessibilityUITests` | 4 | ⛔ not executed | Tabs labelled, estimate spoken as an estimate, disclosure readable, status spoken |

To execute: run the `offrent-fast-verify` and `offrent-targeted-ui` Codemagic workflows, or on
a Mac:

```
xcodebuild test -project OffRentLedger.xcodeproj -scheme OffRentLedger \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## C. Not verifiable anywhere in this environment

Nothing in this repository is evidence for any of these. Every one is a human or device gate.

| Gate | Status |
|---|---|
| The Xcode project opens and builds | ⛔ **unverified** — the highest-risk item in the project; `docs/RISK_REGISTER.md` R2 |
| The SwiftUI / SwiftData / StoreKit code compiles | ⛔ **unverified** — never type-checked anywhere; `docs/RISK_REGISTER.md` R3 |
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
