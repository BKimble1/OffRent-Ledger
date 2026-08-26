# Marketing screenshots

Two consumers, one folder, told apart by their filenames.

| Prefix | Goes into | Named by |
|---|---|---|
| `appstore-*.png` | the six App Store templates in `marketing/AppStore/` | `OffRent-AppStore-Template-Placement-Guide.md` |
| everything else | the website's reserved frames | `RESERVED_SHOTS` in `scripts/generate_website.py` |

**Nothing in here is drawn.** Every file is a capture of the running app, or of a real iOS Home
Screen. The templates carry blank openings on purpose, and
`scripts/validate_appstore_templates.py` samples every one of them and fails if anything has been
painted into it — so a fabricated screen cannot reach the gallery by being pasted into a master.

---

# The App Store gallery

Seven captures fill seven openings across six templates. Six of them come out of one command; the
seventh has to be taken by hand, and cannot honestly be taken any other way.

| File | Opening | Screen | How |
|---|---|---|---|
| `appstore-01-today.png` | 1 · `screen-1` | Today dashboard | automated |
| `appstore-02-rentals.png` | 2 · `screen-1` (back) | Rentals list | automated |
| `appstore-02-home-screen-widget.png` | 2 · `screen-2` (front) | iOS Home Screen with the medium OffRent Summary widget | **by hand, on a device** |
| `appstore-03-off-rent-proof.png` | 3 · `screen-1` | A confirmed rental's detail, at Off-rent confirmation | automated |
| `appstore-04-operations-map.png` | 4 · `screen-1` | Operations Map with an Awaiting Pickup card open | automated |
| `appstore-05-scan-review.png` | 5 · `screen-1` | Scan Review | automated |
| `appstore-06-invoice-review.png` | 6 · `screen-1` | Invoice Review, expected against invoiced | automated |

## The one command

```sh
bash scripts/capture_appstore_screenshots.sh
```

Requires macOS with Xcode and a 6.9-inch iPhone simulator installed. It erases and boots the
simulator, pins the status bar to 9:41 with full bars and a charged battery, runs
`OffRentLedgerUITests/AppStoreCaptureUITests`, and writes the six app captures into this folder.
Pass a device name as the first argument to use a different simulator — but see **Device size**
below before you do.

## What makes it repeatable

### Device size

**iPhone 16 Pro Max** (or any 6.9-inch iPhone). Its portrait screenshot is **1290 × 2796**, which
is both the App Store's required size for that display class and the templates' canvas size — so a
capture drops into an opening with a uniform resize and no cropping at all. The scale factors in
the placement guide are computed from that; another device needs them recomputed.

### Build configuration

**Debug.** Every launch argument below is read inside `#if DEBUG`, and
`AppDependencies.testOverrides()` returns nothing at all in a Release build. A Release build
ignores the fixture entirely and launches into whatever is on the device — which is the point (see
**Proving the fixture cannot ship** below), and also means a Release build cannot be used to take
these screenshots.

### Launch arguments

```
-offrent-reset-state
-offrent-seed-appstore
-offrent-fixed-now 2026-05-09T15:00:00Z
-offrent-force-pro
-offrent-skip-onboarding
-offrent-disable-animations
-offrent-stub-ocr
-offrent-open-scan-review
```

| Argument | Why |
|---|---|
| `-offrent-reset-state` | Empties the store first. Without it a second session inherits the first one's records. |
| `-offrent-seed-appstore` | The capture fixture: four machines, two rental companies, three jobsites, one invoice. It wipes before it writes, so re-running is safe. |
| `-offrent-fixed-now` | Freezes the clock at **2026-05-09T15:00:00Z** — 10:00 America/Chicago. Every figure in the gallery is computed against this instant. |
| `-offrent-force-pro` | The widget and the operations map are Pro features. Without this the capture is of a paywall. |
| `-offrent-skip-onboarding` | The welcome cover otherwise sits in front of every screen. |
| `-offrent-disable-animations` | A screenshot taken mid-transition is a blurred screenshot. |
| `-offrent-stub-ocr` | The scan returns a committed fixture rather than whatever a camera saw. |
| `-offrent-open-scan-review` | Opens Scan Review over the real pipeline. `VNDocumentCameraViewController` reports itself unsupported on every simulator, so the app correctly draws no scan button there and the screen is otherwise unreachable without a physical device. |

**Do not change the timestamp** without re-running the tests. `AppStoreCaptureFixtureTests`
asserts every figure the gallery shows against it.

### The Pro entitlement

`-offrent-force-pro` is a Debug-only override read by `AppDependencies.effectiveEntitlement`. It
does not touch StoreKit, buy anything, or write a receipt. For the **device** capture of the Home
Screen widget, where launch arguments are awkward to pass, use a StoreKit configuration file
instead: Xcode → Edit Scheme → Run → Options → StoreKit Configuration → `StoreKit/Products.storekit`,
then buy the monthly subscription in the app's paywall. It is a test transaction and costs nothing.

### State reset

The script runs `xcrun simctl erase` before booting. That is stronger than deleting the app: the
App Group snapshot the widget reads, `UserDefaults` (onboarding flags, reminder settings) and the
on-disk store all survive a reinstall, and any one of them left over from a previous session
changes what a screenshot shows.

### The figures every screenshot must agree on

All of these come from `AppStoreCaptureFixture` and are asserted by
`Tests/OffRentDomainTests/AppStoreCaptureFixtureTests.swift`:

| | |
|---|---|
| Estimated rent running | **$2,885.00** — mini excavator 5 × $425, light tower 8 × $95 |
| Open rentals | **4** |
| On rent (accruing) | **2** |
| Awaiting pickup | **1** — the boom lift, BL-204, confirmation `OR-7318` |
| Invoices to review | **1** — Summit Rental Co., `SUM-30918` |
| Next rate change | **11 May 2026**, +$425 expected |
| Invoice: expected | **$2,280.00** — 8 days at $285 to the confirmation |
| Invoice: invoiced | **$2,565.00** — 9 days at $285 |
| Invoice: possible difference | **$285.00** — one day |

If a screenshot disagrees with this table, the screenshot is wrong, not the table.

### Capture order

The suite walks the screens in this order and photographs each one:

1. Today (launch lands here)
2. Rentals
3. Rentals → *Articulating Boom Lift* → three slow drags to the Off-rent confirmation block
4. Today → the map card → key open → search `BL-204` → tap the result → its Awaiting Pickup card
5. Today → *Scan a contract* → Scan Review
6. Audit → the Summit Rental Co. invoice

Step 3's scroll distance is the constant `Scroll.offRentProof` at the top of
`AppStoreCaptureUITests`. If a copy change moves the proof block out of frame, change that number
— it is the whole adjustment.

### Things that would spoil a capture, and what stops them

| Risk | What handles it |
|---|---|
| Permission dialogs | The capture never asks for location, notifications or the camera. |
| A keyboard over the map's card | The map search submits with the return key; the test asserts the keyboard is down before photographing and fails loudly if it is not. |
| A loading state | Each screen waits for a real element, then for the drawing to settle. Scan Review waits for the parse to finish rather than photographing the spinner. |
| Map tiles not yet loaded | Four seconds of settle after the camera flies, and a network connection. Check frame 4 before accepting it. |
| A different clock in each frame | `simctl status_bar override` pins 9:41, full bars, charged. |
| Transient banners | Nothing in the fixture schedules a notification during the run. |

---

## The Home Screen widget capture, by hand

`appstore-02-home-screen-widget.png` is the front device on template 2. **It must be a real iOS
Home Screen with the real widget on it.** XCUITest cannot add a widget to a Home Screen, and a
drawn one would put a picture of an iOS feature that nobody can install into an App Store listing.
So this one is done by hand, once, and it takes about five minutes.

A simulator can do it, and a device does it better — the simulator's Home Screen has a placeholder
wallpaper and a slightly different icon grid. Either is acceptable; both are real.

1. **Prepare the phone.** A 6.9-inch iPhone (or its simulator), portrait.
   - Settings → Wallpaper → a plain neutral still. No photograph of anybody, nothing with a logo.
     The templates are ivory, stone and graphite; a mid-grey or warm off-white wallpaper sits in
     the frame rather than fighting it.
   - Settings → Focus → Do Not Disturb **on**, so no banner arrives mid-capture.
   - Remove or move every third-party app off the first Home Screen page. What should be left is
     Apple's own apps, OffRent Ledger, and the widget. A row of unrelated logos in an App Store
     screenshot is somebody else's advertising.
   - No personal photos, no notification badges, no unread counts.
2. **Install the Debug build** with the capture fixture. On a simulator, the capture script has
   already done this; the app's data is still there after it finishes. On a device, run the app
   from Xcode with the launch arguments above set in the scheme (Edit Scheme → Run → Arguments).
3. **Open the app once** and let Today appear. That is what publishes the snapshot the widget
   reads — the widget never opens the store itself, so a widget added before the app has run shows
   its empty state.
4. **Confirm Pro is active.** The widget's useful state is a Pro feature; without the entitlement
   it correctly draws "The widget is part of Pro". `-offrent-force-pro`, or the StoreKit
   configuration file above.
5. **Add the widget.** Long-press the Home Screen → **+** (top left) → search "OffRent" → choose
   **OffRent Summary** → swipe to the **medium** size → *Add Widget* → place it at the top of the
   first page → Done.
6. **Check what it says** before photographing it. It must read **$2,885** estimated rent running,
   **4** open, **1** awaiting pickup, **1** to review, and *Next rate change May 11*. If it reads
   anything else — most likely an empty state or a Pro prompt — go back to steps 3 and 4; the
   snapshot has not been published or the entitlement is not on.
7. **Pin the status bar** so it matches the other six frames.
   - Simulator: `xcrun simctl status_bar booted override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3`
   - Device: this cannot be forced. Take it at 9:41 if you can be bothered; if not, the mismatch
     is small and honest.
8. **Take the screenshot.** Simulator: `xcrun simctl io booted screenshot marketing/screenshots/appstore-02-home-screen-widget.png`.
   Device: side button + volume up, then AirDrop it across and rename it.
9. **Check the size.** It must be exactly 1290 × 2796. Anything else means the wrong device.

Never substitute a drawing, a mockup, or a rendering of the widget for this file. If it cannot be
captured, leave template 2's front opening blank and ship five frames rather than six.

---

## Assembling the gallery

1. Regenerate the blank templates, if anything about them changed:
   ```sh
   python3 scripts/generate_appstore_templates.py
   ```
2. Place each capture into its opening. Every coordinate, radius, rotation, pivot, scale factor
   and crop rule is in `marketing/AppStore/OffRent-AppStore-Template-Placement-Guide.md`, per
   opening. In Figma or Illustrator, clip each capture to a rounded rectangle of the geometry
   given; in Canva, place it and apply the rounded-corner frame.
3. Export the finished composites at 1290 × 2796 into a folder of their own — **not** over
   `marketing/AppStore/`, which holds the reusable blank masters. `marketing/AppStore/composites/`
   is the convention.
4. Validate and package:
   ```sh
   python3 scripts/validate_appstore_templates.py
   python3 scripts/package_appstore_templates.py
   ```
   The validator checks the blank masters. It deliberately fails on a template with a screenshot
   in it, which is why the composites live somewhere else.

---

## Proving the fixture cannot ship

The App Store fixture writes four invented rentals and an invoice with a deliberate overcharge on
it. That is the right thing to put in front of a camera and the wrong thing to be reachable on a
phone somebody has paid for. Three locks, in order of strength:

1. **`AppDependencies.testOverrides()` returns an empty struct in a Release build.** Every launch
   argument is inert there, `-offrent-seed-appstore` included.
2. **The fixture and its seeder are inside `#if DEBUG`.** `AppStoreCaptureFixture` and
   `SeedFixtures.seedAppStore` are not compiled into a Release binary at all, so there is no
   symbol to reach even with a debugger attached.
3. **`verify_repository.py` fails the build if either escapes.** The check is
   `check_appstore_fixture_is_debug_only`; it walks every shipped Swift file, tracks
   `#if`/`#else`/`#endif` nesting, and names the file and line of any reference outside a
   `#if DEBUG`.

To check it yourself:

```sh
python3 scripts/verify_repository.py            # the check, by name, in the output
grep -rn "AppStoreCaptureFixture\|seedAppStore" OffRentLedger/   # every hit inside a #if DEBUG
```

And to see the guarantee rather than read about it, build for release and look for the symbols:

```sh
xcodebuild build -project OffRentLedger.xcodeproj -scheme OffRentLedger \
  -configuration Release -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO
nm -gU "$(xcodebuild -project OffRentLedger.xcodeproj -scheme OffRentLedger \
  -configuration Release -sdk iphonesimulator -showBuildSettings \
  | awk '/ BUILT_PRODUCTS_DIR /{print $3}')/OffRentLedger.app/OffRentLedger" \
  | grep -i appstorecapture || echo "not in the release binary"
```

---

# Website screenshots

Separate slots, separate filenames, same folder. The website renders a labelled reserved frame for
each of the captures below, naming the exact file it is waiting for.

1. Run the app on an iPhone simulator or a device.
2. Capture these screens, portrait, at native resolution (1290 × 2796 for a 6.9-inch iPhone):

   | File                  | Screen                                                      |
   |-----------------------|-------------------------------------------------------------|
   | `today.png`           | Today, with two or three rentals accruing                    |
   | `rentals.png`         | Rentals list, mixed statuses                                 |
   | `rental-detail.png`   | One rental with terms, running estimate and timeline         |
   | `scan-review.png`     | Scan review, values ticked and unticked                      |
   | `confirmation.png`    | Vendor confirmation recorded                                 |
   | `awaiting-pickup.png` | Awaiting pickup                                              |
   | `invoice-review.png`  | Invoice review showing a possible mismatch                   |

3. Drop them here, add them to `SCREENSHOTS` in `scripts/generate_website.py` with their real
   pixel dimensions and alt text, then re-run the generator and the packager.

Use the walkthrough fixture (`-offrent-seed-walkthrough`) for these, so the figures are the ones
the tests and the documentation already use — or the App Store fixture
(`-offrent-seed-appstore`) if you would rather the site and the store showed the same records.
Do not retouch the numbers.
