#!/usr/bin/env python3
"""Builds the six App Store screenshot templates for OffRent Ledger.

These are **empty marketing templates**. Each one carries a finished background, headline,
supporting line and correctly proportioned iPhones with *blank* screen openings. Not one of them
contains app UI: no cards, no tabs, no figures, no status bar. Drawing one would put an invented
interface in front of people deciding whether to install the real thing, so every opening is a
flat neutral rectangle waiting for a capture taken from the running app.

The gallery tells one story in six frames, in this order:

    1  hero              Stop the rental clock with proof.        Today dashboard
    2  widget-glance     Rental cost at a glance.                 Home Screen widget + Rentals
    3  off-rent-proof    Record off-rent proof.                   confirmed rental detail
    4  operations-map    Find every rental on the map.            Operations Map, awaiting pickup
    5  scan-review       Scan the contract. Review every field.   Scan Review
    6  invoice-variance  Spot possible billing differences.       Invoice Review

Frame 2 is the only one with two devices, and the only one on a graphite ground before the
closing frame — so the first three read light, contrast, light. Every other frame carries one
phone whose screen opening is 62–68% of the canvas width, because the App Store shows this
gallery at about a fifth of full size and a smaller phone there is a screenshot nobody can read.

Everything is deterministic vector construction. The masters are SVG with live `<text>`, so the
copy stays editable, and the PNGs are rasterised from those same masters by cairosvg — the SVG
is the source, the PNG is the output, and they cannot disagree.

Type is measured, not guessed. Every headline and supporting line is fitted with the real font
metrics before it is written, so a line that would overrun its column is shrunk to fit rather
than clipped at the canvas edge. Composition is asserted arithmetically for the same reason: a
headline that runs into a phone, a motif that runs through a supporting line, or a device with
too little of itself on the canvas fails the build rather than shipping.

Run: python3 scripts/generate_appstore_templates.py
"""

import math
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Point fontconfig at this repository's own configuration *before* cairo is imported, so the
# render is grayscale-antialiased on any host. See scripts/fontconfig/fonts.conf for why.
os.environ.setdefault("FONTCONFIG_FILE", str(ROOT / "scripts" / "fontconfig" / "fonts.conf"))
OUT = ROOT / "marketing" / "AppStore"
FONT_DIR = pathlib.Path("/usr/local/share/fonts/inter")

# --- canvas -------------------------------------------------------------------------------------

W, H = 1290, 2796          # 6.9-inch iPhone App Store screenshot size
MARGIN = 104

# --- palette ------------------------------------------------------------------------------------

IVORY = "#F6F1E8"
STONE = "#E9E5DC"
STONE_DEEP = "#DCD6CA"
GRAPHITE = "#171A1F"
GRAPHITE_2 = "#252A31"
GRAPHITE_3 = "#39414E"
ORANGE = "#FF8A1F"
ORANGE_DEEP = "#D2690D"
STONE_SHADE = "#DFD9CC"    # the deepest pale field used behind type

# Templates 2 and 5 sit on their own stones, a step down from STONE and a step warmer — red is
# held while blue falls, which is what makes a grey read as warm rather than merely darker.
# STONE is r-b 13; these are 19 and 24.
STONE_WARM = "#DED7C8"     # template 2
STONE_WARMER = "#D7CEBD"   # template 5, the deepest of the light five
STONE_WARMER_2 = "#CFC5B0"  # its wedge
WARM_GRAY = "#867F72"      # expected-cost lines on graphite. Lifted from #6E695F so the neutral
                           # bars hold their own against the orange variance segment instead of
                           # sinking into the ground.
RAIL_LIGHT = "#52504A"     # phone rail on a light template
RAIL_DARK = "#4C4840"      # phone rail on graphite

# Supporting copy. The old #5B6068 was a cool gray at 5.4:1 on ivory — legible up close and
# washed out at App Store thumbnail size, which is the size that decides whether anyone opens
# the listing. This is a warm dark gray at 9.4:1.
INK_SUPPORT = "#413E38"
IVORY_SUPPORT = "#DAD4C7"  # supporting copy on graphite. Warm, and brighter than the #C9C2B4 it
                           # replaced: 12.1:1 on #171A1F rather than 9.6:1.

SCREEN_LIGHT = "#D8D2C7"   # the blank display on a light template
SCREEN_DARK = "#4A4A48"    # the blank display on the graphite template.
                           # Neutral. Every earlier pick was blue-grey — #2C333E, then #39424F
                           # (one unit from GRAPHITE_3), then #434D5C — and then the correction
                           # overshot into brown. This is r-b 2: neither.

FONT_STACK = "Inter, 'Inter Display', 'SF Pro Display', 'Helvetica Neue', Helvetica, Arial, sans-serif"

# --- iPhone geometry ------------------------------------------------------------------------------
#
# Proportions taken from a 6.9-inch iPhone rather than invented. The screenshot itself is
# 1290 x 2796, so the screen opening is locked to that ratio and every other measurement is
# expressed as a fraction of the screen width — which is what keeps bezel thickness, corner
# radius and Dynamic Island identical across all six templates at six different scales.

SCREEN_RATIO = H / W                 # 2.167442
BEZEL_RATIO = 0.0312                 # (device width - screen width) / 2, over screen width
SCREEN_RADIUS_RATIO = 0.1180
ISLAND_WIDTH_RATIO = 0.2907
ISLAND_ASPECT = 0.2933               # island height / island width
ISLAND_TOP_RATIO = 0.01175           # from the top of the screen, over screen height


def phone_geometry(screen_w: float, screen_x: float, screen_y: float) -> dict:
    """Every measurement of one phone, derived from its screen width and top-left corner."""
    bezel = screen_w * BEZEL_RATIO
    screen_h = screen_w * SCREEN_RATIO
    island_w = screen_w * ISLAND_WIDTH_RATIO
    island_h = island_w * ISLAND_ASPECT
    return {
        "screen_x": screen_x, "screen_y": screen_y,
        "screen_w": screen_w, "screen_h": screen_h,
        "screen_r": screen_w * SCREEN_RADIUS_RATIO,
        "bezel": bezel,
        "device_x": screen_x - bezel, "device_y": screen_y - bezel,
        "device_w": screen_w + bezel * 2, "device_h": screen_h + bezel * 2,
        "device_r": screen_w * SCREEN_RADIUS_RATIO + bezel,
        "island_x": screen_x + (screen_w - island_w) / 2,
        "island_y": screen_y + screen_h * ISLAND_TOP_RATIO,
        "island_w": island_w, "island_h": island_h,
    }


def phone_svg(g: dict, *, screen_fill: str, dark: bool, rotation: float = 0.0,
              opening: int = 1) -> str:
    """The device: body, bezel, blank screen, Dynamic Island.

    The screen is a flat neutral and nothing else. It is a hole to drop a real screenshot into,
    and anything drawn inside it would have to be painted out again by whoever does that.

    `opening` numbers the hole within its own template, so a frame with two devices has
    `screen-1` and `screen-2` rather than two rectangles nobody can tell apart. The placement
    guide and `validate_appstore_templates.py` both address them by that id.
    """
    body = "#0E1116" if dark else "#1E1D1B"
    rail = RAIL_DARK if dark else RAIL_LIGHT

    cx = g["device_x"] + g["device_w"] / 2
    cy = g["device_y"] + g["device_h"] / 2
    transform = f' transform="rotate({rotation:.3f} {cx:.2f} {cy:.2f})"' if rotation else ""

    # Identical on all six: 9% ambient behind, 10% contact under the bottom edge. The contact
    # pool is what reads as "mounted"; the ambient one alone is what read as flat.
    ambient = (f'<ellipse cx="{cx:.1f}" cy="{cy + g["device_h"] * 0.10:.1f}" '
               f'rx="{g["device_w"] * 0.78:.1f}" ry="{g["device_h"] * 0.56:.1f}" '
               f'fill="url(#deviceShadow)" opacity="0.09"/>')
    contact = (f'<ellipse cx="{cx:.1f}" cy="{g["device_y"] + g["device_h"] + g["device_h"] * 0.018:.1f}" '
               f'rx="{g["device_w"] * 0.47:.1f}" ry="{g["device_h"] * 0.040:.1f}" '
               f'fill="url(#deviceShadow)" opacity="0.10"/>')

    return f"""  <g class="device-shadow"{transform}>{ambient}{contact}</g>
  <g class="device"{transform}>
    <rect x="{g['device_x']:.2f}" y="{g['device_y']:.2f}" width="{g['device_w']:.2f}" height="{g['device_h']:.2f}"
          rx="{g['device_r']:.2f}" fill="{body}"/>
    <rect x="{g['device_x'] + 1.5:.2f}" y="{g['device_y'] + 1.5:.2f}"
          width="{g['device_w'] - 3:.2f}" height="{g['device_h'] - 3:.2f}"
          rx="{g['device_r'] - 1.5:.2f}" fill="none" stroke="{rail}" stroke-width="3"/>
    <rect class="screen-area" id="screen-{opening}" x="{g['screen_x']:.2f}" y="{g['screen_y']:.2f}"
          width="{g['screen_w']:.2f}" height="{g['screen_h']:.2f}"
          rx="{g['screen_r']:.2f}" fill="{screen_fill}"/>
    <rect x="{g['island_x']:.2f}" y="{g['island_y']:.2f}" width="{g['island_w']:.2f}" height="{g['island_h']:.2f}"
          rx="{g['island_h'] / 2:.2f}" fill="#0B0E12"/>
  </g>"""


# --- type ---------------------------------------------------------------------------------------

_font_cache: dict = {}


def _font(weight: str, size: int):
    from PIL import ImageFont  # noqa: PLC0415
    key = (weight, size)
    if key not in _font_cache:
        path = FONT_DIR / f"Inter-{weight}.ttf"
        if not path.exists():
            raise SystemExit(f"missing font: {path}. Install Inter into {FONT_DIR}.")
        _font_cache[key] = ImageFont.truetype(str(path), size)
    return _font_cache[key]


def measure(text: str, weight: str, size: int, tracking_em: float = 0.0) -> float:
    """Advance width in pixels, including letter-spacing, using the real font metrics."""
    width = _font(weight, size).getlength(text)
    return width + tracking_em * size * max(len(text) - 1, 0)


def fit(lines: list[str], weight: str, max_size: int, max_width: float,
        tracking_em: float = 0.0) -> int:
    """Largest size at which every line fits the column. This is why nothing clips."""
    size = max_size
    while size > 24:
        if all(measure(line, weight, size, tracking_em) <= max_width for line in lines):
            return size
        size -= 2
    return size


def text_block(lines: list[str], *, x: float, y: float, weight: str, size: int, fill: str,
               leading: float, tracking_em: float = 0.0, anchor: str = "start") -> str:
    tracking = f' letter-spacing="{tracking_em * size:.2f}"' if tracking_em else ""
    spans = "".join(
        f'<tspan x="{x:.1f}" dy="{0 if i == 0 else leading:.1f}">{line}</tspan>'
        for i, line in enumerate(lines)
    )
    weights = {"Bold": 700, "SemiBold": 600, "Medium": 500, "Regular": 400}
    return (
        f'  <text x="{x:.1f}" y="{y:.1f}" font-family="{FONT_STACK}" font-weight="{weights[weight]}" '
        f'font-size="{size}" fill="{fill}" text-anchor="{anchor}"{tracking} '
        f'xml:space="preserve">{spans}</text>'
    )


# --- abstract accent motifs ------------------------------------------------------------------------
#
# Every motif here is geometry. None of them imitates a control, a card, a chart the app draws, or
# a value the app would show. They live outside the phone, they carry no numbers, and they are the
# reason the gallery reads as one campaign at six different rhythms.

def motif_meter_arc(cx: float, cy: float, r: float, *, sweep: float, ink: str,
                    track: str, width: float, hand: str) -> str:
    """Elapsed rental time: a track ring, an orange arc, and a hand from the centre.

    The hand and the hub are the point. Without them this was a three-quarter orange ring in a
    top-right corner, which is the shape of a download or refresh glyph on every platform — an
    unexplained control implying a feature the app does not have. A hub and a hand make it a
    meter, which is what the headline is about.
    """
    def point(fraction: float, radius: float) -> tuple[float, float]:
        angle = math.radians(-90 + 360 * fraction)
        return cx + radius * math.cos(angle), cy + radius * math.sin(angle)

    sx, sy = point(0.0, r)
    ex, ey = point(sweep, r)
    hx, hy = point(sweep, r * 0.60)
    large = 1 if sweep > 0.5 else 0
    return f"""  <g class="motif-meter">
    <circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="none" stroke="{track}" stroke-width="{width:.1f}"/>
    <path d="M {sx:.2f} {sy:.2f} A {r:.1f} {r:.1f} 0 {large} 1 {ex:.2f} {ey:.2f}"
          fill="none" stroke="{ink}" stroke-width="{width:.1f}" stroke-linecap="round"/>
    <line x1="{cx:.1f}" y1="{cy:.1f}" x2="{hx:.2f}" y2="{hy:.2f}"
          stroke="{hand}" stroke-width="{width * 0.62:.1f}" stroke-linecap="round"/>
    <circle cx="{cx:.1f}" cy="{cy:.1f}" r="{width * 0.52:.1f}" fill="{hand}"/>
  </g>"""


def motif_progression(x: float, y: float, *, count: int, gap: float, base: float,
                      growth: float, width: float, ink: str, accent: str,
                      accent_from: int) -> str:
    """Rising tick marks: a rate stepping up over time, with the roll-over in orange."""
    bars = []
    for i in range(count):
        height = base + growth * i
        colour = accent if i >= accent_from else ink
        bars.append(
            f'<rect x="{x + i * (width + gap):.1f}" y="{y - height:.1f}" '
            f'width="{width:.1f}" height="{height:.1f}" rx="{width / 2:.1f}" fill="{colour}"/>'
        )
    return f'  <g class="motif-progression">{"".join(bars)}</g>'


def motif_scan_edges(x: float, y: float, w: float, h: float, *, ink: str, accent: str,
                     stroke: float) -> str:
    """Capture corners framing the device. No camera chrome, no barcode, no page text.

    An earlier version also drew a scan line across the middle. It was invisible: the motif is
    painted before the phone, so the line sat behind the device the whole time. Rather than move
    a line that would have crossed the screen anyway, the diagonal pair of corners carries the
    orange — which keeps the accent thread running through all six frames.
    """
    arm = min(w, h) * 0.22
    corners = [
        (f"M {x} {y + arm} L {x} {y} L {x + arm} {y}", accent),
        (f"M {x + w - arm} {y} L {x + w} {y} L {x + w} {y + arm}", ink),
        (f"M {x + w} {y + h - arm} L {x + w} {y + h} L {x + w - arm} {y + h}", accent),
        (f"M {x + arm} {y + h} L {x} {y + h} L {x} {y + h - arm}", ink),
    ]
    paths = "".join(
        f'<path d="{d}" fill="none" stroke="{colour}" stroke-width="{stroke}" '
        f'stroke-linecap="square"/>'
        for d, colour in corners
    )
    return f'  <g class="motif-scan">{paths}</g>' 


def motif_stop_block(x: float, y: float, w: float, h: float, *, ran: float,
                     ink: str, accent: str, stroke: float) -> str:
    """A meter that runs and then stops: filled to the stop, outlined after it.

    Deliberately not a stop sign, a warning triangle or a power symbol — the rental did not fail,
    it ended, and the record of it is the product.
    """
    filled = w * ran
    return f"""  <g class="motif-stop">
    <rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{h / 2:.1f}"
          fill="none" stroke="{ink}" stroke-width="{stroke:.1f}"/>
    <rect x="{x:.1f}" y="{y:.1f}" width="{filled:.1f}" height="{h:.1f}" rx="{h / 2:.1f}" fill="{accent}"/>
    <rect x="{x + filled - h * 0.16:.1f}" y="{y - h * 0.62:.1f}" width="{h * 0.32:.1f}"
          height="{h * 2.24:.1f}" rx="{h * 0.16:.1f}" fill="{ink}"/>
  </g>"""


def motif_staged(x: float, y: float, *, count: int, w: float, h: float, gap: float,
                 ink: str, accent: str, stroke: float) -> str:
    """Machines staged in a line, waiting to be collected, with a direction of travel."""
    parts = []
    for i in range(count):
        cx = x + i * (w + gap)
        filled = i == count - 1
        parts.append(
            f'<rect x="{cx:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{h * 0.28:.1f}" '
            + (f'fill="{accent}"/>' if filled else f'fill="none" stroke="{ink}" stroke-width="{stroke:.1f}"/>')
        )
    tip = x + count * (w + gap) + w * 0.55
    mid = y + h / 2
    parts.append(
        f'<path d="M {tip - w * 0.5:.1f} {mid - h * 0.3:.1f} L {tip:.1f} {mid:.1f} '
        f'L {tip - w * 0.5:.1f} {mid + h * 0.3:.1f}" fill="none" stroke="{accent}" '
        f'stroke-width="{stroke * 1.2:.1f}" stroke-linecap="round" stroke-linejoin="round"/>'
    )
    return f'  <g class="motif-staged">{"".join(parts)}</g>'


def motif_variance(x: float, y: float, w: float, *, bar_h: float, gap: float, expected: float,
                   invoiced: float, ink: str, accent: str) -> str:
    """Two bars and the gap between them. No currency, no invoice, no alarm."""
    a = w * expected
    b = w * invoiced
    delta_x = x + min(a, b)
    delta_w = abs(b - a)
    return f"""  <g class="motif-variance">
    <rect x="{x:.1f}" y="{y:.1f}" width="{a:.1f}" height="{bar_h:.1f}" rx="{bar_h / 2:.1f}" fill="{ink}"/>
    <rect x="{x:.1f}" y="{y + bar_h + gap:.1f}" width="{b:.1f}" height="{bar_h:.1f}" rx="{bar_h / 2:.1f}" fill="{ink}"/>
    <rect x="{delta_x:.1f}" y="{y + bar_h + gap:.1f}" width="{delta_w:.1f}" height="{bar_h:.1f}"
          rx="{bar_h / 2:.1f}" fill="{accent}"/>
    <line x1="{delta_x:.1f}" y1="{y - bar_h * 0.5:.1f}" x2="{delta_x:.1f}"
          y2="{y + bar_h * 2 + gap + bar_h * 0.5:.1f}" stroke="{accent}" stroke-width="4"
          stroke-dasharray="14 12" stroke-linecap="round"/>
  </g>"""


def disclosure_badge(text: str, x: float, y: float, *, size: int, ink: str,
                     rule: str) -> tuple[str, tuple[float, float, float, float]]:
    """A small outlined pill saying what tier a feature belongs to.

    One frame in this gallery shows a widget whose useful state is behind the subscription. A
    filled orange pill would shout it and a footnote would hide it; an outlined pill at the size
    of the supporting copy says it once, where the claim is made, and then gets out of the way.

    Returns the markup and its box, so the layout assertions can keep the headline off it the
    same way they keep the headline off everything else.
    """
    pad_x, pad_y = 30.0, 17.0
    tracking = 0.02
    text_w = measure(text, "SemiBold", size, tracking)
    w = text_w + pad_x * 2
    h = size + pad_y * 2
    baseline = y + pad_y + size * 0.74
    return (
        f'  <g class="disclosure-badge">\n'
        f'    <rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{h / 2:.1f}" '
        f'fill="none" stroke="{rule}" stroke-width="2.5"/>\n'
        f'    <text x="{x + pad_x:.1f}" y="{baseline:.1f}" font-family="{FONT_STACK}" '
        f'font-weight="600" font-size="{size}" fill="{ink}" '
        f'letter-spacing="{tracking * size:.2f}" xml:space="preserve">{text}</text>\n'
        f'  </g>',
        (x, y, w, h),
    )


# --- shared defs ------------------------------------------------------------------------------------

def defs(dark: bool) -> str:
    return f"""  <defs>
    <!--
      The device shadow is drawn, not filtered.

      `feDropShadow` is silently ignored by cairosvg: a probe of a 50%-opacity drop shadow over a
      known background came back with the background luminance unchanged at every sample point.
      So the shadows in every previous version of these templates never rendered at all — which
      is exactly why the devices looked flat, and why turning the opacity down would not have
      helped. `feGaussianBlur` + `feOffset` renders, but with a hard edge where the falloff
      should be.

      Two radial gradients per device instead: a tight contact pool under the bottom edge and a
      wide ambient one behind. Both render exactly, and both survive an editor that drops filters
      on import — which Canva does.
    -->
    <radialGradient id="deviceShadow" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#2E2A22" stop-opacity="1"/>
      <stop offset="55%" stop-color="#2E2A22" stop-opacity="0.45"/>
      <stop offset="100%" stop-color="#2E2A22" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="warmGlow" cx="50%" cy="16%" r="76%">
      <stop offset="0%" stop-color="#FFFDF8" stop-opacity="0.80"/>
      <stop offset="100%" stop-color="#FFFDF8" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="heroFade" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="{IVORY}"/>
      <stop offset="52%" stop-color="{IVORY}"/>
      <stop offset="100%" stop-color="{STONE}"/>
    </linearGradient>
    <linearGradient id="topLift" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#FFFDF8" stop-opacity="0.55"/>
      <stop offset="46%" stop-color="#FFFDF8" stop-opacity="0.10"/>
      <stop offset="100%" stop-color="#FFFDF8" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="divisionFade" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="{STONE}"/>
      <stop offset="100%" stop-color="{STONE}" stop-opacity="0"/>
    </linearGradient>
    <radialGradient id="neutralLift" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.055"/>
      <stop offset="100%" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="graphiteFade" x1="0" y1="0" x2="0.28" y2="1">
      <stop offset="0%" stop-color="{GRAPHITE}"/>
      <stop offset="100%" stop-color="{GRAPHITE_2}"/>
    </linearGradient>
    <linearGradient id="graphiteRise" x1="0" y1="0" x2="0.22" y2="1">
      <stop offset="0%" stop-color="{GRAPHITE_2}"/>
      <stop offset="62%" stop-color="{GRAPHITE}"/>
      <stop offset="100%" stop-color="{GRAPHITE}"/>
    </linearGradient>
    <linearGradient id="stoneFade" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="{STONE}"/>
      <stop offset="100%" stop-color="{IVORY}"/>
    </linearGradient>
  </defs>"""


# --- the six templates ------------------------------------------------------------------------------
#
# One story, six frames, in the order a stranger reads them: the promise, the glance, the proof,
# the map, the scan, the invoice. Position and rhythm vary deliberately — phone centred, two
# phones on graphite, phone above the copy, phone below it, phone rotated, phone cropped at the
# bottom edge. Bezel, corner radius and Dynamic Island are identical in every one of them,
# because those are the things a viewer notices when they are not.
#
# Each device declares what belongs in its opening. `capture` is `app` for a screen recorded
# inside OffRent Ledger and `home-screen` for a real iOS Home Screen with the widget on it;
# nothing here is ever drawn, and the two are captured by different procedures, so the guide has
# to say which is which.

TEMPLATES = [
    {
        "n": 1, "slug": "hero",
        "headline": ["Stop the rental clock", "with proof."],
        "sub": ["Running cost, urgent calls, and", "every jobsite in one place."],
        "dark": False, "bg": "hero",
        "head_y": 452, "align": "center",
        # 850 of 1290 is 65.9% of the canvas. The old hero was 780, and the difference is what
        # decides whether the running-rent figure is a number or a smudge in a search result.
        "devices": [
            {"screen_w": 850, "device_y": 830, "device_dx": 0, "rotation": 0.0,
             "capture": "app", "layer": "single",
             "shot": "Today dashboard",
             "file": "appstore-01-today.png",
             "crop": "None. The whole capture is placed; the phone sits clear of every edge.",
             "why": "The estimated running rent, the action counts, the upcoming rate change "
                    "and the map card are all on this one screen."},
        ],
    },
    {
        "n": 2, "slug": "widget-glance",
        "headline": ["Rental cost", "at a glance."],
        "sub": ["See the running total without", "opening the app."],
        "dark": True, "bg": "graphite-riser",
        "head_y": 430, "align": "left",
        # The one disclosure in the gallery. The useful widget state is Pro-only, and a frame
        # that shows it without saying so is a promise the free tier does not keep.
        "badge": "Pro feature",
        # The only two-device frame in the set. Front is the Home Screen, because the headline is
        # about the widget; the app screen behind it is what the widget is a glance *at*.
        "devices": [
            {"screen_w": 550, "device_x": 726, "device_y": 946, "rotation": 0.0,
             "capture": "app", "layer": "back",
             "shot": "Rentals list",
             "file": "appstore-02-rentals.png",
             "crop": "A hair off the right edge — about 3 px of the capture, where the device "
                     "runs off the canvas. Place the whole capture at the coordinates given "
                     "and let the canvas trim it; there is nothing to pre-crop.",
             "why": "The machines behind the widget's total, with their statuses and estimates."},
            {"screen_w": 720, "device_x": 28, "device_y": 1128, "rotation": 0.0,
             "capture": "home-screen", "layer": "front",
             "shot": "iOS Home Screen with the medium OffRent Summary widget",
             "file": "appstore-02-home-screen-widget.png",
             "crop": "None. The whole Home Screen capture is placed.",
             "why": "A real Home Screen with the real widget on it. Never drawn, never "
                    "recreated — see marketing/screenshots/README.md for the capture steps."},
        ],
    },
    {
        "n": 3, "slug": "off-rent-proof",
        "headline": ["Record", "off-rent proof."],
        "sub": ["Confirmation number, meter, fuel,", "and condition, kept together."],
        "dark": False, "bg": "stone-top",
        "head_y": 2300, "align": "left",
        "devices": [
            {"screen_w": 820, "device_y": 168, "device_dx": -62, "rotation": 0.0,
             "capture": "app", "layer": "single",
             "shot": "A confirmed rental's detail, scrolled to Off-rent confirmation",
             "file": "appstore-03-off-rent-proof.png",
             "crop": "None. The copy sits below the phone, so the whole screen is visible.",
             "why": "Recorded at, confirmation number, who was spoken to, how, meter and fuel — "
                    "the evidence, in the order the app files it."},
        ],
    },
    {
        "n": 4, "slug": "operations-map",
        "headline": ["Find every rental", "on the map."],
        "sub": ["Search your own records, and see", "what is still awaiting pickup."],
        "dark": False, "bg": "wedge",
        "head_y": 420, "align": "left",
        "devices": [
            {"screen_w": 810, "device_y": 870, "device_dx": 34, "rotation": 0.0,
             "capture": "app", "layer": "single",
             "shot": "Operations Map with an Awaiting Pickup card selected",
             "file": "appstore-04-operations-map.png",
             "crop": "None, and none is allowed: the search field and filters are at the top of "
                     "this screen and the selected record's card is at the bottom.",
             "why": "Search, filters, the key, several jobsites, and one machine's card reading "
                    "Awaiting Pickup."},
        ],
    },
    {
        "n": 5, "slug": "scan-review",
        "headline": ["Scan the contract.", "Review every field."],
        "sub": ["Every value is yours to check", "before anything is saved."],
        "dark": False, "bg": "band",
        "head_y": 420, "align": "left",
        # -3.0 degrees, down from -5.5. At the old angle and the old size the extracted values ran
        # visibly downhill; at this one the frame still reads as a document on a desk and the
        # figures stay level enough to be read at thumbnail size.
        "devices": [
            {"screen_w": 830, "device_y": 858, "device_dx": 0, "rotation": -3.0,
             "capture": "app", "layer": "single",
             "shot": "Scan Review",
             "file": "appstore-05-scan-review.png",
             "crop": "None. Rotate the placed capture about the pivot below, after resizing.",
             "why": "The extracted company, unit, dates and rates, each with its own tick, above "
                    "the line that says nothing is saved until the user says so."},
        ],
    },
    {
        "n": 6, "slug": "invoice-variance",
        "headline": ["Spot possible billing", "differences."],
        "sub": ["Compare the invoice with the", "terms you confirmed."],
        "dark": True, "bg": "graphite",
        "head_y": 420, "align": "left",
        # Cropped at the bottom on purpose. Expected, Invoiced and Possible difference are the
        # first panel on this screen, so trading the bottom ninth of the phone for a bigger one
        # buys legibility exactly where the frame's whole argument is.
        "devices": [
            {"screen_w": 870, "device_y": 1030, "device_dx": -60, "rotation": 0.0,
             "capture": "app", "layer": "single",
             "shot": "Invoice Review showing an expected-versus-invoiced difference",
             "file": "appstore-06-invoice-review.png",
             "crop": "Bottom edge, on purpose. Align the capture's top with the opening's top; "
                     "the last ~8% of the screen runs off the canvas, and the three figures this "
                     "frame is about are in the panel at the very top of it.",
             "why": "Expected $2,280, Invoiced $2,565, Possible difference $285 — the three "
                    "figures this frame exists for, in the panel at the top of the screen."},
        ],
    },
]


def gallery_type_sizes() -> tuple[int, int]:
    """The one headline size and one supporting size the whole gallery uses.

    Fitted against the longest line anywhere in the set, so every template gets the same type at
    a size that cannot overrun its column. Nothing clips, and nothing has to be eyeballed.
    """
    column = W - MARGIN * 2
    heads = [line for spec in TEMPLATES for line in spec["headline"]]
    subs = [line for spec in TEMPLATES for line in spec["sub"]]
    return (fit(heads, "Bold", 118, column, tracking_em=-0.022),
            fit(subs, "Medium", 52, column, tracking_em=-0.004))


def background(kind: str, g: dict | None = None, rotation: float = 0.0) -> str:
    """The ground each template stands on.

    The first version was five near-identical warm-white canvases: correct, premium and, seen as
    a row of six thumbnails, flat. Each light template now carries one large tonal move — a
    gradient, a field, a division or a wedge — held between roughly 4% and 9% luminance contrast
    against its base. Enough that the gallery has rhythm; not so much that it competes with the
    screenshot, which is the thing anyone is actually looking at.
    """
    if kind == "hero":
        # Warm ivory, with the faintest ivory-to-stone settle down the frame. The most negative
        # space in the set, deliberately: this is the one that has to feel calm.
        return (f'  <rect width="{W}" height="{H}" fill="url(#heroFade)"/>\n'
                f'  <rect width="{W}" height="{H}" fill="url(#warmGlow)"/>\n'
                f'  <ellipse cx="{W * 0.5:.0f}" cy="{H * 1.02:.0f}" rx="{W * 0.86:.0f}" '
                f'ry="{H * 0.30:.0f}" fill="{STONE}" opacity="0.55"/>')

    if kind == "stone":
        # A step down and a step warmer than STONE, so it separates from templates 1 and 3 at
        # thumbnail size rather than only at full resolution.
        return (f'  <rect width="{W}" height="{H}" fill="{STONE_WARM}"/>\n'
                f'  <rect width="{W}" height="{H}" fill="url(#topLift)"/>\n'
                f'  <rect x="0" y="{H * 0.40:.0f}" width="{W}" height="{H * 0.60:.0f}" '
                f'fill="{STONE_WARMER}" opacity="0.50"/>')

    if kind == "band":
        # Ivory, with an oversized pale document field behind the phone, tilted to the same
        # angle as the device so the two read as one gesture rather than two.
        #
        # The angle is read from the device rather than written here. It used to be a literal
        # -5.5, and when the phone was straightened to -3 the field stayed where it was: two
        # rectangles two and a half degrees apart, which is close enough to look like a mistake
        # and far enough to see.
        field = ""
        if g:
            fw, fh = g["device_w"] + 260, g["device_h"] + 210
            fx, fy = g["device_x"] - 130, g["device_y"] - 105
            cx, cy = fx + fw / 2, fy + fh / 2
            field = (f'  <rect x="{fx:.0f}" y="{fy:.0f}" width="{fw:.0f}" height="{fh:.0f}" '
                     f'rx="56" fill="{STONE}" opacity="0.66" '
                     f'transform="rotate({rotation:.3f} {cx:.1f} {cy:.1f})"/>\n')
        return (f'  <rect width="{W}" height="{H}" fill="{IVORY}"/>\n'
                f'  <path d="M 0 {H * 0.315:.0f} L {W} {H * 0.245:.0f} L {W} {H} L 0 {H} Z" '
                f'fill="{STONE}" opacity="0.40"/>\n'
                f"{field}"
                f'  <rect width="{W}" height="{H}" fill="url(#warmGlow)" opacity="0.55"/>')

    if kind == "stone-top":
        # A clean tonal division: stone above, holding the phone; ivory below, holding the copy.
        return (f'  <rect width="{W}" height="{H}" fill="{IVORY}"/>\n'
                f'  <rect x="0" y="0" width="{W}" height="{H * 0.605:.0f}" fill="{STONE}"/>\n'
                f'  <rect x="0" y="{H * 0.605 - 2:.0f}" width="{W}" height="150" '
                f'fill="url(#divisionFade)"/>\n'
                f'  <rect width="{W}" height="{H}" fill="url(#warmGlow)" opacity="0.45"/>')

    if kind == "wedge":
        # The deepest of the light five. A single diagonal, nothing else.
        return (f'  <rect width="{W}" height="{H}" fill="{STONE_WARMER}"/>\n'
                f'  <path d="M {W} 0 L {W} {H} L {W * 0.10:.0f} {H} Z" '
                f'fill="{STONE_WARMER_2}" opacity="0.85"/>\n'
                f'  <rect width="{W}" height="{H}" fill="url(#topLift)"/>')

    if kind == "graphite-riser":
        # The second graphite frame, and deliberately not the same graphite frame.
        #
        # Two dark grounds in one gallery read as a mistake unless they are visibly different
        # pieces of art. Template 6 falls from deep graphite at the top to secondary graphite at
        # the bottom, with a neutral bloom high on the right. This one runs the other way — the
        # lighter graphite at the top, the deeper one under the devices — with the bloom low on
        # the left, where the front phone stands. Same two brand darks, opposite direction, so
        # the pair reads as bookends rather than as a repeat.
        return (f'  <rect width="{W}" height="{H}" fill="url(#graphiteRise)"/>\n'
                f'  <ellipse cx="{W * 0.20:.0f}" cy="{H * 0.84:.0f}" rx="{W * 0.74:.0f}" '
                f'ry="{H * 0.26:.0f}" fill="url(#neutralLift)"/>')

    if kind == "graphite":
        # Graphite, and graphite all the way down.
        #
        # The previous version laid a 20%-opacity orange radial over the whole canvas and a hard
        # 760px rectangle across the bottom. Together they produced a sepia wash with a visible
        # seam through it — a dirty texture, which is the one finish this palette must not have.
        # A smooth graphite-to-secondary-graphite fall and one small warm bloom in the corner
        # give the frame depth without tinting it.
        # The two brand graphites and nothing else. The orange bloom that used to sit over the
        # top of this is gone: at any opacity high enough to read, it tinted the whole frame,
        # which is where the brown cast came from. Depth now comes from the fall between the two
        # graphites plus a neutral highlight that adds no colour of its own.
        return (f'  <rect width="{W}" height="{H}" fill="url(#graphiteFade)"/>\n'
                f'  <ellipse cx="{W * 0.74:.0f}" cy="{H * 0.13:.0f}" rx="{W * 0.66:.0f}" '
                f'ry="{H * 0.22:.0f}" fill="url(#neutralLift)"/>')

    raise ValueError(kind)


def motif_for(spec: dict) -> tuple[str, tuple[float, float, float, float] | None]:
    """The one abstract mark each frame carries, and the box it occupies.

    Keyed by slug rather than by number: the sequence was reordered once and a table keyed by
    position silently moved a rental meter onto the invoice frame. Each motif passes its own ink
    because they sit on six different grounds, and one shared value would be too faint on the
    deeper ones and too heavy on ivory.
    """
    slug = spec["slug"]

    if slug == "hero":
        cx, cy, r = W - MARGIN - 78, 226, 78
        return (motif_meter_arc(cx, cy, r, sweep=0.63, ink=ORANGE, track=STONE_SHADE,
                                width=16, hand=GRAPHITE),
                (cx - r - 8, cy - r - 8, (r + 8) * 2, (r + 8) * 2))

    if slug == "widget-glance":
        # Six ticks, not nine, and in the top-right rather than under the copy. The frame below
        # the headline belongs to two phones and a disclosure pill, and the old nine-bar run at
        # full height would have crossed both.
        count, width, gap, base, growth = 6, 26, 22, 40, 22
        span = count * (width + gap) - gap
        tallest = base + growth * (count - 1)
        x = W - MARGIN - span
        return (motif_progression(x, 300, count=count, gap=gap, base=base, growth=growth,
                                  width=width, ink=WARM_GRAY, accent=ORANGE, accent_from=4),
                (x, 300 - tallest, span, tallest))

    if slug == "off-rent-proof":
        # The meter that runs and then stops, in the band between the phone and the copy.
        y, h = 2101, 46
        return (motif_stop_block(MARGIN, y, W - MARGIN * 2 - 40, h, ran=0.62,
                                 ink="#ADA391", accent=ORANGE, stroke=7),
                (MARGIN, y - 29, W - MARGIN * 2 - 40, h + 58))

    if slug == "operations-map":
        # Machines staged in a line with a direction of travel: the awaiting-pickup half of what
        # this frame is about, said without drawing a pin, a truck or a map control.
        #
        # In the corner, not under the supporting line. Sat there, three rounded rectangles and
        # an arrow thirty pixels below a sentence read as a row of filter chips — a fake control
        # on the one frame whose whole promise is that everything inside the phone is real.
        count, w, h, gap = 3, 76, 54, 22
        span = count * (w + gap) + w * 0.55
        x, y = W - MARGIN - span, 214
        return (motif_staged(x, y, count=count, w=w, h=h, gap=gap,
                             ink="#B0A796", accent=ORANGE, stroke=7),
                (x, y, span, h))

    if slug == "scan-review":
        # Capture corners as a mark of their own, in the top-right, rather than wrapped around
        # the device. Wrapped, at this phone size, they ran to within fourteen pixels of the
        # bottom of the canvas and read as a border rather than as a viewfinder.
        size = 168
        x, y = W - MARGIN - size, 132
        return (motif_scan_edges(x, y, size, size, ink="#B4AB99", accent=ORANGE, stroke=8),
                (x, y, size, size))

    if slug == "invoice-variance":
        # WARM_GRAY, not GRAPHITE_3. The expected-cost lines were blue-grey, which is the one
        # thing the closing frame of this gallery must not be.
        y, bar_h, gap = 830, 46, 30
        return (motif_variance(MARGIN, y, W - MARGIN * 2 - 120, bar_h=bar_h, gap=gap,
                               expected=0.58, invoiced=0.86, ink=WARM_GRAY, accent=ORANGE),
                (MARGIN, y - 23, W - MARGIN * 2 - 120, bar_h * 2 + gap + bar_h))

    raise ValueError(f"no motif for {slug!r}")


def overlaps(a: tuple, b: tuple, slack: float = 12.0) -> bool:
    """Do two boxes intersect, allowing a little optical breathing room?"""
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    return not (ax + aw + slack <= bx or bx + bw + slack <= ax
                or ay + ah + slack <= by or by + bh + slack <= ay)


def rotated_bounds(g: dict, rotation: float) -> tuple[float, float, float, float]:
    """Axis-aligned bounds of the device body after rotation."""
    x, y, w, h = g["device_x"], g["device_y"], g["device_w"], g["device_h"]
    if not rotation:
        return x, y, w, h
    cx, cy = x + w / 2, y + h / 2
    a = math.radians(rotation)
    cos_a, sin_a = abs(math.cos(a)), abs(math.sin(a))
    rw, rh = w * cos_a + h * sin_a, w * sin_a + h * cos_a
    return cx - rw / 2, cy - rh / 2, rw, rh


GALLERY_HEAD_SIZE, GALLERY_SUB_SIZE = gallery_type_sizes()


def device_geometry(device: dict) -> dict:
    """One device's full geometry from its spec.

    `device_x` places the device body outright; `device_dx` offsets it from centred. The first
    form is what a two-device composition needs — "centred, minus 229" describes nothing anybody
    can check — and the second is what a single centred phone reads best as.
    """
    screen_w = device["screen_w"]
    bezel = screen_w * BEZEL_RATIO
    if "device_x" in device:
        device_x = device["device_x"]
    else:
        device_w = screen_w + bezel * 2
        device_x = (W - device_w) / 2 + device.get("device_dx", 0)
    return phone_geometry(screen_w, screen_x=device_x + bezel, screen_y=device["device_y"] + bezel)


def build_template(spec: dict) -> tuple[str, dict]:
    dark = spec["dark"]
    ink = IVORY if dark else GRAPHITE
    muted = IVORY_SUPPORT if dark else INK_SUPPORT
    screen_fill = SCREEN_DARK if dark else SCREEN_LIGHT

    devices = spec["devices"]
    geometries = [device_geometry(device) for device in devices]

    head_size = GALLERY_HEAD_SIZE
    sub_size = GALLERY_SUB_SIZE

    motif, motif_box = motif_for(spec)

    if spec["align"] == "center":
        tx, anchor = W / 2, "middle"
    else:
        tx, anchor = MARGIN, "start"

    head_leading = head_size * 1.06
    head_y = spec["head_y"]
    sub_y = head_y + head_leading * (len(spec["headline"]) - 1) + head_size * 1.02 + 34

    # The disclosure pill, where the frame carries one. Below the supporting copy, at its left
    # edge, because that is where the sentence it qualifies ends.
    badge_svg, badge_box = "", None
    if spec.get("badge"):
        badge_svg, badge_box = disclosure_badge(
            spec["badge"], MARGIN, sub_y + sub_size * 1.36 * (len(spec["sub"]) - 1) + 46,
            size=sub_size - 6, ink=ORANGE, rule=ORANGE,
        )

    # Back to front. The devices are written in the order they are declared, so a front phone's
    # shadow falls across the one behind it rather than under it.
    device_svg = "\n".join(
        phone_svg(g, screen_fill=screen_fill, dark=dark, rotation=device["rotation"],
                  opening=index + 1)
        for index, (device, g) in enumerate(zip(devices, geometries))
    )

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
        f'viewBox="0 0 {W} {H}" role="img" '
        f'aria-label="OffRent Ledger App Store template {spec["n"]}">',
        f"  <title>OffRent Ledger — App Store template {spec['n']} — {spec['slug']}</title>",
        defs(dark),
        background(spec["bg"], geometries[0], devices[0]["rotation"]),
        motif,
        device_svg,
        text_block(spec["headline"], x=tx, y=head_y, weight="Bold", size=head_size,
                   fill=ink, leading=head_leading, tracking_em=-0.022, anchor=anchor),
        text_block(spec["sub"], x=tx, y=sub_y, weight="Medium", size=sub_size,
                   fill=muted, leading=sub_size * 1.36, tracking_em=-0.004, anchor=anchor),
    ]
    if badge_svg:
        parts.append(badge_svg)
    parts.append("</svg>")

    # --- layout assertions -------------------------------------------------------------------
    #
    # Composition checked arithmetically rather than by looking at it. Template 2's rising bars
    # ran straight through "upcoming rate changes" in the first build and the contact sheet is
    # where that was caught — at thumbnail size, which is exactly where it is easiest to miss.
    ascent, descent = head_size * 0.74, head_size * 0.24
    head_w = max(measure(line, "Bold", head_size, -0.022) for line in spec["headline"])
    sub_w = max(measure(line, "Medium", sub_size, -0.004) for line in spec["sub"])
    head_left = tx - head_w / 2 if anchor == "middle" else tx
    sub_left = tx - sub_w / 2 if anchor == "middle" else tx
    head_box = (head_left, head_y - ascent,
                head_w, head_leading * (len(spec["headline"]) - 1) + ascent + descent)
    sub_box = (sub_left, sub_y - sub_size * 0.76, sub_w,
               sub_size * 1.36 * (len(spec["sub"]) - 1) + sub_size)
    device_boxes = [
        rotated_bounds(g, device["rotation"]) for device, g in zip(devices, geometries)
    ]

    drawn: list[tuple[str, tuple]] = [("headline", head_box), ("supporting text", sub_box)]
    if badge_box:
        drawn.append((f"the {spec['badge']!r} badge", badge_box))

    for name, box in drawn:
        if box[0] < MARGIN - 1 or box[0] + box[2] > W - MARGIN + 1:
            raise SystemExit(
                f"template {spec['n']}: {name} breaks the {MARGIN}px margin "
                f"(x {box[0]:.0f} to {box[0] + box[2]:.0f})")
        if box[1] < 40 or box[1] + box[3] > H - 40:
            raise SystemExit(f"template {spec['n']}: {name} runs off the canvas vertically")
        for index, device_box in enumerate(device_boxes, start=1):
            if overlaps(box, device_box):
                raise SystemExit(f"template {spec['n']}: {name} overlaps phone {index}")
        if motif_box and overlaps(box, motif_box):
            raise SystemExit(f"template {spec['n']}: {name} overlaps the accent motif")

    # Type may not collide with type either. Two blocks and a pill is three chances to discover
    # by eye what arithmetic can say outright.
    for (a_name, a_box), (b_name, b_box) in zip(drawn, drawn[1:]):
        if overlaps(a_box, b_box, slack=4):
            raise SystemExit(f"template {spec['n']}: {a_name} overlaps {b_name}")

    for index, (device, box) in enumerate(zip(devices, device_boxes), start=1):
        # The device may bleed off an edge on purpose, but never so far that it stops being a
        # phone.
        visible_w = min(box[0] + box[2], W) - max(box[0], 0)
        visible_h = min(box[1] + box[3], H) - max(box[1], 0)
        if visible_w < box[2] * 0.62 or visible_h < box[3] * 0.55:
            raise SystemExit(
                f"template {spec['n']}: too little of phone {index} is on the canvas")
        # The whole point of the redesign: a screen opening small enough to be unreadable in a
        # search result is a failed frame, however elegant the rest of it is. Two-device frames
        # are exempt — the pair carries the same information across two smaller screens.
        share = device["screen_w"] / W
        floor = 0.42 if len(devices) > 1 else 0.62
        if share < floor:
            raise SystemExit(
                f"template {spec['n']}: phone {index}'s opening is {share:.1%} of the canvas, "
                f"under the {floor:.0%} floor")

    openings = []
    for index, (device, g) in enumerate(zip(devices, geometries), start=1):
        openings.append({
            "index": index,
            "capture": device["capture"],
            "layer": device["layer"],
            "shot": device["shot"],
            "file": device["file"],
            "crop": device["crop"],
            "why": device["why"],
            "screen_x": round(g["screen_x"], 1), "screen_y": round(g["screen_y"], 1),
            "screen_w": round(g["screen_w"], 1), "screen_h": round(g["screen_h"], 1),
            "screen_r": round(g["screen_r"], 1),
            "rotation": device["rotation"],
            "pivot_x": round(g["device_x"] + g["device_w"] / 2, 1),
            "pivot_y": round(g["device_y"] + g["device_h"] / 2, 1),
            "scale": round(g["screen_w"] / W, 4),
            "share": round(g["screen_w"] / W, 4),
        })

    placement = {
        "n": spec["n"], "slug": spec["slug"],
        "headline": " ".join(spec["headline"]),
        "sub": " ".join(spec["sub"]),
        "badge": spec.get("badge"),
        "dark": spec["dark"],
        "head_size": head_size, "sub_size": sub_size,
        "openings": openings,
    }
    return "\n".join(parts) + "\n", placement


# --- rasterise, document, package ---------------------------------------------------------------

def rasterise(svg_path: pathlib.Path, png_path: pathlib.Path) -> None:
    """SVG master -> PNG at exactly 1290x2796, RGB, no alpha.

    cairosvg emits RGBA. App Store Connect rejects a screenshot with an alpha channel, so the
    flatten onto an opaque canvas is not cosmetic — it is the difference between an upload that
    works and one that is refused without much explanation.
    """
    import cairosvg  # noqa: PLC0415
    from PIL import Image  # noqa: PLC0415

    import io  # noqa: PLC0415

    # Rendered at 2x and resampled down. Supersampling costs a couple of seconds and buys cleaner
    # curves on the device corners and the meter arc than any rasteriser gives at 1x — and it
    # averages away whatever antialiasing artefacts the host still contributes.
    scale = 2
    raw = cairosvg.svg2png(url=str(svg_path), output_width=W * scale, output_height=H * scale)
    rgba = Image.open(io.BytesIO(raw)).convert("RGBA")
    flat = Image.new("RGB", (W * scale, H * scale), (255, 255, 255))
    flat.paste(rgba, mask=rgba.split()[3])
    flat = flat.resize((W, H), Image.LANCZOS)
    flat.save(png_path, format="PNG", optimize=True)


def contact_sheet(pngs: list[pathlib.Path], target: pathlib.Path) -> None:
    """A small review sheet. Supplemental — never a substitute for the six full-size files."""
    from PIL import Image  # noqa: PLC0415

    thumb_w = 300
    thumb_h = round(thumb_w * H / W)
    pad, label = 28, 44
    sheet = Image.new("RGB", (pad + (thumb_w + pad) * 6, thumb_h + pad * 2 + label), (24, 27, 32))
    for i, path in enumerate(pngs):
        im = Image.open(path).convert("RGB").resize((thumb_w, thumb_h), Image.LANCZOS)
        sheet.paste(im, (pad + i * (thumb_w + pad), pad))
    sheet.save(target, format="PNG", optimize=True)


CAPTURE_LABEL = {
    "app": "App capture",
    "home-screen": "Home Screen capture",
}

LAYER_LABEL = {
    "single": "only device",
    "front": "front device",
    "back": "back device",
}


def placement_guide(placements: list[dict]) -> str:
    rows = []
    for p in placements:
        for opening in p["openings"]:
            rows.append(
                f"| {p['n']} | `screen-{opening['index']}` | `{opening['screen_x']}` | "
                f"`{opening['screen_y']}` | `{opening['screen_w']}` | `{opening['screen_h']}` | "
                f"`{opening['screen_r']}` | `{opening['rotation']}°` | "
                f"{CAPTURE_LABEL[opening['capture']]} | `{opening['file']}` |"
            )
    row_block = "\n".join(rows)

    sections = []
    for p in placements:
        badge = f"\n\n**Disclosure badge:** “{p['badge']}”, below the supporting line." if p["badge"] else ""
        opening_blocks = []
        for opening in p["openings"]:
            rotation = (
                f"`{opening['rotation']}°`" if not opening["rotation"]
                else f"`{opening['rotation']}°` about `({opening['pivot_x']}, {opening['pivot_y']})` "
                     f"— the pivot is the centre of the **device body**, not of the screen"
            )
            opening_blocks.append(f"""#### Opening `screen-{opening['index']}` — {LAYER_LABEL[opening['layer']]}

| | |
|---|---|
| Source screenshot | `marketing/screenshots/{opening['file']}` |
| Intended screen | {opening['shot']} |
| Capture kind | **{CAPTURE_LABEL[opening['capture']]}** |
| Screen opening | `{opening['screen_w']} × {opening['screen_h']}` px |
| Top-left corner | `x = {opening['screen_x']}`, `y = {opening['screen_y']}` |
| Corner radius | `{opening['screen_r']}` px |
| Screenshot aspect | `1290 : 2796` — the opening is locked to it, so a proportional resize lands exactly |
| Scale from source | `{opening['scale']}` — resize the 1290 × 2796 capture to `{opening['screen_w']} × {opening['screen_h']}` |
| Opening width | `{opening['share'] * 100:.1f}%` of the canvas |
| Rotation | {rotation} |
| Crop | {opening['crop']} |

{opening['why']}
""")
        joined = "\n".join(opening_blocks)
        sections.append(f"""### Template {p['n']} — {p['slug']}

> {p['headline']}

{p['sub']}{badge}

{joined}""")
    detail = "\n\n".join(sections)

    return f"""# OffRent Ledger — App Store template placement guide

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
{row_block}

## Device geometry, identical across all seven

Bezel, corner radius and Dynamic Island are expressed as fractions of the screen width, so they
stay visually identical at several different phone scales — which is what a viewer notices when
it is not true.

| | |
|---|---|
| Screen aspect | `1290 : 2796` — the App Store screenshot size itself |
| Bezel | `{BEZEL_RATIO} × screen width`, uniform on all four sides |
| Screen corner radius | `{SCREEN_RADIUS_RATIO} × screen width` |
| Device corner radius | screen radius + bezel |
| Dynamic Island | `{ISLAND_WIDTH_RATIO} × screen width` wide, `{ISLAND_ASPECT} × island width` tall, fully rounded |
| Island top offset | `{ISLAND_TOP_RATIO} × screen height` from the top of the screen |

{detail}

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
| Warm ivory | `{IVORY}` |
| Soft stone | `{STONE}` |
| Deep graphite | `{GRAPHITE}` |
| Secondary graphite | `{GRAPHITE_2}` |
| Construction orange | `{ORANGE}` |
| Blank screen, light templates | `{SCREEN_LIGHT}` |
| Blank screen, graphite templates | `{SCREEN_DARK}` |

Four of the six are light — warm ivory and pale stone with graphite structure. Templates 2 and 6
are graphite: 2 because the sequence has to break to dark once early, so the first three frames
read light → contrast → light rather than as three shades of the same cream, and 6 because the
gallery should close on its strongest contrast rather than open on it. The two are drawn from the
same pair of brand darks in opposite directions, so they read as bookends rather than as a repeat.

The palette is ivory, stone, graphite and one orange. There is no blue anywhere in the set, from
a sibling product or otherwise — `validate_appstore_templates.py` samples every finished PNG and
fails on any blue-dominant pixel.
"""


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    placements, pngs = [], []
    written: set[pathlib.Path] = set()

    for spec in TEMPLATES:
        svg, placement = build_template(spec)
        stem = f"OffRent-AppStore-Template-{spec['n']:02d}-{spec['slug']}"
        svg_path = OUT / f"{stem}.svg"
        png_path = OUT / f"OffRent-AppStore-Template-{spec['n']:02d}.png"
        svg_path.write_text(svg)
        rasterise(svg_path, png_path)
        written.update({svg_path, png_path})
        placements.append(placement)
        pngs.append(png_path)
        openings = ", ".join(
            f"screen-{o['index']} {o['screen_w']:.0f}x{o['screen_h']:.0f} "
            f"@ ({o['screen_x']:.0f}, {o['screen_y']:.0f})"
            for o in placement["openings"]
        )
        print(f"  {png_path.name}  head {placement['head_size']}px  {openings}")

    # A slug that changed, or a frame that was retired, leaves a master behind — and the packager
    # globs the folder, so the stale file ships in the ZIP and the validator counts seven SVGs
    # where it expects six. The generator owns this directory's template files, so it removes the
    # ones it did not just write.
    for stale in sorted(OUT.glob("OffRent-AppStore-Template-*")):
        if stale.suffix in {".svg", ".png"} and stale not in written:
            stale.unlink()
            print(f"  removed stale {stale.name}")

    contact_sheet(pngs, OUT / "OffRent-AppStore-Contact-Sheet.png")
    (OUT / "OffRent-AppStore-Template-Placement-Guide.md").write_text(placement_guide(placements))
    total = sum(len(p["openings"]) for p in placements)
    print(f"wrote: {OUT.relative_to(ROOT)}/ — 6 SVG masters, 6 PNGs, {total} screen openings, "
          f"contact sheet, placement guide")
    return 0


if __name__ == "__main__":
    sys.exit(main())
