# OffRent Ledger — Release checklist

Work top to bottom. Nothing below section 1 was, or could be, done in the environment that built
this repository, and nothing in this repository is evidence for any of it.

**Precise labels, used exactly:**

- **Locally complete** — builds, all automated gates that can run have run and passed.
- **TestFlight-ready** — additionally: signing and archive gates pass.
- **App-Store-ready** — additionally: real-device, Sandbox/TestFlight StoreKit, legal URL,
  privacy, metadata, screenshot and App Review checks are actually complete.

**Current status: none of the three.** The portable domain layer is complete and tested; the app
has never been compiled. See §1.

---

## 1. Make it build — do this first

Everything else waits on this. The Xcode project, the SwiftUI views, the SwiftData models and the
StoreKit code have **never been type-checked**, because the build machine had no Xcode.

- [ ] Open `OffRentLedger.xcodeproj` in Xcode 16 or later. It should show four targets:
      `OffRentLedger`, `OffRentLedgerTests`, `OffRentLedgerUITests`, `OffRentLedgerWidget`.
- [ ] Confirm `OffRentShared` is a member of **both** `OffRentLedger` and `OffRentLedgerWidget`.
      If the widget cannot see `RentalSummarySnapshot`, tick the widget's checkbox for that folder
      in the File Inspector. (`verify_repository.py` asserts the pbxproj expresses this, but only
      Xcode can confirm it honours it.)
- [ ] Build for the simulator. Expect compile errors; fix them.
      - Concurrency findings will be **warnings**, not errors: the project is Swift 5 language
        mode with `SWIFT_STRICT_CONCURRENCY = complete`. Read them, then decide whether to move
        to Swift 6 mode.
      - If `#Predicate` complains about `contains` on a captured array, hoist the array to a
        `let` outside the predicate (`StoreQueries` already does this).
- [ ] Run `swift test` at the repository root. **This must still pass**, and it is the fastest
      signal that a refactor broke the domain layer.
- [ ] Run `python3 scripts/verify_repository.py`. Must pass.
- [ ] Run the unit tests, then the UI tests. Fix what fails.
- [ ] Re-run `python3 scripts/generate_xcodeproj.py --check` after any project change made in
      Xcode. If it reports stale, port the change into the generator rather than leaving the two
      out of sync.

Once this section is complete, the project is **locally complete**.

---

## 2. Device and accessibility pass (a real iPhone, not a simulator)

- [ ] Cold launch straight into a usable Today tab.
- [ ] Create a rental entirely by hand with camera, photos, location and notifications **all
      denied**. The whole workflow must work.
- [ ] Scan a real rental contract with the document camera. Check what the review sheet suggests
      against the paper.
- [ ] Scan a real invoice. Confirm no value is preselected that you would not have accepted.
- [ ] Import a PDF invoice exported from a vendor's billing system.
- [ ] Turn on each reminder; confirm the permission prompt appears **only then**.
- [ ] Wait for a reminder to fire; tap it; confirm it lands on the right rental item.
- [ ] Tap "Add current location", deny, and confirm the flow continues.
- [ ] Tap it again, allow, and confirm one coordinate is stored and no tracking follows.
- [ ] Add the widget. Confirm it shows the summary and **no vendor, jobsite or equipment name**.
- [ ] Lock the phone and look at the widget on the lock screen. Same check.
- [ ] Run each App Intent from Shortcuts. Confirm the confirmation intent **opens the sheet and
      records nothing**.
- [ ] Generate an evidence packet and read **every page**. Check the disclaimer, the timeline, the
      photos and the invoice comparison.
- [ ] Share the packet by AirDrop and by email.
- [ ] Export CSV; open it in Numbers and in Excel; confirm the amount columns sum.
- [ ] Export a backup, delete all data, re-import, confirm the preview counts are right.
- [ ] VoiceOver: traverse Today, Rentals, item detail, Contact Vendor, confirmation, pickup,
      invoice review, paywall and settings. Every control announced; no duplicate or orphaned
      elements.
- [ ] Dynamic Type at the largest accessibility size on every screen above. Nothing clipped,
      nothing unreachable, no hit target under the keyboard.
- [ ] Light and dark. Bright sunlight if you can get it — this is a jobsite app.
- [ ] Smallest supported iPhone and largest current iPhone.
- [ ] Reduce Motion on.
- [ ] Create 1,000 rental items (import a generated backup) and scroll the list. **Measure** it in
      Instruments; do not assume it is fine.

---

## 3. Apple accounts and signing — none of this exists yet

- [ ] Confirm `com.idlery.offrent` is available, or choose another and change
      `OFFRENT_BUNDLE_PREFIX` in `Config/Identifiers.xcconfig` (one edit).
- [ ] Confirm the team. `OFFRENT_DEVELOPMENT_TEAM` currently reads `7GNFT94A9L`, **carried over
      from the owner's existing CoreCredit project and not verified against anything for this
      app**. Decide whether Idlery Services LLC should have its own account.
- [ ] Create App IDs: `com.idlery.offrent` and `com.idlery.offrent.widget`, both with the App
      Groups capability.
- [ ] Create the App Group `group.com.idlery.offrent` and assign it to both.
- [ ] Create the App Store Connect app record.
- [ ] Create the subscription group `OffRent Ledger Pro` with:
      - `com.idlery.offrent.pro.monthly` — auto-renewable, 1 month, US $14.99
      - `com.idlery.offrent.pro.annual` — auto-renewable, 1 year, US $119.99
      - Localised display names and descriptions, and a review screenshot for each.
- [ ] Create an App Store Connect API key and a distribution certificate; add them to Codemagic as
      the environment groups `offrent_appstore` and `offrent_signing`.
- [ ] Run `offrent-testflight`. Its preflight step will refuse until all of the above exists.

After a successful signed archive, the app is **TestFlight-ready**.

---

## 4. Legal, privacy and metadata

- [ ] Decide whether `offrent.idlery.com` will exist. If yes: deploy `Website/` (GitHub Pages
      from that folder, or any static host), **load every URL in a browser**, then set
      `AppConfiguration.legalURLsAreLive = true`. `verify_repository.py` fails while that flag is
      true, by design — remove that guard in the same commit, deliberately.
- [ ] If no website: the App Store privacy policy URL is still required. The bundled text in
      `OffRentLedger/Resources/Legal/` is the source; publish it somewhere and use that URL.
- [ ] Have a lawyer read `TermsOfUse.md`. Section 10 (no warranty), section 11 (liability cap) and
      section 13 (Texas governing law) are placeholders written by an engineer, not counsel.
- [ ] Trademark: clear "OffRent Ledger" for use and for the App Store name. **Unverified.**
- [ ] App Store privacy label: select **Data Not Collected**. Confirm that is still true — the
      app has no SDK, no network client and no analytics, and `verify_repository.py` checks for
      all three, but the label is a legal declaration and needs a human to sign it.
- [ ] Age rating, category (Business or Productivity), keywords, subtitle.
- [ ] Screenshots for every required size. Show real screens, not mock-ups, and do not show a
      figure without its "Estimate" qualifier.
- [ ] App Review notes: state plainly that the app does not contact rental companies, that its
      figures are estimates, and how to reach the paywall (Settings › Subscription › See Pro).
- [ ] Provide a demo account: not applicable — there are no accounts. Say so in the notes.

---

## 5. Artwork

- [ ] The shipped icon is an **original placeholder** generated by `scripts/generate_assets.py`
      (orange octagon, graphite clock hand). It is legally clean and renders correctly, but it is
      not finished brand work. Commission or design the real mark.
- [ ] Marketing screenshots and any App Store promotional artwork.

---

## 6. Sandbox and TestFlight purchase gates

A passing StoreKit **configuration** test proves the entitlement logic. It proves nothing about
production purchases. All of the following are separate, real gates:

- [ ] Sandbox: buy monthly. Confirm Pro unlocks and the status screen shows what StoreKit gave it.
- [ ] Sandbox: buy annual.
- [ ] Sandbox: cancel; wait for expiry; confirm the app drops to free **and every existing record
      is still editable, resolvable, exportable and deletable**.
- [ ] Sandbox: restore purchases on a second device.
- [ ] Sandbox: request a refund; confirm revocation is handled.
- [ ] Sandbox: upgrade monthly → annual and downgrade back.
- [ ] Airplane mode with an active subscription: confirm Pro stays on via the last verified
      entitlement, and that the status says "Active (offline)".
- [ ] TestFlight: install and purchase. Confirm the **app icon** appears correctly in the purchase
      sheet — a missing icon there is a common rejection.
- [ ] Confirm no review prompt appears after a purchase.

---

## 7. Final gates before submission

- [ ] `offrent-full-release` green.
- [ ] `offrent-targeted-ui` green.
- [ ] `swift test` green.
- [ ] `verify_repository.py` green.
- [ ] Every box in sections 1–6 ticked.
- [ ] Read `PROJECT_SOURCE_OF_TRUTH.md` §10 and confirm nothing there is still open.

Only then is the app **App-Store-ready**.

**This repository does not submit to Apple, and no part of the build that produced it did.**

---

## Known outstanding blockers, as of the build that produced this repository

| # | Blocker | Owner |
|---|---|---|
| 1 | The app has never been compiled. No macOS or Xcode was available. | Whoever opens it in Xcode |
| 2 | `BKimble1/OffRent-Ledger` had to be created by hand — the GitHub App in that session could not create repositories (403). | Repository owner |
| 3 | Bundle ID availability, Team ID correctness, App Store Connect record: all unverified. | Repository owner |
| 4 | Production subscription products do not exist. | Repository owner |
| 5 | `offrent.idlery.com` does not exist. The app correctly claims nothing. | Repository owner |
| 6 | "OffRent Ledger" trademark clearance unknown. | Counsel |
| 7 | Final app icon and marketing artwork outstanding. | Designer |
| 8 | Terms of Use sections 10, 11 and 13 need legal review. | Counsel |
