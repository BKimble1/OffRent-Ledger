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

**432 tests. 432 passed. 0 failed.** Last run 2026-08-27, on the working tree that became the
commit below this line in the log.

| Suite | Tests | Result | What it covers |
|---|---:|---|---|
| `RentalRateEngineTests` | 26 | ✅ pass | Period counting, DST spring-forward and fall-back, time-zone stability, missing/negative/zero rates, manual vs scheduled rollover, override precedence, rounding drift over 400 periods |
| `MapSearchTests` | 24 | ✅ pass | Local search across equipment, class, vendor ID, serial, company, jobsite, address, agreement number, PO and status; every-word-must-match narrowing; clustering at one metre; **a record with no coordinate is never placed at one**; the most urgent rental decides a shared marker; VoiceOver labels name the entity and its status rather than saying "pin" |
| `DocumentTextParserTests` | 22 | ✅ pass | OCR parsing against the fixtures; "7 DAY RATE" not read as a daily rate; confidence degradation; provenance; determinism |
| `StatusTransitionTests` | 22 | ✅ pass | The whole transition table; **exhaustive proof that no intent reaches Confirmation Recorded without the user affirming contact**; reopen rules; banned vocabulary |
| `ReminderPlannerTests` | 20 | ✅ pass | Each reminder kind, opt-in default, closed items never nag, stable identifiers, entitlement gating, DST |
| `PlaceNamingTests` | 16 | ✅ pass | **The `07820` pin.** Digit-dominant and Canadian codes recognised; UK postcodes deliberately not, with the reason; uppercase site names like `ZONE 4` survive; the fallback chain from business name to street to town; a dropped pin is never labelled with its coordinate |
| `ExtractionFixtureTests` | 16 | ✅ pass | **The residential-lease negative test**: OCR reads it, the extractor finds nothing, and the outcome is `nothingFound` rather than `Use 0 values`. Also a third vendor layout with dotted-leader rate tables and split labels; multipage page attribution; `4,18O.00` refused rather than read as $418; a clean amount before a full stop still parses |
| `BackupArchiveTests` | 15 | ✅ pass | Round trip, byte stability, version gate, additive-only import, orphan handling, missing files |
| `InvoiceComparisonTests` | 14 | ✅ pass | Expectation runs to the confirmation not to pickup; zero variance; extra-day mismatch; review flags vs findings |
| `WalkthroughScriptTests` | 14 | ✅ pass | The sequence has a first and a last; Finish appears exactly once and on the last page; an index past the end does not crash; all four tabs are pointed at; re-presentation only on a version bump; **no page claims the app contacts a vendor or guarantees anything** |
| `ModelSuggestionValidatorTests` | 13 | ✅ pass | The five rules a model proposal must survive; nothing from a model arrives ticked |
| `InvoiceAcceptanceTests` | 12 | ✅ pass | **The button that did nothing.** The screenshot's record is blocked with a reason and an `Edit invoice` route; a genuine zero-dollar invoice is accepted; live findings block as well as stored ones; a second press cannot write a second acceptance |
| `QuietHoursTests` | 12 | ✅ pass | Windows that wrap past midnight; a reminder moves earlier, never later; existing settings survive a decode |
| `CompanyMatchingTests` | 10 | ✅ pass | Case, punctuation and spacing ignored; **a different branch of the same chain is not a duplicate**; a suffix difference is not assumed to be the same company; editing a record does not find itself |
| `LegalDocumentOutlineTests` | 10 | ✅ pass | Markdown to clauses, preamble, bullets |
| `ScanOutcomeTests` | 10 | ✅ pass | Invoice fields on a contract do not count as rental details; **the commit button refuses to render a zero**; the empty state names what was not found and offers three ways on |
| `EntitlementPolicyTests` | 10 | ✅ pass | Free limit; **every guarantee that entitlement never removes access to existing records**; the widget is not among the gated features |
| `CSVExportTests` | 8 | ✅ pass | RFC 4180 quoting, formula-injection neutralisation, blank-not-zero for incomplete estimates |
| `EvidencePacketTests` | 6 | ✅ pass | Disclaimer denies every prohibited claim; completeness reporting |
| `MoneyParsingTests` | 6 | ✅ pass | Accepted and rejected forms; banker's rounding; cent-level equality |
| `SnapshotBuilderTests` | 16 | ✅ pass | Aggregation; per-rental rows, their ranking and their cap; **the widget snapshot carries the machine and nothing else identifying** |
| `SafePathTests` | 5 | ✅ pass | Filename sanitisation: traversal contained to one component, ordinary names unmangled, no input yields an unusable name |
| `DateTextParserTests` | 4 | ✅ pass | US paperwork formats; noon anchoring; implausible years rejected |
| `DeepLinkTests` | 4 | ✅ pass | Round trip of every case; foreign schemes and malformed IDs rejected |
| `UnaddressedFindingsTests` | 4 | ✅ pass | A finding nothing has been recorded against is still open |
| `EmailValidationTests` | 3 | ✅ pass | Ordinary addresses accepted, blank accepted because the field is optional, impossible shapes rejected |
| `RecognizedDocumentPageTests` | 3 | ✅ pass | A line knows its page; a document with no attribution reports page 0 rather than crashing; a page is only named when there is more than one |
| `FinancialWalkthroughTests` | 2 | ✅ pass | **§19 of the specification, both paths**, end to end through the engines |
| `StatusTransitionDocTests` | 1 | ✅ pass | The generated transition table matches the code |

**Removed in this change:** `GuidedTourTests` (8 tests). Not deleted to make a suite pass — the
feature it covered was removed by product decision. It asserted that the hands-on walkthrough
derived its step from a rental's status, which is precisely the design §10 of the brief replaced.
`WalkthroughScriptTests` (14) covers what took its place, and asserts the property the old design
could not have: that the walkthrough ends.

### Also executed and passed

| Check | Result |
|---|---|
| `python3 scripts/verify_repository.py` | ✅ 65 invariant checks, 0 problems |
| `python3 scripts/check_swift_call_sites.py` | ✅ 404 types parsed, 123 with initialisers checked and 198 static functions; **every call site in the repository resolves, by label and by arity**, across typealiases, extension initialisers and `@Model` classes. 0 findings. |
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

Run by the `Verify` workflow, `xcodebuild test -only-testing:OffRentLedgerTests` against an
iPhone and an iPad simulator. These need SwiftData, UIKit, UserNotifications and a bundle, so
this machine cannot run them; CI can.

**88 tests across 13 suites.** Last fully green: the "Unit tests" step of run
[32983157504](https://github.com/BKimble1/OffRent-Ledger/actions/runs/32983157504) at commit
`654b2be`. The two historic failures described below are kept because of what they found, not
because they are current.

| Suite | Tests | Covers |
|---|---:|---|
| `MigrationTests` | 15 | V1→V2→V3→V4, every stage lightweight; a store written by an earlier schema opens |
| `DeepLinkRoutingTests` | 9 | Where each link lands; a foreign URL is refused; the sheet queue holds one request and the later one wins |
| `PersistenceTests` | 8 | SwiftData relationships, cascade vs nullify, unknown-status degradation, archive round trip, additive import |
| `WorkflowServiceTests` | 8 | Accrual stops on done and backdates to the vendor's time; refused transitions write no event; reopen restarts accrual; estimate cache |
| `FileStoreTests` | 7 | Downscaling, digests, **reconcile never removes a referenced file**, path traversal refused |
| `ScanReviewCommitTests` | 7 | **Running the whole scan pipeline and discarding it writes nothing** |
| `CopyAndFixtureTests` | 6 | Required copy present, banned copy absent, stub matches the committed fixture |
| `AttachmentEditingTests` | 5 | Renaming and captioning survive a refetch; a blank name falls back rather than blanking the record; a failed save restores what was there; removal reports the file paths, and only once the record is gone |
| `EvidencePDFTests` | 5 | The packet is not blank and its text is not clipped — pages are rasterised and the pixels read back |
| `LaunchScreenTests` | 5 | The shipping Info.plist declares a launch screen and names both keys; the splash draws the mark at the size the launch image does |
| `NotificationSchedulerTests` | 5 | Add/cancel diffing; no authorisation request from synchronising; a test reminder survives a reschedule |
| `EntitlementBehaviourTests` | 5 | Free limit against a real store; resolving frees the slot; lapsed Pro keeps everything working; a free user's widget snapshot still carries their rentals |
| `ScanIntelligenceTests` | 4 | The model guardrail: a value not printed on the page is dropped; a rule-based suggestion always wins |

Two historic failures are worth keeping, because each was a real defect the suite caught before
it shipped:

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

## C. Executed on the simulator — the UI suite

**52 test methods across 11 suites.** The iPhone job runs 48 of them; the iPad job runs 13
(`IPadLayoutUITests` plus `CoreWorkflowUITests`, which runs on both). `LayoutObstructionUITests`
is declared as a second class inside `MapAndEditingUITests.swift`, so a count by file misses it.

| Suite | Tests | Runs on | Covers |
|---|---:|---|---|
| `CoreWorkflowUITests` | 9 | both | Manual creation and relaunch through the company picker; the full workflow to resolution with zero variance; the evidence packet sheet |
| `MapAndEditingUITests` | 7 | iPhone | Today keeps its map with no rentals and with unplaced ones; full screen and close; the legend; search finds the user's own machine; an edit survives a relaunch |
| `EntitlementUITests` | 5 | iPhone | Free limit, Pro unlock, entitlement loss |
| `OnboardingUITests` | 5 | iPhone | The walkthrough on Next and Finish alone; it dismisses itself; it is not shown twice; **it creates no rental, company or jobsite** |
| `ReusableRecordsUITests` | 5 | iPhone | The plus offers all three; a company made inside a draft returns to it selected with the draft intact; a disabled Save names the missing field |
| `AccessibilityUITests` | 4 | iPhone | Tabs labelled, the estimate spoken as an estimate, disclosure readable, status spoken |
| `InvoiceAcceptanceUITests` | 4 | iPhone | A valid invoice is accepted and survives a relaunch; an empty one is disabled with a reason and a route that opens the form |
| `IPadLayoutUITests` | 4 | iPad | The readable-width column, rotation, and the layout at iPad metrics |
| `AttachmentEditingUITests` | 4 | iPhone | 2 of 4 green as of run `33019905318`; the other two had a root cause found and fixed — see below |
| `LayoutObstructionUITests` | 3 | iPhone | The save bar stays above the keyboard on the longest form; Today scrolls clear of the tab bar |
| `MismatchUITests` | 2 | iPhone | An extra-day mismatch survives a relaunch; **scan review never saves without confirmation** |

### What is red, and why it is recorded rather than removed

**`AttachmentEditingUITests` — two faults, both now understood.**

The first was the app's, and it was the one the tester hit: `AttachmentEditorView` held a live
`@Query` built as a closure-based `NavigationLink` destination inside a `ForEach`, so the view
graph never settled and the main thread span. On a real iPhone that is a watchdog kill,
`0x8BADF00D`. Fixed in `61affad`, and the effect on this suite is measurable: every 197-second
snapshot timeout disappeared, the iPhone UI step dropped from 2368s to 1862s, and two of the four
tests went green. Invariant 63 fails the build if the shape comes back.

The second was an accessibility identifier in the wrong place, and it is why the other two stayed
red on run `33019905318`: `.accessibilityIdentifier(A11yID.Attachment.root)` sat on the chain
*above* `.safeAreaInset(edge: .bottom) { saveBar }`. SwiftUI pushes an accessibility modifier down
into an inset's contents, so the root identifier landed on the Save button and replaced
`attachment.save`. The CI accessibility dump is unambiguous —
`Button, identifier: 'attachment.editor', label: 'Save changes'` — and both failures were
`app.buttons[A11yUI.Attachment.save]` timing out after 8 seconds on a button that was on screen,
enabled, and renamed.

`EditRentalView` hit exactly this and carries a note about it; the editor reintroduced it. So the
note is no longer the only thing holding the rule: invariant 66 fails the build on the ordering,
and it found a third instance in `ScanReviewView` that nothing had noticed. **Verified**: on run
`33036865836` the suite went from two failures to one, and `testABlankNameCannotBeSaved` — which
had never passed — is green.

The third fault is the one still red, and it is a third distinct thing rather than a return of
either of the first two. `testTheNameAndCaptionSurviveLeavingAndComingBack` failed at line 31,
inside `openTheAttachment`, with *"element was found and then went away before it could be
tapped"*. The teardown dump is a rental detail screen scrolled to its **rate** rows — several
sections past the attachments row the test was reaching for. Nothing rebuilt: `reveal` swiped,
`exists` was true at the instant the gesture ended, and the flick's momentum then carried the row
off the top of the screen before anything could tap it.

`reveal` now swipes at `.slow` velocity, stops swiping the moment the row is on screen rather
than checking and swiping again, and waits for the row's frame to stop changing before handing it
back. None of that is a delay: the wait polls the frame and returns as soon as two reads agree.
**Not yet verified in CI.**

The behaviour these four tests were written for is also covered at the level that decides what the
store holds — `AttachmentEditingTests`, 5 tests, green.

**`PhotosPicker` is covered by no test.** `-offrent-stub-photo-picker` replaces it in this suite
because an out-of-process picker service keeps the app from reaching the idle state XCUITest
needs. It was not covered before that flag existed either. Saying otherwise would be worse than
the gap.

**`CoreWorkflowUITests` on iPad was not flaky. It was a bug in the test harness.**

`testManuallyCreatedRentalSurvivesRelaunch` failed on runs `33004572538` and `33035640186` and
passed in between, which is the shape that gets a test written off. Run `33035640186` printed the
actual value and ended the argument:

    XCTAssertEqual failed: ("Optional("Mini Excavatorh410.00")")
                        is not equal to ("Optional("Mini Excavator")")

The daily rate went into the equipment field, behind a stray `h`. Both come from the same place.
`reveal` swipes to bring a row on screen, and after the company sheet closes the keyboard is
back up with focus restored to the field that had it before. `swipeUp` starts at the horizontal
centre of the screen — which, with a keyboard up, is the middle of the home row, where `h` is.
iPad reads the swipe as QuickPath and types it. The swipe never reaches the form, so the rate
row is never revealed, and the `typeText` that follows goes to the field that still has focus.

`reveal` now puts the keyboard away before it swipes, and `fillMinimalRental` types through a
helper that asserts the characters landed in the field they were aimed at rather than finding
out three lines later. **Not yet verified in CI.**

`testTheEvidencePacketSheetOpensFromARental` failed once on run `32998916617` (iPhone) and has
not recurred. That one is still unexplained.

### The build that shipped as TestFlight 21

`1b7a54a` changes **only** files under `OffRentLedgerUITests/` — `git diff 04b16a8..1b7a54a` over
`OffRentLedger`, `OffRentLedgerWidget`, `OffRentShared` and `Config` is empty. The app binary is
therefore the one verified on run `32998916617` at `04b16a8`: 62 invariants, 421 domain tests, 88
app-target unit tests, simulator builds of the app and the widget for both idioms, the entire
iPad UI suite green, and 44 of 48 iPhone UI tests. What is red above is test code.

---

## D. Not verified anywhere yet

Every one of these is a human or device gate. Nothing in this repository is evidence for any
of them.

| Gate | Status |
|---|---|
| The Xcode project builds | ✅ **verified in CI** — `xcodebuild clean build`, app and widget, Xcode 26.4 |
| The SwiftUI / SwiftData / StoreKit code compiles | ✅ **verified in CI** — zero errors; `docs/RISK_REGISTER.md` R2 and R3 are closed |
| The Xcode project opens in the Xcode UI | ⛔ unverified — CI drives `xcodebuild`, which is not the same thing |
| Simulator run of the app | ✅ **verified in CI** — the UI suite launches and drives the app on a booted simulator |
| Release archive, signing, export | ⛔ unverified |
| Live document camera | ⛔ unverified |
| **OCR orientation on a photo smaller than the downscale cap** | ⛔ unverified — the fix passes `image.imageOrientation` to Vision, which is correct by inspection and by Apple's documentation, but no image has been through it here |
| **Map search, pin drop and reverse geocoding** | ⛔ unverified — `MKLocalSearch` and `CLGeocoder` both need a network and a device |
| **The full-screen map's markers and clustering** | ⛔ unverified — the clustering *rule* is covered by `MapSearchTests`; what MapKit draws is not |
| **Apple Foundation Models on a supported device** | ⛔ unverified — the guardrail is tested, the model's accuracy is not |
| Photo picker and PDF import on device | ⛔ unverified |
| OCR against real vendor contracts | ⛔ unverified |
| Local notification delivery | ⛔ unverified |
| Deep links from a delivered notification | ⛔ unverified |
| Location permission prompt, one-shot capture, denial path | ⛔ unverified |
| Widget rendering and refresh | ⛔ unverified |
| App Intents / Shortcuts | ⛔ unverified |
| PDF sharing via the share sheet | ⛔ unverified |
| StoreKit **Sandbox** purchase | ⛔ unverified |
| The StoreKit purchase confirmation sheet | ⛔ **unautomatable here** — StoreKit presents it out of process, so it is not in the app's accessibility tree. The UI suite asserts up to the Subscribe tap; what a purchase *unlocks* is asserted directly with a forced entitlement |
| Restore purchases against a real Apple Account | ⛔ unverified |
| Cancellation, expiry, billing retry, refund behaviour | ⛔ unverified |
| TestFlight install and purchase | ⛔ unverified |
| App icon during the purchase flow | ⛔ unverified |
| Light / dark appearance on hardware | ⛔ unverified |
| Dynamic Type at accessibility sizes on hardware | ⛔ unverified |
| VoiceOver traversal | ⛔ unverified |
| Performance with 1,000 items; scrolling; cold launch | ⛔ **not measured** |
| Migration against a real existing store | ⛔ unverified |
| **On-device model output against real contracts** | ⛔ unverified — the guardrail is tested, the model's own accuracy is not |
| Foundation Models availability on real hardware | ⛔ unverified |
| Map rendering and pin selection on device | ⛔ unverified |
| Place search results and reverse geocoding | ⛔ unverified — needs a network and a real address |
| Lock Screen and Control Centre widget rendering | ⛔ unverified |
| Legal URL liveness | ⛔ unverified — the app does not claim they are live |
| Bundle ID availability, Team ID, App Store Connect record | ⛔ unverified |

**A passing StoreKit configuration test says nothing about production purchases.** The
`.storekit` file is a local simulator fixture. Sandbox and TestFlight are separate real gates.

**What "the on-device model is tested" does and does not mean.** `ModelSuggestionValidatorTests`
and `ScanIntelligenceTests` verify the *guardrail*: that a value not printed on the page is
dropped, that a rule-based suggestion always wins, that nothing a model proposes arrives ticked.
None of them runs a model. How well Apple's model actually reads a rate table off a photographed
contract is unverified here and can only be answered on hardware, with real documents.
