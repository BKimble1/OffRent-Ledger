# OffRent Ledger — App Store template placement guide

Six empty templates at **1290 × 2796** (6.9-inch iPhone). Each carries a finished background,
headline, supporting line and a correctly proportioned iPhone with a **blank** screen. Drop a real
screenshot into the opening and the template is finished — no repainting, no rebuilding.

**No app UI was generated.** Not a card, not a tab, not a figure, not a status bar. The app has
not been launched yet, so no screenshot of it exists; inventing one would put a picture of an
interface nobody has run in front of people deciding whether to install the real thing. Every
screen opening is a flat neutral rectangle waiting for a real capture.

## How to place a screenshot

1. Capture the intended screen on a 6.9-inch iPhone (or its simulator) at **1290 × 2796**.
   That is the same size as the template, so there is no cropping and no distortion — only a
   uniform resize.
2. Resize the capture to the screen opening below. The opening is locked to 1290:2796, so a
   proportional resize lands exactly.
3. Position its top-left corner at the coordinates given, measuring from the top-left of the
   1290 × 2796 canvas.
4. Round the corners to the radius given. In Canva: place the image, then apply the rounded-corner
   frame. In Figma or Illustrator: clip it to a rounded rectangle of the same geometry.
5. Where a rotation is listed, rotate the placed screenshot by that angle about the pivot given —
   the pivot is the centre of the device body, not the centre of the screen.

The Dynamic Island is drawn **on top of** the screen in the template. Place the screenshot behind
it, or place it above and re-draw the island; the island is a separate rounded rectangle in the
SVG master, so either is a one-step edit.

## Every template at a glance

| # | Screen x | Screen y | Screen w | Screen h | Radius | Rotation | Intended screenshot |
|---|---|---|---|---|---|---|---|
| 1 | `255.0` | `1011.3` | `780` | `1690.6` | `92.0` | `0.0°` | Today dashboard |
| 2 | `513.0` | `1267.8` | `700` | `1517.2` | `82.6` | `0.0°` | Rentals list, or an active rental's detail |
| 3 | `317.5` | `1125.4` | `655` | `1419.7` | `77.3` | `-5.5°` | Scan Review |
| 4 | `193.5` | `190.9` | `735` | `1593.1` | `86.7` | `0.0°` | Record Confirmation, or a confirmed rental's detail |
| 5 | `662.0` | `961.5` | `690` | `1495.5` | `81.4` | `0.0°` | Awaiting Pickup list, or a rental's detail |
| 6 | `129.5` | `1267.3` | `715` | `1549.7` | `84.4` | `0.0°` | Invoice Review showing an expected-versus-invoiced difference |

## Device geometry, identical across all six

Bezel, corner radius and Dynamic Island are expressed as fractions of the screen width, so they
stay visually identical at six different phone scales — which is what a viewer notices when it is
not true.

| | |
|---|---|
| Screen aspect | `1290 : 2796` — the App Store screenshot size itself |
| Bezel | `0.0312 × screen width`, uniform on all four sides |
| Screen corner radius | `0.1180 × screen width` |
| Device corner radius | screen radius + bezel |
| Dynamic Island | `0.2907 × screen width` wide, `0.2933 × island width` tall, fully rounded |
| Island top offset | `0.01175 × screen height` from the top of the screen |

### Template 1 — hero

> Stop the rental clock with proof.

**Intended screenshot:** Today dashboard

| | |
|---|---|
| Screen opening | `780 × 1690.6` px |
| Top-left corner | `x = 255.0`, `y = 1011.3` |
| Corner radius | `92.0` px |
| Rotation | `0.0°` |
| Scale from source | `0.6047` — resize the 1290 × 2796 capture to `780 × 1690.6` |


### Template 2 — active-costs

> Control every active rental.

**Intended screenshot:** Rentals list, or an active rental's detail

| | |
|---|---|
| Screen opening | `700 × 1517.2` px |
| Top-left corner | `x = 513.0`, `y = 1267.8` |
| Corner radius | `82.6` px |
| Rotation | `0.0°` |
| Scale from source | `0.5426` — resize the 1290 × 2796 capture to `700 × 1517.2` |


### Template 3 — scan-review

> Scan rental details in seconds.

**Intended screenshot:** Scan Review

| | |
|---|---|
| Screen opening | `655 × 1419.7` px |
| Top-left corner | `x = 317.5`, `y = 1125.4` |
| Corner radius | `77.3` px |
| Rotation | `-5.5°` about `(645.0, 1835.3)` |
| Scale from source | `0.5078` — resize the 1290 × 2796 capture to `655 × 1419.7` |


### Template 4 — off-rent-proof

> Record off-rent proof.

**Intended screenshot:** Record Confirmation, or a confirmed rental's detail

| | |
|---|---|
| Screen opening | `735 × 1593.1` px |
| Top-left corner | `x = 193.5`, `y = 190.9` |
| Corner radius | `86.7` px |
| Rotation | `0.0°` |
| Scale from source | `0.5698` — resize the 1290 × 2796 capture to `735 × 1593.1` |


### Template 5 — awaiting-pickup

> Track equipment awaiting pickup.

**Intended screenshot:** Awaiting Pickup list, or a rental's detail

| | |
|---|---|
| Screen opening | `690 × 1495.5` px |
| Top-left corner | `x = 662.0`, `y = 961.5` |
| Corner radius | `81.4` px |
| Rotation | `0.0°` |
| Scale from source | `0.5349` — resize the 1290 × 2796 capture to `690 × 1495.5` |


### Template 6 — invoice-variance

> Spot possible billing differences.

**Intended screenshot:** Invoice Review showing an expected-versus-invoiced difference

| | |
|---|---|
| Screen opening | `715 × 1549.7` px |
| Top-left corner | `x = 129.5`, `y = 1267.3` |
| Corner radius | `84.4` px |
| Rotation | `0.0°` |
| Scale from source | `0.5543` — resize the 1290 × 2796 capture to `715 × 1549.7` |


## Editing the masters

`OffRent-AppStore-Template-NN-*.svg` are the editable masters. Headlines and supporting lines are
live `<text>` elements, not outlines, so the copy can be changed in any vector editor. The screen
opening carries `class="screen-area"` for easy selection.

Type is **Inter** (SIL Open Font License), with a fallback stack of SF Pro Display, Helvetica Neue,
Helvetica and Arial. `fonts/` in this package holds the four weights used and the licence. Install
them before editing, or the fallback will reflow the lines.

To regenerate everything from source:

    python3 scripts/generate_appstore_templates.py

## Colour

| Role | Value |
|---|---|
| Warm ivory | `#F6F1E8` |
| Soft stone | `#E9E5DC` |
| Deep graphite | `#171A1F` |
| Secondary graphite | `#252A31` |
| Construction orange | `#FF8A1F` |
| Blank screen, light templates | `#D8D2C7` |
| Blank screen, graphite template | `#4C4A45` |

Five of the six are light — warm ivory and pale stone with graphite structure. Template 6 is the
single graphite frame, placed last so the gallery closes on its strongest contrast rather than
opening on it.

The palette is ivory, stone, graphite and one orange. There is no blue anywhere in the set, from
a sibling product or otherwise — `validate_appstore_templates.py` samples every finished PNG and
fails on any blue-dominant pixel.
