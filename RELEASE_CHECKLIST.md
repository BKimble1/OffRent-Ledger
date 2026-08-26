# OffRent Ledger — Release checklist

Work top to bottom. Nothing below section 1 was, or could be, done in the environment that built
this repository, and nothing in this repository is evidence for any of it.

**Precise labels, used exactly:**

- **Locally complete** — builds, all automated gates that can run have run and passed.
- **TestFlight-ready** — additionally: signing and archive gates pass.
- **App-Store-ready** — additionally: real-device, Sandbox/TestFlight StoreKit, legal URL,
  privacy, metadata, screenshot and App Review checks are actually complete.

**Current status: TestFlight-ready, not App-Store-ready.** The app compiles for the simulator on
GitHub Actions, the unit and UI suites run there, the archive signs, and builds have been accepted
by App Store Connect. Everything in §2 onwards — anything needing a real iPhone, a real rental
contract, a Sandbox purchase or a person reading a screen — remains undone, and nothing in this
repository is evidence for any of it.

---

## 1. Make it build — done, and re-checked on every push

This section is complete and is kept here because it is what a fresh clone has to reproduce. The
Xcode project, the SwiftUI views, the SwiftData models and the StoreKit code are type-checked by
`.github/workflows/verify.yml`, which builds for the simulator and runs both test bundles on every
push. Treat a red run as this section failing again.

- [x] Open `OffRentLedger.xcodeproj` in Xcode 16 or later. It should show four targets:
      `OffRentLedger`, `OffRentLedgerTests`, `OffRentLedgerUITests`, `OffRentLedgerWidget`.
- [ ] Confirm `OffRentShared` is a member of **both** `OffRentLedger` and `OffRentLedgerWidget`.
      If the widget cannot see `RentalSummarySnapshot`, tick the widget's checkbox for that folder
      in the File Inspector. (`verify_repository.py` asserts the pbxproj expresses this, but only
      Xcode can confirm it honours it.)
- [x] Build for the simulator. Expect compile errors; fix them.
      - Concurrency findings will be **warnings**, not errors: the project is Swift 5 language
        mode with `SWIFT_STRICT_CONCURRENCY = complete`. Read them, then decide whether to move
        to Swift 6 mode.
      - If `#Predicate` complains about `contains` on a captured array, hoist the array to a
        `let` outside the predicate (`StoreQueries` already does this).
- [x] Run `swift test` at the repository root. **This must still pass**, and it is the fastest
      signal that a refactor broke the domain layer.
- [x] Run `python3 scripts/verify_repository.py`. Must pass.
- [x] Run the unit tests, then the UI tests. Fix what fails.
- [ ] Re-run `python3 scripts/generate_xcodeproj.py --check` after any project change made in
      Xcode. If it reports stale, port the change into the generator rather than leaving the two
      out of sync.

This section is complete, so the project is **locally complete** and, with the signing and
archive gates in `.github/workflows/testflight.yml` passing, **TestFlight-ready**.

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
- [ ] Add the widget in all three home-screen sizes. Confirm it shows the summary and **no
      vendor, jobsite or equipment name**.
- [ ] Add all three Lock Screen widgets — inline, circular and rectangular. Same check, and this
      is the one that matters most: a lock screen is read by whoever picks the phone up.
- [ ] Add the Control Centre button. Confirm it opens the new rental form and **creates nothing**.

### The on-device model (new)

- [ ] Scan a contract whose rates are printed as a **table** — labels on one row, figures on the
      next. The rule parser now joins a bare label to the line beneath it, so check whether the
      deterministic pass gets there on its own before crediting the model.
- [ ] Scan something that is **not** a rental agreement — a lease, a delivery note, a receipt. It
      must show `No rental details found` with Rescan / Add pages / Enter manually, and there must
      be **no button offering to use zero values** anywhere on that screen.
- [ ] Photograph a contract in portrait, close up, so the image is small. It must still be read —
      this is the orientation path that only bites below the downscale cap.
- [ ] Check every figure it proposes against the paper. Confirm none of them arrives ticked.
- [ ] Confirm the review screen names the line each value was read from, and that the line is
      really on the page.
- [ ] Turn Apple Intelligence **off** in iOS Settings and scan again. Scanning must still work,
      and the screen must say in one sentence why tables are not being read.
- [ ] Scan on a device that cannot run the model at all. Same expectation.

### Confirmation location (unchanged)

- [ ] Record a confirmation with location allowed. Confirm the row reads as a **place name**, with
      the coordinate underneath — and that the coordinate is what the evidence export carries.
- [ ] Do the same with no network. The coordinate must still be recorded and displayed.
- [ ] Deny location. The confirmation must still save.

### The walkthrough (rewritten)

- [ ] From a clean install, take the tour from the welcome screen.
- [ ] Walk it end to end with **Next only**. Confirm it never waits for you to do something in
      the app, and that the last page's button reads **Finish**.
- [ ] Tap Finish. It must dismiss itself immediately, leave no overlay, restore the tab bar, and
      land on Today. You should not have to tap anything else or swipe anything away.
- [ ] Check the Rentals tab, Rental companies and Jobsites. **All three must be empty.** The
      walkthrough is not allowed to have created anything.
- [ ] Relaunch. It must not reappear.
- [ ] Settings → Replay the walkthrough. Same behaviour, and `Skip` on page one exits cleanly.

### Reusable companies and jobsites (new)

- [ ] Rentals → `+`. Confirm the menu offers **New rental**, **New rental company** and
      **New jobsite**.
- [ ] Create a company from that menu. It must appear under Rental companies straight away.
- [ ] Start a New Rental, type an equipment name, then tap the **Rental company** row and use
      `Add New`. Save the company. **You must land back on the rental draft with the equipment
      name still in it and the new company selected.** This is the one that would be worst to get
      wrong; do it deliberately.
- [ ] Try to create the same company again with the same branch. It must name the one you already
      have rather than silently making a second.
- [ ] Create it again with a *different* branch. That must be allowed.
- [ ] Leave the form empty and read the line under the disabled Save. It must name both missing
      fields, then narrow as you fill them in.

### The jobsite map editor (new)

- [ ] Search for a real address. Results appear as you type; picking one centres the map, drops a
      pin, and fills the name with something a person would say — **never a bare postal code**.
- [ ] Search for somewhere with no street address (a rural site). Check what the name field gets.
- [ ] Turn off Wi-Fi and cellular. Search must fail gracefully and still let you drop a pin.
- [ ] Drop a pin by hand and confirm the location. Name it yourself.
- [ ] Pick a search result, then tap **Move the pin** and put it somewhere else. The address a
      search returns is often the gate rather than the pour, and "close, but not there" has to be
      fixable without starting the search again.
- [ ] Reopen that jobsite for editing. The pin and the name must be where you left them.
- [ ] Confirm no location permission prompt appears anywhere in this flow.

### The maps (new)

- [ ] Today with no rentals at all: the map card is present, with **No rentals in progress** over
      it.
- [ ] Today with a rental that has no jobsite location: the card is still present and the caption
      says how many rentals have no location.
- [ ] Tap the card anywhere — not just on a pin. It must open the full-screen map.
- [ ] `X` closes it and returns to Today in the same state.
- [ ] Search for a machine by name, by vendor equipment ID, by serial, by company, by jobsite and
      by PO number. Each must find it. Search for something you do not own: nothing, not the web.
- [ ] Select a result. The map centres, the card shows status and company, and Open and Edit both
      work.
- [ ] Put two machines at the same jobsite. The marker must carry a count and tapping it must let
      you choose between them — not bury one under the other.
- [ ] VoiceOver over a marker: it must name the entity and its status, not say "pin".

### Invoice acceptance (new)

- [ ] Attach an invoice with **no total and no lines**. On the review screen, `Accept this
      invoice` must be **disabled**, with a specific reason under it and an `Edit invoice`
      button that opens the form preloaded.
- [ ] Attach a matching invoice. Accept it. You must get immediate feedback, a confirmation, and
      a return to Audit. The rental must move to Resolved and the Audit counts must change.
- [ ] Relaunch. It must still be accepted.
- [ ] Turn the text size up to the largest accessibility setting and reopen a comparison. No label
      or figure may run off the right-hand edge.

### Editing a rental (new)

- [ ] Open any rental. **Edit** must be visible in the navigation bar.
- [ ] Everything you entered must be preloaded, including the company, the jobsite, the
      identifiers, the PO and the dates.
- [ ] Change the company. Save. Check the Rentals list, Today, the map and search all agree.
- [ ] Take a rental with no location, give it a jobsite with a place, and check it appears on the
      Today map and on the full-screen map — then relaunch and check again.
- [ ] Edit a rental that is already off rent. Its confirmation, its pickup and its attached
      invoice must be untouched, and the estimate must not start running again.

### Reminders reach the schedule without a relaunch (new, build 8)

The four derived things — the cached estimates, the widget, the Shortcuts index and the reminder
schedule — used to be rebuilt only on launch and on returning to the foreground. This is the pass
that proves the new signal works, and it is the one no simulator test can make.

- [ ] Turn reminders on. Create a rental with a scheduled end date a few days out. **Without
      backgrounding the app**, open Settings → Reminders: the planned reminder for that rental
      must already be listed.
- [ ] Edit that rental and move its scheduled end date. The planned reminder must move with it,
      again without backgrounding the app.
- [ ] Record the pickup. The reminders that no longer apply must disappear from the list.
- [ ] Restore a backup onto a phone that has other rentals on it. Every reminder, the widget and
      the Shortcuts suggestions must describe the restored data, not what was there before.


## 3. Apple accounts and signing — done, and proved by a build Apple accepted

This section used to read "none of this exists yet", with every box empty. It is out of date, and
in the direction that matters: it made the work still outstanding harder to find.

A build reaching TestFlight and reporting `processingState = VALID` is not a claim — it is Apple
saying it accepted a signed archive for this bundle. That single fact proves most of this list,
because the upload could not have happened otherwise:

- [x] `com.idlery.offrent` is registered and is this app's identifier.
- [x] The team is correct for this app. `OFFRENT_DEVELOPMENT_TEAM` reads `7GNFT94A9L`, and an
      archive signed against it was accepted. It was carried over from the owner's CoreCredit
      project; it is now verified by use rather than by assumption.
- [x] Both App IDs exist — `com.idlery.offrent` and `com.idlery.offrent.widget`. The widget ships
      inside the archive, so a missing App ID would have failed the export.
- [x] The App Group `group.com.idlery.offrent` exists and is assigned to both. Entitlements have
      to match a profile Apple issued, or signing fails.
- [x] The App Store Connect app record exists. Builds are attached to it.
- [x] An App Store Connect API key with the **App Manager** role exists, and `ASC_KEY_ID`,
      `ASC_ISSUER_ID` and `ASC_PRIVATE_KEY` are set as repository secrets. Below App Manager the
      archive fails on provisioning; it does not.
- [x] The **TestFlight** workflow runs and uploads. Its build number comes from App Store Connect
      itself — the highest it holds for this bundle, plus one — so it cannot be wrong-footed by a
      build from another pipeline.

There is still no certificate or provisioning-profile secret, and there should not be. The
workflow archives with `-allowProvisioningUpdates` and the same API key, so Xcode issues and
downloads what it needs. Three secrets to rotate instead of five, and no `.p8` or `.p12` sitting
in a repository setting.

**What a successful upload does not prove, and what is therefore still open:**

- [ ] The subscription group `OffRent Ledger Pro` and its two products, configured in App Store
      Connect:
      - `com.idlery.offrent.pro.monthly` — auto-renewable, 1 month, US $14.99
      - `com.idlery.offrent.pro.annual` — auto-renewable, 1 year, US $119.99

      An upload never touches these. The app reads prices from `Product.displayPrice` and shows
      nothing if StoreKit returns no products, so a build can be perfectly valid and still have a
      paywall with nothing on it. This is the single most likely cause of a rejection under
      guideline 3.1.2, and it cannot be checked from here.
- [ ] Localised display name, description and a review screenshot for each product. Apple's
      reviewer sees these, and a missing review screenshot is a rejection on its own.
- [ ] Assign the processed build to a tester group. The workflow uploads and stops: it does not
      assign testers and does not submit for review.

- [ ] Optionally add `APPLE_TEAM_ID`. Without it the export falls back to the team id in
      `Config/Identifiers.xcconfig`, which is what has been happening.
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

- [x] App icon: the owner's artwork is installed. Master at
      `marketing/AppIcon/OffRentLedger-AppIcon-master.png`; rebuild the App Store copy with
      `python3 scripts/prepare_app_icon.py`. It is 1024x1024 with no alpha channel, both of
      which `verify_repository.py` enforces — those are the two most common icon rejections.
- [ ] Optional: iOS 18 dark and tinted icon variants. The artwork is already dark-background so
      the default rendering is reasonable; adding variants is polish.
- [ ] Check the icon on a real device at Home Screen size — thin strokes (the clock hands, the
      tread outline) are the first thing to suffer at 60pt, and no simulator screenshot settles it.
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

- [ ] The **Verify** workflow green on the release commit.
- [ ] The UI scenarios run at least once on a simulator (see TEST_MATRIX.md).
- [ ] `swift test` green.
- [ ] `verify_repository.py` green.
- [ ] Every box in sections 1–6 ticked.
- [ ] Read `PROJECT_SOURCE_OF_TRUTH.md` §10 and confirm nothing there is still open.

Only then is the app **App-Store-ready**.

**This repository does not submit to Apple, and no part of the build that produced it did.**

---

## What is actually still in the way

This table used to be "as of the build that produced this repository", and four of its eight rows
have since been settled — by CI compiling and testing the app on every push, and by builds Apple
accepted. Leaving them listed buried the ones that still matter.

**Settled, and how:**

| Was | Settled by |
|---|---|
| The app has never been compiled. | `verify.yml` builds the app and the widget for an iPhone and an iPad simulator on every push, and runs both test suites on each. |
| `BKimble1/OffRent-Ledger` had to be created by hand. | It exists and is the origin this pushes to. |
| Bundle ID availability, Team ID correctness, App Store Connect record. | An archive signed with `7GNFT94A9L` for `com.idlery.offrent` was accepted by App Store Connect and reported `VALID`. See §3. |
| Final app icon outstanding. | The owner's artwork is installed and checked for size and alpha by `verify_repository.py`. Screenshots are still outstanding — see below. |

**Still in the way:**

| # | Blocker | Owner | Why it cannot be closed from here |
|---|---|---|---|
| 1 | The two subscription products do not demonstrably exist in App Store Connect. | Repository owner | An upload never touches them. The paywall reads `Product.displayPrice` and shows nothing when StoreKit returns no products, so the build can be valid and the paywall empty. Most likely single cause of a 3.1.2 rejection. |
| 2 | No Sandbox purchase, restore, refund or upgrade/downgrade has been exercised. | Repository owner | Needs a real Apple Account and a real transaction. The local `.storekit` file is a simulator fixture and proves nothing about any of it. |
| 3 | Nothing has run on real hardware. | Repository owner | Camera, OCR against real contracts, notification delivery and the tap that follows it, widget and Lock Screen rendering, sharing a PDF out. A simulator cannot do these. |
| 4 | `offrent.idlery.com` does not exist. | Repository owner | The app claims nothing — `legalURLsAreLive` is `false` and the legal screens render bundled Markdown. App Store Connect still wants a live privacy policy URL at submission. |
| 5 | App Store screenshots. | Designer | Required by App Store Connect; not required for TestFlight. |
| 6 | "OffRent Ledger" trademark clearance unknown. | Counsel | |
| 7 | Terms of Use sections 10, 11 and 13 need legal review. | Counsel | |

Blockers 1 through 4 are between TestFlight and submission. None of them blocks TestFlight itself.
