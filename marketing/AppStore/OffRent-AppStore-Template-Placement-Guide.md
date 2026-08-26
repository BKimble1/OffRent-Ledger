# OffRent Ledger — App Store template placement guide

Six templates at **1290 × 2796** (6.9-inch iPhone). Each carries a finished background, headline,
supporting line and correctly proportioned iPhones with **blank** screen openings. Drop a real
screenshot into each opening and the template is finished — no repainting, no rebuilding.

**No app UI was generated.** Not a card, not a tab, not a figure, not a status bar, and not a
single pixel of iOS. Every screen opening is a flat neutral rectangle waiting for a real capture,
because a drawn interface in an App Store gallery is a picture of software nobody can install.

Seven captures fill the seven openings. Six come from the running app; one — template 2's front
device — is a real iPhone Home Screen with the OffRent Summary widget on it, which cannot be
produced by a simulator and is not permitted to be drawn. `marketing/screenshots/README.md` is
the procedure for all seven, including the deterministic fixture and the fixed clock that make
the figures on them agree with each other.

## How to place a screenshot

1. Capture the intended screen on a 6.9-inch iPhone (or its simulator) at **1290 × 2796**.
   That is the same size as the template, so there is no distortion — only a uniform resize.
2. Resize the capture to the screen opening below. The opening is locked to 1290:2796, so a
   proportional resize lands exactly.
3. Position its top-left corner at the coordinates given, measuring from the top-left of the
   1290 × 2796 canvas.
4. Round the corners to the radius given. In Canva: place the image, then apply the rounded-corner
   frame. In Figma or Illustrator: clip it to a rounded rectangle of the same geometry.
5. Where a rotation is listed, rotate the placed screenshot by that angle **about the pivot
   given** — the pivot is the centre of the device body, not the centre of the screen.
6. Where a crop is listed, the opening runs off the canvas on that edge. Place the whole capture
   at the coordinates above and let the canvas do the cropping; do not pre-crop and re-fit, which
   changes the scale and breaks the alignment with the bezel.

The Dynamic Island is drawn **on top of** the screen in the template. Place the screenshot behind
it, or place it above and re-draw the island; the island is a separate rounded rectangle in the
SVG master, so either is a one-step edit.

Template 2 has two openings. `screen-1` is the **back** device and `screen-2` is the **front**
one, and they are written to the SVG in that order — so placing them in numeric order, each
behind the next, reproduces the overlap without any restacking.

## Every opening at a glance

| # | Opening | Screen x | Screen y | Screen w | Screen h | Radius | Rotation | Capture | Source file |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `screen-1` | `220.0` | `856.5` | `850` | `1842.3` | `100.3` | `0.0°` | App capture | `appstore-01-today.png` |
| 2 | `screen-1` | `743.2` | `963.2` | `550` | `1192.1` | `64.9` | `0.0°` | App capture | `appstore-02-rentals.png` |
| 2 | `screen-2` | `50.5` | `1150.5` | `720` | `1560.6` | `85.0` | `0.0°` | Home Screen capture | `appstore-02-home-screen-widget.png` |
| 3 | `screen-1` | `173.0` | `193.6` | `820` | `1777.3` | `96.8` | `0.0°` | App capture | `appstore-03-off-rent-proof.png` |
| 4 | `screen-1` | `274.0` | `895.3` | `810` | `1755.6` | `95.6` | `0.0°` | App capture | `appstore-04-operations-map.png` |
| 5 | `screen-1` | `230.0` | `883.9` | `830` | `1799.0` | `97.9` | `-3.0°` | App capture | `appstore-05-scan-review.png` |
| 6 | `screen-1` | `150.0` | `1057.1` | `870` | `1885.7` | `102.7` | `0.0°` | App capture | `appstore-06-invoice-review.png` |

## Device geometry, identical across all seven

Bezel, corner radius and Dynamic Island are expressed as fractions of the screen width, so they
stay visually identical at several different phone scales — which is what a viewer notices when
it is not true.

| | |
|---|---|
| Screen aspect | `1290 : 2796` — the App Store screenshot size itself |
| Bezel | `0.0312 × screen width`, uniform on all four sides |
| Screen corner radius | `0.118 × screen width` |
| Device corner radius | screen radius + bezel |
| Dynamic Island | `0.2907 × screen width` wide, `0.2933 × island width` tall, fully rounded |
| Island top offset | `0.01175 × screen height` from the top of the screen |

### Template 1 — hero

> Stop the rental clock with proof.

Running cost, urgent calls, and every jobsite in one place.

#### Opening `screen-1` — only device

| | |
|---|---|
| Source screenshot | `marketing/screenshots/appstore-01-today.png` |
| Intended screen | Today dashboard |
| Capture kind | **App capture** |
| Screen opening | `850 × 1842.3` px |
| Top-left corner | `x = 220.0`, `y = 856.5` |
| Corner radius | `100.3` px |
| Screenshot aspect | `1290 : 2796` — the opening is locked to it, so a proportional resize lands exactly |
| Scale from source | `0.6589` — resize the 1290 × 2796 capture to `850 × 1842.3` |
| Opening width | `65.9%` of the canvas |
| Rotation | `0.0°` |
| Crop | None. The whole capture is placed; the phone sits clear of every edge. |

The estimated running rent, the action counts, the upcoming rate change and the map card are all on this one screen.


### Template 2 — widget-glance

> Rental cost at a glance.

See the running total without opening the app.

**Disclosure badge:** “Pro feature”, below the supporting line.

#### Opening `screen-1` — back device

| | |
|---|---|
| Source screenshot | `marketing/screenshots/appstore-02-rentals.png` |
| Intended screen | Rentals list |
| Capture kind | **App capture** |
| Screen opening | `550 × 1192.1` px |
| Top-left corner | `x = 743.2`, `y = 963.2` |
| Corner radius | `64.9` px |
| Screenshot aspect | `1290 : 2796` — the opening is locked to it, so a proportional resize lands exactly |
| Scale from source | `0.4264` — resize the 1290 × 2796 capture to `550 × 1192.1` |
| Opening width | `42.6%` of the canvas |
| Rotation | `0.0°` |
| Crop | A hair off the right edge — about 3 px of the capture, where the device runs off the canvas. Place the whole capture at the coordinates given and let the canvas trim it; there is nothing to pre-crop. |

The machines behind the widget's total, with their statuses and estimates.

#### Opening `screen-2` — front device

| | |
|---|---|
| Source screenshot | `marketing/screenshots/appstore-02-home-screen-widget.png` |
| Intended screen | iOS Home Screen with the medium OffRent Summary widget |
| Capture kind | **Home Screen capture** |
| Screen opening | `720 × 1560.6` px |
| Top-left corner | `x = 50.5`, `y = 1150.5` |
| Corner radius | `85.0` px |
| Screenshot aspect | `1290 : 2796` — the opening is locked to it, so a proportional resize lands exactly |
| Scale from source | `0.5581` — resize the 1290 × 2796 capture to `720 × 1560.6` |
| Opening width | `55.8%` of the canvas |
| Rotation | `0.0°` |
| Crop | None. The whole Home Screen capture is placed. |

A real Home Screen with the real widget on it. Never drawn, never recreated — see marketing/screenshots/README.md for the capture steps.


### Template 3 — off-rent-proof

> Record off-rent proof.

Confirmation number, meter, fuel, and condition, kept together.

#### Opening `screen-1` — only device

| | |
|---|---|
| Source screenshot | `marketing/screenshots/appstore-03-off-rent-proof.png` |
| Intended screen | A confirmed rental's detail, scrolled to Off-rent confirmation |
| Capture kind | **App capture** |
| Screen opening | `820 × 1777.3` px |
| Top-left corner | `x = 173.0`, `y = 193.6` |
| Corner radius | `96.8` px |
| Screenshot aspect | `1290 : 2796` — the opening is locked to it, so a proportional resize lands exactly |
| Scale from source | `0.6357` — resize the 1290 × 2796 capture to `820 × 1777.3` |
| Opening width | `63.6%` of the canvas |
| Rotation | `0.0°` |
| Crop | None. The copy sits below the phone, so the whole screen is visible. |

Recorded at, confirmation number, who was spoken to, how, meter and fuel — the evidence, in the order the app files it.


### Template 4 — operations-map

> Find every rental on the map.

Search your own records, and see what is still awaiting pickup.

#### Opening `screen-1` — only device

| | |
|---|---|
| Source screenshot | `marketing/screenshots/appstore-04-operations-map.png` |
| Intended screen | Operations Map with an Awaiting Pickup card selected |
| Capture kind | **App capture** |
| Screen opening | `810 × 1755.6` px |
| Top-left corner | `x = 274.0`, `y = 895.3` |
| Corner radius | `95.6` px |
| Screenshot aspect | `1290 : 2796` — the opening is locked to it, so a proportional resize lands exactly |
| Scale from source | `0.6279` — resize the 1290 × 2796 capture to `810 × 1755.6` |
| Opening width | `62.8%` of the canvas |
| Rotation | `0.0°` |
| Crop | None, and none is allowed: the search field and filters are at the top of this screen and the selected record's card is at the bottom. |

Search, filters, the key, several jobsites, and one machine's card reading Awaiting Pickup.


### Template 5 — scan-review

> Scan the contract. Review every field.

Every value is yours to check before anything is saved.

#### Opening `screen-1` — only device

| | |
|---|---|
| Source screenshot | `marketing/screenshots/appstore-05-scan-review.png` |
| Intended screen | Scan Review |
| Capture kind | **App capture** |
| Screen opening | `830 × 1799.0` px |
| Top-left corner | `x = 230.0`, `y = 883.9` |
| Corner radius | `97.9` px |
| Screenshot aspect | `1290 : 2796` — the opening is locked to it, so a proportional resize lands exactly |
| Scale from source | `0.6434` — resize the 1290 × 2796 capture to `830 × 1799.0` |
| Opening width | `64.3%` of the canvas |
| Rotation | `-3.0°` about `(645.0, 1783.4)` — the pivot is the centre of the **device body**, not of the screen |
| Crop | None. Rotate the placed capture about the pivot below, after resizing. |

The extracted company, unit, dates and rates, each with its own tick, above the line that says nothing is saved until the user says so.


### Template 6 — invoice-variance

> Spot possible billing differences.

Compare the invoice with the terms you confirmed.

#### Opening `screen-1` — only device

| | |
|---|---|
| Source screenshot | `marketing/screenshots/appstore-06-invoice-review.png` |
| Intended screen | Invoice Review showing an expected-versus-invoiced difference |
| Capture kind | **App capture** |
| Screen opening | `870 × 1885.7` px |
| Top-left corner | `x = 150.0`, `y = 1057.1` |
| Corner radius | `102.7` px |
| Screenshot aspect | `1290 : 2796` — the opening is locked to it, so a proportional resize lands exactly |
| Scale from source | `0.6744` — resize the 1290 × 2796 capture to `870 × 1885.7` |
| Opening width | `67.4%` of the canvas |
| Rotation | `0.0°` |
| Crop | Bottom edge, on purpose. Align the capture's top with the opening's top; the last ~8% of the screen runs off the canvas, and the three figures this frame is about are in the panel at the very top of it. |

Expected $2,280, Invoiced $2,565, Possible difference $285 — the three figures this frame exists for, in the panel at the top of the screen.


## Editing the masters

`OffRent-AppStore-Template-NN-*.svg` are the editable masters. Headlines and supporting lines are
live `<text>` elements, not outlines, so the copy can be changed in any vector editor. Every
screen opening carries `class="screen-area"` and an `id` of `screen-1` or `screen-2`, so it can be
selected by name rather than by clicking around.

Type is **Inter** (SIL Open Font License), with a fallback stack of SF Pro Display, Helvetica Neue,
Helvetica and Arial. `fonts/` in this package holds the four weights used and the licence. Install
them before editing, or the fallback will reflow the lines.

To regenerate everything from source:

    python3 scripts/generate_appstore_templates.py
    python3 scripts/validate_appstore_templates.py
    python3 scripts/package_appstore_templates.py

## Colour

| Role | Value |
|---|---|
| Warm ivory | `#F6F1E8` |
| Soft stone | `#E9E5DC` |
| Deep graphite | `#171A1F` |
| Secondary graphite | `#252A31` |
| Construction orange | `#FF8A1F` |
| Blank screen, light templates | `#D8D2C7` |
| Blank screen, graphite templates | `#4A4A48` |

Four of the six are light — warm ivory and pale stone with graphite structure. Templates 2 and 6
are graphite: 2 because the sequence has to break to dark once early, so the first three frames
read light → contrast → light rather than as three shades of the same cream, and 6 because the
gallery should close on its strongest contrast rather than open on it. The two are drawn from the
same pair of brand darks in opposite directions, so they read as bookends rather than as a repeat.

The palette is ivory, stone, graphite and one orange. There is no blue anywhere in the set, from
a sibling product or otherwise — `validate_appstore_templates.py` samples every finished PNG and
fails on any blue-dominant pixel.
