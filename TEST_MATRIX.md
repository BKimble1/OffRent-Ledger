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

**323 tests. 323 passed. 0 failed.** Last run 2026-08-25 against commit `8eb4c7b`.

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
| `EntitlementPolicyTests` | 9 | ✅ pass | Free limit; **every guarantee that entitlement never removes access to existing records** |
| `CSVExportTests` | 8 | ✅ pass | RFC 4180 quoting, formula-injection neutralisation, blank-not-zero for incomplete estimates |
| `EvidencePacketTests` | 6 | ✅ pass | Disclaimer denies every prohibited claim; completeness reporting |
| `MoneyParsingTests` | 6 | ✅ pass | Accepted and rejected forms; banker's rounding; cent-level equality |
| `SnapshotBuilderTests` | 6 | ✅ pass | Aggregation; **the widget snapshot cannot carry identifying detail** |
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
| `python3 scripts/verify_repository.py` | ✅ 47 invariant checks, 0 problems |
| `python3 scripts/check_swift_call_sites.py` | ✅ 115 types with initialisers and 168 static functions; **every call site in the repository resolves, by label and by arity**, across typealiases, extension initialisers and `@Model` classes. 0 findings. |
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

## C. Executed on the simulator — the UI suite

The suite ran for the first time on 2026-08-24 and reached green on commit `b3057d1`
(GitHub Actions run `32797297734`). Before that it had never launched the app at all, and the
eleven runs it took to get there are recorded in the commit history from `c9240b0` to `b3057d1`.

It found two real defects that no unit test could have: an invoice with a live mismatch on
screen could be accepted without a word, and a control whose centre sat inside the tab bar
reported `isHittable == true` while a tap on it did nothing.

**Rewritten in this change.** The suites below reflect the flows as they now are — a plus that
is a menu, a company that is a record rather than four text fields, a walkthrough that ends.

| Suite | Tests | Status | Covers |
|---|---:|---|---|
| `CoreWorkflowUITests` | 2 | ✅ green at `b3057d1`, rewritten | Manual creation + relaunch, now through the company picker; full workflow to resolution with zero variance |
| `MismatchUITests` | 2 | ✅ green at `b3057d1`, rewritten | Extra-day mismatch survives relaunch; **scan review never saves without confirmation** |
| `EntitlementUITests` | 3 | ✅ green at `b3057d1`, rewritten | Free limit, Pro unlock, entitlement loss |
| `AccessibilityUITests` | 4 | ✅ green at `b3057d1` | Tabs labelled, estimate spoken as an estimate, disclosure readable, status spoken |
| `OnboardingUITests` | 5 | ✅ **5 passed** at `78a8a39` | **§12.16.** The whole walkthrough on Next and Finish alone; it dismisses itself; Back is absent on page one rather than dead; it is not shown twice; **and it created no rental, no company and no jobsite** |
| `ReusableRecordsUITests` | 5 | ✅ **5 passed** at `b671f4f` | **§12.1–3.** The plus offers all three; a company made from Rentals is selectable in a draft; one made *inside* a draft returns to it selected with the draft intact; a disabled Save names the missing field; the jobsite editor is a map |
| `MapAndEditingUITests` | 7 | ⚠️ 3 passed, 4 failed at `b671f4f`; all four traced to the three defects below | **§12.6–9, §12.15.** Today keeps the map with no rentals and with unplaced ones; the card opens full screen and X closes it; the legend opens; search finds the user's own machine; a rental with no coordinate says `No location set`; an edit survives a relaunch; the editor reaches company and jobsite |
| `LayoutObstructionUITests` | 3 | ✅ **3 passed** at `b671f4f` | **§12.17.** The save bar stays above the keyboard on the longest form; Today scrolls clear of the tab bar; the map's close button and search field clear the status bar and the home indicator |
| `InvoiceAcceptanceUITests` | 3 | ⚠️ 3 failed at `b671f4f`, all on defect 1 below | **§12.13–14.** A valid invoice is accepted from Audit, the counts move, and it is still accepted after a relaunch; an empty one is disabled with a specific reason and an `Edit invoice` route that opens the form; no comparison row runs past the right edge |

**35 UI test methods.** The four suites added for this change had never run at all until
`cec8638` — the workflow names its UI suites explicitly with `-only-testing:`, and the new ones
were not on the list. CI reported "Executed 17 tests" and looked exactly like a pass.

`verify_repository.py` now fails if a `XCTestCase` subclass in the UI target is not named in
that step, and if the step names one that does not exist. Both directions were proved by breaking
them.

### What run 32810021653 (`b671f4f`) actually found

35 executed, 1 skipped, **13 failures — and every one of the thirteen came from three defects**,
none of which was in the feature the failing test was named after. The accessibility-tree dump
each failure prints is what made them separable; without it the same thirteen read as thirteen
unrelated timeouts.

1. **`rentals.root` was not in the tree at all.** `RentalsView` put it on its `List` and then put
   `rentals.search` on the `.searchable` below it. `.accessibilityIdentifier` sets one property
   on one element, so the second call replaced the first: the dump shows
   `CollectionView, identifier: 'rentals.search'` and no `rentals.root` anywhere. Eleven tests
   waited eight seconds for it and reported "the rentals list never appeared" while the rentals
   list was plainly on screen. The `.searchable` field needs no identifier — XCUITest addresses
   it as `app.searchFields` — so the duplicate is gone, and
   `check_one_identifier_per_modifier_chain` now fails the build on a second identifier in one
   modifier chain.

2. **A stack that names itself renames its children.** An accessibility modifier on a plain
   `VStack`/`HStack`/`ZStack` is pushed down onto everything inside it. The operations map's
   result list carried `map.searchResults`, so the row inside it lost `map.searchResult` — the
   dump shows the row present, correct and renamed:
   `Button, identifier: 'map.searchResults', label: 'Rental, Skid Steer Loader, Active, at
   Ridgeline Phase 2, No location set'`. The detail card was about to do the same to `Open`,
   `Edit` and `Add a location`. `.accessibilityElement(children: .contain)` before the identifier
   is the fix — the same one the welcome screen had already needed — and
   `check_container_identifiers_do_not_shadow_children` now requires it. `List`, `Form`,
   `ScrollView` and `Group` are exempt on evidence, not assumption: CI dumps show their children
   keeping their own identifiers.

3. **A `Form` row below the fold is not in the accessibility tree at all.** Not off screen —
   absent, because the row has never been built. `expect` on `addRental.dailyRate` therefore
   failed on existence eight seconds before `tapInContent` could have scrolled to it. The dump
   proves the rest of the form was there and Save was enabled. `reveal(_:)` scrolls until the
   element exists; `revealAndTap` then hands off to `tapInContent`.

Two test-side defects came out of the same reading. A rentals row is one combined accessibility
element whose label is the whole row, so `staticTexts["Mini Excavator"]` is not what a row looks
like — and `XCTAssertFalse(app.staticTexts["Skid Steer Loader 75HP Closed Cab"].exists)` in
`MismatchUITests` was therefore passing whether or not the scan had written a rental. Both now go
through `rentalIsListed(_:)`, which matches a label prefix across buttons and static texts.

**What the UI suite still cannot cover, and why:**

| §12 gate | Why not automated |
|---|---|
| 5 — a manually dropped pin when search has no result | Dropping a pin means tapping a coordinate on a live `MKMapView`, and the "search has no result" half needs the network to be reachable but unhelpful. It is a device pass in `RELEASE_CHECKLIST.md`. |
| 10–11 — a real agreement and a real invoice through the camera | Covered deterministically at the parser, which is the layer that can be wrong. The camera is a device pass. |
| 19 — simulator launch | Covered by the UI suite existing at all: it launches and drives the app. Compilation alone is never treated as proof. |

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
