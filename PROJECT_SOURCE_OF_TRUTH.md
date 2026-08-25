# OffRent Ledger — Project Source of Truth

**Company:** Idlery Services LLC
**Working product name:** OffRent Ledger *(working name; trademark and App Store name
availability are UNVERIFIED — see "Open external questions")*
**Document status:** authoritative. Where this file and any other document disagree, this file wins.
**Last updated by:** Phase 6 build pass.

---

## 1. What this app is

> Know what every equipment rental is costing, capture the vendor's off-rent confirmation,
> track pickup, and check the final invoice — across every rental yard.

OffRent Ledger is a **local-first, single-user, iPhone-only record keeper** for construction
equipment rentals. It is a *ledger and evidence tool*. It is not a communication channel to a
rental vendor, and it never becomes one in version 1.

### 1.1 The truth boundary (non-negotiable)

**OffRent Ledger does not contact rental companies and does not terminate rentals.**

This sentence is a product invariant, not a disclaimer. It is enforced in three places:

| Layer | Enforcement |
|---|---|
| Copy | `AppCopy.offRentDisclosure` is the single source for the notice. Every screen that could imply vendor contact renders it. |
| Model | `RentalItemStatus.contactVendor` cannot advance to `.confirmationRecorded` without a `RentalEvent(type: .vendorConfirmationRecorded)` carrying a user-affirmed contact. See `StatusTransitionService`. |
| Tests | `Tests/OffRentDomainTests/StatusTransitionTests.swift` asserts the illegal shortcut is rejected. `scripts/verify_repository.py` fails the build on banned phrasing. |

#### Banned phrases (build-enforced)

`scripts/verify_repository.py` fails if any of these appear in user-facing Swift string literals
or in the shipped legal/marketing HTML:

- "End Rental" as a standalone control label
- "Rental successfully ended" / "Rental ended"
- "Vendor notified" / "We notified"
- "Guaranteed savings" / "Guaranteed"
- "Verified overcharge"
- "Legal proof" / "legally binding"
- "tamper-proof"

#### Required phrasing

| Concept | Approved wording |
|---|---|
| Accruing cost | "Estimated rent running" |
| Detected difference | "Possible invoice mismatch" / "Possible invoice variance" |
| Confirmation captured | "Vendor confirmation recorded" |
| Post-confirmation state | "Awaiting pickup" |
| Line needing attention | "Review this charge" |
| Any computed figure | "Based on the terms you confirmed" |

Every currency figure the app derives (rather than the user typing) is rendered through
`EstimateLabel`, which is physically incapable of drawing without an "Estimate" qualifier.

### 1.2 Explicit non-goals for version 1

Not a marketplace, not yard/fleet software, not project management, not accounting, not safety
inspection, not telematics, not a booking system, not a payment processor, not legal advice, not a
dispute service, not a chatbot.

**Not implemented, by decision:** automatic vendor off-rent submission; vendor account scraping;
vendor credentials; email inbox access; accounting/QuickBooks integrations; multi-tenant company
accounts; employee invitations; background location; telematics; equipment booking; remote push;
generative AI; cloud OCR; ads; third-party analytics; tracking SDKs; crash-reporting SDKs; any
external backend.

Anything that would expand one of those lines belongs in `docs/FUTURE_EXPERIMENTS.md`, not in v1.

---

## 2. Platform and identifiers

| Item | Value | Where it lives |
|---|---|---|
| Language | Swift, SwiftUI | — |
| Minimum OS | iOS 18.0 | `Config/Identifiers.xcconfig` → `OFFRENT_DEPLOYMENT_TARGET` |
| Devices | iPhone only (`TARGETED_DEVICE_FAMILY = 1`) | `Config/Identifiers.xcconfig` |
| Orientation | Portrait only | `Config/OffRentLedger-Info.plist` |
| Catalyst / visionOS / Android / web | **None** | — |
| Locale | US English, US App Store only for v1 | — |
| App bundle | `com.idlery.offrent` | `Config/Identifiers.xcconfig` |
| Widget bundle | `com.idlery.offrent.widget` | `Config/Identifiers.xcconfig` |
| Unit test bundle | `com.idlery.offrent.tests` | `Config/Identifiers.xcconfig` |
| UI test bundle | `com.idlery.offrent.uitests` | `Config/Identifiers.xcconfig` |
| App Group | `group.com.idlery.offrent` | `OffRentShared/SharedIdentifiers.swift` + entitlements |
| URL scheme | `offrent` | `OffRentShared/SharedIdentifiers.swift` + Info.plist |
| Keychain | *not used in v1* | — |
| Monthly product | `com.idlery.offrent.pro.monthly` | `AppConfiguration.swift` + `StoreKit/OffRentLedger.storekit` |
| Annual product | `com.idlery.offrent.pro.annual` | `AppConfiguration.swift` + `StoreKit/OffRentLedger.storekit` |
| Subscription group | `OffRent Ledger Pro` | `StoreKit/OffRentLedger.storekit` |

**Display name is centralized.** `AppConfiguration.displayName` is the only literal. Changing the
working name is a one-line edit plus the Info.plist `CFBundleDisplayName`, which reads
`$(OFFRENT_DISPLAY_NAME)` from the xcconfig. `scripts/verify_repository.py` asserts no other Swift
file hardcodes the string "OffRent Ledger" in a user-facing literal.

### 2.1 Identifier collision check

`com.idlery.offrent*` does not collide with anything in this repository or in the CoreCredit
project, which uses `com.blakekimble.corecredit*`. `scripts/verify_repository.py` fails if any
CoreCredit identifier, model name, asset name, or bundle ID appears anywhere in this repository.

**UNVERIFIED (external):** whether `com.idlery.offrent` is already registered to another Apple
Developer account, and whether "OffRent Ledger" is available as an App Store name or free of
trademark conflict. Both require a human with App Store Connect and USPTO/counsel access.

### 2.2 Signing

`DEVELOPMENT_TEAM` is `$(OFFRENT_DEVELOPMENT_TEAM)` in `Config/Identifiers.xcconfig`. The value
carried into that file (`7GNFT94A9L`) was **read from the owner's existing CoreCredit project in
this same workspace** — it is not invented — but it has **not** been verified against an App Store
Connect record for OffRent Ledger, and no App ID, provisioning profile, App Store Connect app
record, or production subscription has been created. Those are human gates (see
`RELEASE_CHECKLIST.md`).

---

## 3. Architecture

```
OffRentLedger/
  App/             app entry, root scene, deep-link routing, dependency container
  Configuration/   display name, URLs, product ids, feature flags, copy constants
  Domain/          PURE. Foundation only. No SwiftUI/SwiftData/StoreKit/Vision/UIKit.
  Persistence/     SwiftData @Model types, versioned schema, migration plan, mapping
  Services/        OCR, notifications, files, PDF, export/import, StoreKit, location, snapshot
  Features/…       one folder per tab/flow, each with view + @Observable view model
  SharedUI/        design tokens, reusable components, accessibility helpers
  Resources/       asset catalog, legal markdown, OCR fixtures
OffRentShared/     types shared by app + widget (App Group id, URL scheme, widget snapshot)
OffRentLedgerWidget/
```

### 3.1 The portable-domain rule (this is the important one)

`OffRentLedger/Domain/` and `OffRentShared/` import **Foundation and nothing else**. No Apple
UI or persistence framework. That is enforced by `scripts/verify_repository.py`.

Because of that rule, those two folders also compile as a standalone SwiftPM module,
`OffRentDomain`, declared in the root `Package.swift`:

```swift
.target(name: "OffRentDomain", path: ".", sources: ["OffRentLedger/Domain", "OffRentShared"])
```

**The same files** are compiled twice: once by Xcode into the app target, once by SwiftPM. There is
no duplication and no copy step. The consequence is that the money math, the status machine, the
rollover engine, the invoice mismatch engine, the OCR text parser, the reminder planner, the
entitlement policy and the export/import codecs are **testable and were actually executed on a
platform without Xcode** (see `TEST_MATRIX.md` §A for what really ran).

Everything that needs Apple frameworks is a thin adapter over that core.

### 3.2 Boundaries and injection

Every external dependency is a protocol, resolved through `AppDependencies` and injected into the
SwiftUI environment. There is no global mutable singleton holding business state.

| Protocol | Real implementation | Test/preview double |
|---|---|---|
| `Clock` | `SystemClock` | `FixedClock`, `AdvanceableClock` |
| `DocumentTextRecognizing` | `VisionTextRecognizer` (Vision, on-device) | `StubTextRecognizer` (fixture text) |
| `NotificationScheduling` | `UserNotificationScheduler` | `RecordingNotificationScheduler` |
| `SubscriptionProviding` | `StoreKitSubscriptionService` (StoreKit 2) | `StubSubscriptionService` |
| `FileStoring` | `AppFileStore` (Application Support, protected) | temp-directory instance |
| `OneTimeLocationProviding` | `CoreLocationOneShotProvider` | `StubLocationProvider` |
| `EvidenceRendering` | `PDFEvidenceRenderer` (PDFKit) | `EvidencePacket` model asserted directly |
| `SnapshotPublishing` | `AppGroupSnapshotPublisher` | in-memory publisher |

Concurrency: `Decimal` for all money, `actor` for the file store and the OCR pipeline, `@MainActor`
for view models, structured cancellation for OCR, no force unwraps on production paths
(build-enforced by `verify_repository.py`), `Logger` with `privacy: .private` on anything derived
from a user document.

### 3.3 Derived state has one owner

Four things are computed from the store rather than stored: each rental's cached estimate, the
widget snapshot, the Shortcuts/App Intents index, and the reminder schedule. `RootView.refresh()`
rebuilds all four from scratch. There is no incremental path, because an incremental path is a
second place for the truth to live.

It runs on launch, on returning to the foreground, and — since build 8 — whenever a screen calls
`dependencies.derivedStateNeedsRefresh()` after writing something the four depend on. Before that
last one there was a real gap: a rental created and then edited in one sitting had no reminder
until the app next came back from the background, which for somebody who adds a rental and puts
the phone down is exactly the run where the reminder mattered. §9 requires an edit to reach the
reminders.

**The rule for anything new: if it changes a rental's status, terms or scheduled end date, it
calls `derivedStateNeedsRefresh()` after `context.save()`.** A counter on `AppDependencies` rather
than a closure, so nothing needs a reference back to the root view — and `refresh()` never touches
the counter, so there is no path by which recomputing triggers another recomputation.

---

## 4. Domain model

Nine entities, on schema V3. SwiftData `@Model` classes live in `Persistence/`; each has a matching pure value
type in `Domain/` used by the engines and by export/import.

| Entity | Key fields |
|---|---|
| `Vendor` | id, name, branch, **contactName**, phone, email, **address**, link, standardNotes, created/modified |
| `JobSite` | id, name, projectIdentifier, address, notes, placeName, latitude, longitude, created/modified |
| `RentalAgreement` | id, vendor, jobsite, agreementNumber, **purchaseOrderNumber**, startDate, scheduledEndDate, disputeWindowDaysOverride, notes, attachments, created/modified |
| `RentalItem` | id, agreement, equipmentName, equipmentClass, vendorEquipmentIdentifier, serialNumber, deliveryDate, status, dailyRate, weeklyRate, fourWeekRate, billingBasis, nextRolloverDate, expectedNextIncrement, includedUsageNotes, manualRolloverOverride, estimatedRunningCost, meterUnit, notes, created/modified |
| `RentalEvent` | id, item, type, timestamp, detail, contactMethod, vendorRepresentative, confirmationNumber, locationSnapshot, created |
| `EvidenceAsset` | id, owner ref, relativePath, mediaType, displayName, capturedAt, coordinate?, caption, sha256, thumbnailPath |
| `VendorInvoice` | id, agreement, invoiceNumber, receivedDate, billedThroughDate, category totals, invoiceTotal, attachment, reviewStatus, notes |
| `InvoiceLine` | id, invoice, category, detail, quantity, unitPrice, amount, appearedInContract, reviewState |
| `Discrepancy` | id, invoice/line, type, expectedAmount, invoicedAmount, difference, explanation, status, resolutionNotes, created/resolved |

**`Vendor` and `JobSite` are reusable records, and the UI treats them as such.** A rental
*references* a company and, optionally, a jobsite; it never carries a copy of either. The Rentals
tab creates both directly, `New Rental` and `Edit Rental` select from them through the same
editors, and creating one from inside a rental draft returns to that draft with the new record
selected. Duplicate creation is guarded by `CompanyMatching` on a normalised name plus branch —
narrow on purpose, so that two branches of one chain remain two records.

**Equipment is not an entity and will not become one.** A machine *is* a `RentalItem`. Its marker
on the map, its row in map search and its detail card are all derived from that rental, so there
is nothing to keep in step and no second table to drift.

**`RentalAgreement.agreementNumber` and `purchaseOrderNumber` are different strings.** The first is
the vendor's number for the paperwork; the second is the contractor's own reference. Both appear
on an invoice, both find a rental in search and on the map, and conflating them would lose one.

`EvidenceAsset.sha256` is an **integrity aid only**. The UI labels it "File checksum (integrity aid
only)". It is never described as tamper-proof, authoritative, or legally meaningful. Build-enforced.

Deletion: `RentalAgreement` cascades to items → events → owned assets; the file store's
`reconcile(referencedPaths:)` sweeps unreferenced blobs and is exercised by
`AssetReconciliationTests`.

---

## 5. Status model

Rental-specific vocabulary. **No CoreCredit workflow label is reused.**

`Draft → Active → Contact Vendor → Confirmation Recorded → Awaiting Pickup → Picked Up →
Awaiting Invoice → Invoice Review → Needs Follow-Up → Resolved → Archived`

Authoritative transition table: `docs/STATUS_TRANSITIONS.md`, generated from
`StatusTransitionService.allowedTransitions` so the doc cannot drift from the code.

Rules:
- Every transition returns `Result<RentalItemStatus, TransitionRejection>`. Invalid transitions are
  rejected, never silently coerced.
- Backwards movement requires an explicit `.reopen` intent, which writes a `.reopened` event.
- `.contactVendor → .confirmationRecorded` additionally requires `ConfirmationEvidence` with
  `userAffirmedContact == true` and a non-empty confirmation number **or** an explicit
  "no number given" acknowledgement.
- `.archived` is terminal except via `.reopen`.

---

## 6. Rate engine

Two modes. **Manual rollover is the default**, because it assumes the least.

**Manual mode** — the user confirms current billing basis, next rollover date/time, the expected
next increment, and optionally the subsequent interval. The engine never guesses.

**Simple schedule mode (opt-in)** — daily, 7-day weekly, or 28-day four-week only. Every generated
rollover is presented for confirmation and can be overridden.

The engine explicitly does **not**: pick the cheapest rate combination, interpret arbitrary vendor
contract clauses, or compute overtime/excess-meter-hour charges. Excess-hour terms are stored as
`includedUsageNotes` for manual review.

All arithmetic uses `Decimal` with `NSDecimalRound(_:_:2:.bankers)` at exactly one place
(`Money.rounded`). Day counts use `Calendar.dateComponents` on the user's calendar, which is why
DST works: a "day" is a calendar day boundary, not 86 400 seconds. `RentalRateEngineTests` proves
the spring-forward and fall-back cases.

---

## 7. Scanning and OCR

VisionKit `VNDocumentCameraViewController`, Vision `VNRecognizeTextRequest`, PDFKit, PhotosPicker,
`fileImporter`. **On device only. Nothing is transmitted.**

The pipeline is deliberately split so the hard part is testable:

```
image/PDF ──VisionTextRecognizer──▶ RecognizedDocument (raw text + line boxes)
                                          │
                          DocumentTextParser (PURE, Foundation-only)
                                          ▼
                            [FieldSuggestion] (value + confidence + provenance)
                                          ▼
                              ScanReviewView — always shown, always editable
                                          ▼
                                  explicit Save by the user
```

`DocumentTextParser` is pure text→suggestions, so it is unit-tested against synthetic fixtures in
`OffRentLedger/Resources/OCRFixtures/` with **no camera and no simulator**. Only suggestions with
confidence ≥ `FieldSuggestion.preselectThreshold` (0.80) are preselected; the rest are shown
unchecked. Raw recognized text is retained separately from normalized suggestions.

Each suggestion carries where it came from: the line, the page, and the range of the value inside
that line. On a five-page invoice the rate table and the summary are nowhere near each other, and
"read from: TOTAL DUE $3,214.00" with no page is not something a user can go and check.

Three rules the parser holds to, each of which exists because a fixture caught it failing:

- **A label and its value need not share a line.** A second pass joins a line with no digits in it
  to the line beneath and re-runs the rules, at slightly lower confidence so an inline match of
  the same rule always wins. `RENTAL AGREEMENT NUMBER` / `NG-77304` is a real vendor layout, and
  before this pass the field simply went missing.
- **A rate table may be printed with dotted leaders.** `DAY .................. 465.00` is matched
  by the shared label-to-value gap, which permits a colon, an equals, or a run of two or more
  leader characters — two, so a single stray dot cannot join two unrelated things.
- **A garbled amount is refused, not truncated.** Vision reads `4,18O.00` for `4,180.00` — a
  capital O where a zero belongs — and a pattern that simply stops at the first non-digit captures
  `4,18`. That is $418 for a $4,180 line: a plausible number, in the right place, at high
  confidence. The amount pattern now requires the number to actually end where it stops, so the
  field arrives empty with the raw line visible under **Recognised text**.

**What the review screen will not say.** When nothing on a document maps to a field that kind of
document can carry, the screen is `No rental details found` with `Rescan`, `Add pages` and
`Enter manually` — never a commit button offering to use zero values. `ScanOutcome` decides;
`ScanReviewCopy.useValues(selected:)` returns `nil` rather than a string for a count of zero, so
the old wording cannot come back by accident.

### 7.1 The on-device model

The rule parser matches a label against a figure **on the same line**, which is why rate tables
have never worked: a contract prints the labels on one row and the figures on the next. Apple's
Foundation Models framework closes that gap, running entirely on the device
(`FoundationModelDocumentIntelligence`, `#if canImport(FoundationModels)` and iOS 26+). A device
or a build without it falls back to `UnavailableDocumentIntelligence`, which proposes nothing —
scanning behaves exactly as it did before.

**The model proposes; the page decides.** Nothing it returns is trusted. Every proposal goes
through `ModelSuggestionValidator`, in the portable layer, which drops it unless:

1. the line it quotes is a line the recogniser actually produced;
2. the value appears in that text character for character, once whitespace, case and typographic
   quotes are normalised;
3. it parses as the type its field requires;
4. no rule-based suggestion already claims that field — the parser is the floor, and where the two
   disagree the app keeps the one whose reasoning it can print;
5. its confidence is capped below `preselectThreshold`, so **nothing a model proposed ever arrives
   ticked**. That holds by construction rather than by anybody remembering to check it.

A proposal failing any of those is dropped silently. There is no "the model thought" state in
this app.

**Scan results are never auto-committed.** `ScanReviewViewModel.commit()` is the only path that
writes, it is only reachable from the Save button, and `ScanReviewCommitTests` asserts that
constructing the view model and disposing of it writes nothing.

---

## 8. Privacy

No account, no login, no server, no analytics, no ads, no tracking, no third-party crash reporter,
no cloud OCR, no background location. The app is fully usable with every permission denied.

- Records: SwiftData store in Application Support.
- Documents/photos: `AppFileStore` under `Application Support/OffRentLedger/Evidence/`, with
  `FileProtectionType.completeUntilFirstUserAuthentication`, excluded from iCloud backup only where
  the user opts out.
- Location: requested **only** when the user taps "Add current location"; `requestLocation()`
  one-shot, foreground, `kCLLocationAccuracyHundredMeters`. Denial never blocks a flow. No route
  history, ever. The captured coordinate is displayed as a reverse-geocoded place name for
  legibility, but the **coordinate stays the record** — the name is Apple's opinion about a point
  and arrives over the network.
- Places: job sites are located with `MKLocalSearch`, which is a map query and carries no rental
  data. The search is biased towards the **map's visible region**, not the device's location, so
  the jobsite editor needs no location permission at all. A pin the user drops by hand is
  reverse-geocoded for legibility only, and the coordinate they placed stays the record whether
  or not that request returns. A confirmation's location is still a measured GPS fix and never a
  place picked off a list: "where this phone was when the call was made" and "a place the user
  chose" are different claims, and only one of them is evidence.
- The maps: the Today card and the full-screen operations map draw only what is in the store, and
  the operations map's search field searches the store — never the web. A record with no
  coordinate is listed as `No location set` and is never drawn at a substituted one.
- The on-device model: `SystemLanguageModel`, local. No page, no figure and no company name
  leaves the device, which is also why a cloud model was never an option here.
- Photos: `PhotosPicker` (no library authorization prompt). Camera authorization requested only on
  a camera tap.
- Deletion: per-attachment, per-rental, and "Delete all app data" (records + files + notifications
  + App Group snapshot).
- Export: structured JSON backup, CSV rental summary, per-rental evidence PDF.
- Import: preview screen showing exactly what would be added/skipped before anything is written.

**Cancelling Pro never deletes or hides a record.** Entitlement loss only prevents creating an
*additional* open rental item beyond the free limit.

---

### 8.0.1 The walkthrough

Seven pages, advanced by `Next`, `Back`, `Skip` and `Finish`. It **writes nothing**: no sample
rental, no company, no jobsite, no defaults changed. The figures on its illustrations are
obviously illustrative and are never persisted, and a UI test asserts that walking the whole
thing leaves an empty store empty.

It replaced a guide that read a real rental's status and would not advance until the user
performed each step of the workflow for real. That could not be completed on the day somebody
installs the app, and `Skip` was its only exit. Completion is recorded as a *version*
(`WalkthroughScript.version`) rather than a flag, so a materially rewritten walkthrough can be
shown once to an existing user and never again.

---

### 8.1 What the Home Screen and Lock Screen can show

`RentalSummarySnapshot` carries counts, one aggregate figure and one date, and has **no field**
for a machine, a jobsite, a rental company or an invoice amount. That is what makes the accessory
(Lock Screen) widget families safe: a lock screen is read by whoever picks the phone up, and the
guarantee is structural rather than a rule to remember while writing a new layout.

Supported: `systemSmall`, `systemMedium`, `systemLarge`, `accessoryRectangular`,
`accessoryCircular`, `accessoryInline`, plus a Control Centre `ControlWidget` that opens the new
rental form and creates nothing.

---

## 9. Monetization

Free: **one open (unresolved) rental item**, full manual workflow on it, and unrestricted editing,
resolving, deleting and viewing of everything that already exists.

Pro: unlimited open items, invoice-audit workflow, full evidence PDF export, widget, advanced
reminders, complete history export.

Products: `com.idlery.offrent.pro.monthly` ($14.99) and `com.idlery.offrent.pro.annual` ($119.99),
one subscription group, annual marked as the better value without countdowns, pre-selection, or
pressure. **Displayed prices always come from `Product.displayPrice`** — the dollar figures above
appear only in `StoreKit/OffRentLedger.storekit` (a local test file) and in this document.

Entitlement is derived from `Transaction.currentEntitlements` with `VerificationResult.verified`
only. Unverified transactions are ignored. Offline, the last verified entitlement is honoured.

---

## 10. Known-unverified gates

Nothing in this repository proves any of the following. They are human/device gates.

**Cannot be verified in this environment at all** (no macOS, no Xcode, no device):
Xcode compilation of the app/widget/test targets · simulator run · UI test execution ·
archive/signing · live document camera · photo & PDF import · OCR on real contracts ·
notification delivery · deep links from notifications · location prompts · widget refresh ·
PDF sharing · StoreKit Sandbox purchase · restore · cancellation behaviour · TestFlight ·
app icon during purchase · light/dark on hardware · performance measurements.

**Cannot be verified without external accounts:** bundle-ID availability · App Store Connect
record · production subscription configuration · legal URL liveness · trademark clearance.

See `RELEASE_CHECKLIST.md` for the ordered list a human must work through, and `TEST_MATRIX.md`
for the precise distinction between "written", "executed", and "passed".

---

## 11. Open external questions

1. Is "OffRent Ledger" clear of trademark conflict and available on the US App Store?
2. Is `com.idlery.offrent` free in the target Apple Developer account?
3. Is `7GNFT94A9L` the correct team for Idlery Services LLC, or is a separate entity account wanted?
4. Will `offrent.idlery.com` be stood up before submission? Nothing in the app claims it is live —
   `AppConfiguration.legalURLsAreLive` is `false`, and the in-app legal screens render the bundled
   Markdown instead of linking out until that flag is flipped.
5. Final marketing artwork: the app icon is now the owner's own artwork — an orange excavator
   with a clock face on graphite. Master at `marketing/AppIcon/OffRentLedger-AppIcon-master.png`;
   the 1024x1024 App Store copy in the asset catalog is produced by
   `scripts/prepare_app_icon.py` and checked for size and alpha by `verify_repository.py`.
   Still outstanding: App Store screenshots, and optionally the iOS 18 dark and tinted icon
   variants (the artwork is already dark-background, so this is a refinement, not a gap).
