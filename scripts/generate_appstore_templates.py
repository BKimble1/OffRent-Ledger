#!/usr/bin/env python3
"""Builds the six App Store screenshot templates for OffRent Ledger.

These are **empty marketing templates**. Each one carries a finished background, headline,
supporting line and a correctly proportioned iPhone with a *blank* screen opening. Not one of
them contains app UI: no cards, no tabs, no figures, no status bar. The app has never been
launched, so no screenshot of it exists, and drawing one would put an invented interface in
front of people deciding whether to install the real thing.

Everything is deterministic vector construction. The masters are SVG with live `<text>`, so the
copy stays editable, and the PNGs are rasterised from those same masters by cairosvg — the SVG
is the source, the PNG is the output, and they cannot disagree.

Type is measured, not guessed. Every headline and supporting line is fitted with the real font
metrics before it is written, so a line that would overrun its column is shrunk to fit rather
than clipped at the canvas edge.

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
INK_MUTED = "#5B6068"
IVORY_MUTED = "#A8B0BC"
SCREEN_LIGHT = "#D8D2C7"   # the blank display on a light template
SCREEN_DARK = "#434D5C"    # the blank display on the graphite template. Light enough that the
                           # device still reads as a device against graphite, and clearly
                           # apart from GRAPHITE_3 — the first pick, #39424F, was one unit
                           # from it, so the variance bars and the blank screen were the
                           # same colour by accident.

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


def phone_svg(g: dict, *, screen_fill: str, dark: bool, rotation: float = 0.0) -> str:
    """The device: body, bezel, blank screen, Dynamic Island.

    The screen is a flat neutral and nothing else. It is a hole to drop a real screenshot into,
    and anything drawn inside it would have to be painted out again by whoever does that.
    """
    shadow = "phoneShadowDark" if dark else "phoneShadow"
    body = "#0E1116" if dark else "#20242B"
    rail = GRAPHITE_3 if dark else "#4A525F"

    transform = ""
    if rotation:
        cx = g["device_x"] + g["device_w"] / 2
        cy = g["device_y"] + g["device_h"] / 2
        transform = f' transform="rotate({rotation:.3f} {cx:.2f} {cy:.2f})"'

    return f"""  <g class="device"{transform}>
    <rect x="{g['device_x']:.2f}" y="{g['device_y']:.2f}" width="{g['device_w']:.2f}" height="{g['device_h']:.2f}"
          rx="{g['device_r']:.2f}" fill="{body}" filter="url(#{shadow})"/>
    <rect x="{g['device_x'] + 1.5:.2f}" y="{g['device_y'] + 1.5:.2f}"
          width="{g['device_w'] - 3:.2f}" height="{g['device_h'] - 3:.2f}"
          rx="{g['device_r'] - 1.5:.2f}" fill="none" stroke="{rail}" stroke-width="3"/>
    <rect class="screen-area" x="{g['screen_x']:.2f}" y="{g['screen_y']:.2f}"
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
                    track: str, width: float) -> str:
    """A partial ring — time elapsed, drawn as an arc rather than as a clock face."""
    def point(fraction: float) -> tuple[float, float]:
        angle = math.radians(-90 + 360 * fraction)
        return cx + r * math.cos(angle), cy + r * math.sin(angle)

    sx, sy = point(0.0)
    ex, ey = point(sweep)
    large = 1 if sweep > 0.5 else 0
    return f"""  <g class="motif-meter">
    <circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="none" stroke="{track}" stroke-width="{width:.1f}"/>
    <path d="M {sx:.2f} {sy:.2f} A {r:.1f} {r:.1f} 0 {large} 1 {ex:.2f} {ey:.2f}"
          fill="none" stroke="{ink}" stroke-width="{width:.1f}" stroke-linecap="round"/>
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


# --- shared defs ------------------------------------------------------------------------------------

def defs(dark: bool) -> str:
    return f"""  <defs>
    <filter id="phoneShadow" x="-40%" y="-25%" width="180%" height="160%">
      <feDropShadow dx="0" dy="46" stdDeviation="52" flood-color="#5A4F3C" flood-opacity="0.30"/>
      <feDropShadow dx="0" dy="8" stdDeviation="12" flood-color="#3B342A" flood-opacity="0.20"/>
    </filter>
    <filter id="phoneShadowDark" x="-40%" y="-25%" width="180%" height="160%">
      <feDropShadow dx="0" dy="52" stdDeviation="58" flood-color="#000000" flood-opacity="0.62"/>
    </filter>
    <radialGradient id="warmGlow" cx="50%" cy="18%" r="78%">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.85"/>
      <stop offset="100%" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="emberGlow" cx="50%" cy="20%" r="72%">
      <stop offset="0%" stop-color="{ORANGE}" stop-opacity="0.20"/>
      <stop offset="100%" stop-color="{ORANGE}" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="stoneFade" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="{STONE}"/>
      <stop offset="100%" stop-color="{IVORY}"/>
    </linearGradient>
  </defs>"""


# --- the six templates ------------------------------------------------------------------------------
#
# Position, scale and rhythm vary deliberately: phone centred and fully visible, phone low-right
# bleeding off the bottom, phone rotated, phone at the *top* with the copy beneath it, phone
# running off the right edge, phone low-left on graphite. Bezel, corner radius and Dynamic Island
# are identical in every one of them, because those are the things a viewer notices when they are
# not.

TEMPLATES = [
    {
        "n": 1, "slug": "hero",
        "headline": ["Stop the rental clock", "with proof."],
        "sub": ["Track costs, confirmations, pickup,", "and final charges."],
        "shot": "Today dashboard",
        "dark": False, "bg": "hero",
        "screen_w": 780, "device_y": 987, "device_dx": 0, "rotation": 0.0,
        "head_y": 470, "head_max": 108, "align": "center",
    },
    {
        "n": 2, "slug": "active-costs",
        "headline": ["Control every", "active rental."],
        "sub": ["See running costs and", "upcoming rate changes."],
        "shot": "Rentals list, or an active rental's detail",
        "dark": False, "bg": "stone",
        "screen_w": 720, "device_y": 1300, "device_dx": 227, "rotation": 0.0,
        "head_y": 440, "head_max": 116, "align": "left",
    },
    {
        "n": 3, "slug": "scan-review",
        "headline": ["Scan rental details", "in seconds."],
        "sub": ["Review every field before", "anything is saved."],
        "shot": "Scan Review",
        "dark": False, "bg": "band",
        "screen_w": 655, "device_y": 1105, "device_dx": 0, "rotation": -5.5,
        "head_y": 440, "head_max": 112, "align": "left",
    },
    {
        "n": 4, "slug": "off-rent-proof",
        "headline": ["Record", "off-rent proof."],
        "sub": ["Keep confirmation, meter, fuel,", "and condition together."],
        "shot": "Record Confirmation, or a confirmed rental's detail",
        "dark": False, "bg": "stone-top",
        "screen_w": 735, "device_y": 168, "device_dx": -84, "rotation": 0.0,
        "head_y": 2246, "head_max": 116, "align": "left",
    },
    {
        "n": 5, "slug": "awaiting-pickup",
        "headline": ["Track equipment", "awaiting pickup."],
        "sub": ["Keep off-rented machines", "visible until they leave."],
        "shot": "Awaiting Pickup list, or a rental's detail",
        "dark": False, "bg": "wedge",
        "screen_w": 760, "device_y": 905, "device_dx": 391, "rotation": 0.0,
        "head_y": 440, "head_max": 112, "align": "left",
    },
    {
        "n": 6, "slug": "invoice-variance",
        "headline": ["Catch questionable", "final charges."],
        "sub": ["Compare expected cost with", "the vendor invoice."],
        "shot": "Invoice Review showing an expected-versus-invoiced difference",
        "dark": True, "bg": "graphite",
        "screen_w": 715, "device_y": 1245, "device_dx": -158, "rotation": 0.0,
        "head_y": 440, "head_max": 116, "align": "left",
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


def background(kind: str) -> str:
    if kind == "hero":
        return (f'  <rect width="{W}" height="{H}" fill="{IVORY}"/>\n'
                f'  <rect width="{W}" height="{H}" fill="url(#warmGlow)"/>\n'
                f'  <rect x="0" y="{H - 620}" width="{W}" height="620" fill="{STONE}" opacity="0.55"/>')
    if kind == "stone":
        return (f'  <rect width="{W}" height="{H}" fill="url(#stoneFade)"/>\n'
                f'  <rect x="0" y="0" width="{W}" height="{H}" fill="{STONE}" opacity="0.35"/>')
    if kind == "band":
        return (f'  <rect width="{W}" height="{H}" fill="{IVORY}"/>\n'
                f'  <path d="M 0 {H * 0.30:.0f} L {W} {H * 0.22:.0f} L {W} {H} L 0 {H} Z" '
                f'fill="{STONE}" opacity="0.62"/>')
    if kind == "stone-top":
        return (f'  <rect width="{W}" height="{H}" fill="{IVORY}"/>\n'
                f'  <rect x="0" y="0" width="{W}" height="{H * 0.66:.0f}" fill="{STONE}" opacity="0.72"/>\n'
                f'  <rect width="{W}" height="{H}" fill="url(#warmGlow)" opacity="0.5"/>')
    if kind == "wedge":
        return (f'  <rect width="{W}" height="{H}" fill="{IVORY}"/>\n'
                f'  <path d="M {W} 0 L {W} {H} L {W * 0.18:.0f} {H} Z" fill="{STONE}" opacity="0.62"/>')
    if kind == "graphite":
        return (f'  <rect width="{W}" height="{H}" fill="{GRAPHITE}"/>\n'
                f'  <rect width="{W}" height="{H}" fill="url(#emberGlow)"/>\n'
                f'  <rect x="0" y="{H - 700}" width="{W}" height="700" fill="{GRAPHITE_2}" opacity="0.75"/>')
    raise ValueError(kind)


def motif_for(spec: dict, g: dict) -> tuple[str, tuple[float, float, float, float] | None]:
    ink = IVORY_MUTED if spec["dark"] else "#B9B2A4"
    strong = IVORY if spec["dark"] else GRAPHITE
    n = spec["n"]
    if n == 1:
        cx, cy, r = W - MARGIN - 76, 246, 76
        return (motif_meter_arc(cx, cy, r, sweep=0.63, ink=ORANGE, track="#DDD5C6", width=16),
                (cx - r - 8, cy - r - 8, (r + 8) * 2, (r + 8) * 2))
    if n == 2:
        # Sits between the supporting line and the phone. At the old y it ran straight through
        # "upcoming rate changes" — the bars are 294px tall at the right-hand end.
        tallest = 54 + 30 * 8
        return (motif_progression(MARGIN, 1198, count=9, gap=22, base=54, growth=30,
                                  width=26, ink="#C6BFB0", accent=ORANGE, accent_from=7),
                (MARGIN, 1198 - tallest, 9 * 48 - 22, tallest))
    if n == 3:
        pad = 74
        box = (g["device_x"] - pad, g["device_y"] - pad,
               g["device_w"] + pad * 2, g["device_h"] + pad * 2)
        return (motif_scan_edges(*box, ink="#BCB4A5", accent=ORANGE, stroke=8), box)
    if n == 4:
        return (motif_stop_block(MARGIN, 1960, W - MARGIN * 2 - 40, 46, ran=0.62,
                                 ink="#B2AA9B", accent=ORANGE, stroke=7),
                (MARGIN, 1960 - 29, W - MARGIN * 2 - 40, 46 + 58))
    if n == 5:
        return (motif_staged(MARGIN, 2452, count=3, w=108, h=76, gap=30,
                             ink="#BCB4A5", accent=ORANGE, stroke=7),
                (MARGIN, 2452, 3 * 138 + 60, 76))
    if n == 6:
        return (motif_variance(MARGIN, 1000, W - MARGIN * 2 - 120, bar_h=46, gap=30,
                               expected=0.58, invoiced=0.86, ink=GRAPHITE_3, accent=ORANGE),
                (MARGIN, 1000 - 23, W - MARGIN * 2 - 120, 46 * 2 + 30 + 46))
    return "", None


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


def build_template(spec: dict) -> tuple[str, dict]:
    dark = spec["dark"]
    ink = IVORY if dark else GRAPHITE
    muted = IVORY_MUTED if dark else INK_MUTED

    g = phone_geometry(
        spec["screen_w"],
        screen_x=(W - (spec["screen_w"] + spec["screen_w"] * BEZEL_RATIO * 2)) / 2
        + spec["screen_w"] * BEZEL_RATIO + spec["device_dx"],
        screen_y=spec["device_y"] + spec["screen_w"] * BEZEL_RATIO,
    )

    head_size = GALLERY_HEAD_SIZE
    sub_size = GALLERY_SUB_SIZE

    motif, motif_box = motif_for(spec, g)

    if spec["align"] == "center":
        tx, anchor = W / 2, "middle"
    else:
        tx, anchor = MARGIN, "start"

    head_leading = head_size * 1.06
    head_y = spec["head_y"]
    sub_y = head_y + head_leading * (len(spec["headline"]) - 1) + head_size * 1.02 + 34

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
        f'viewBox="0 0 {W} {H}" role="img" '
        f'aria-label="OffRent Ledger App Store template {spec["n"]}">',
        f"  <title>OffRent Ledger — App Store template {spec['n']} — {spec['slug']}</title>",
        defs(dark),
        background(spec["bg"]),
        motif,
        phone_svg(g, screen_fill=SCREEN_DARK if dark else SCREEN_LIGHT, dark=dark,
                  rotation=spec["rotation"]),
        text_block(spec["headline"], x=tx, y=head_y, weight="Bold", size=head_size,
                   fill=ink, leading=head_leading, tracking_em=-0.022, anchor=anchor),
        text_block(spec["sub"], x=tx, y=sub_y, weight="Medium", size=sub_size,
                   fill=muted, leading=sub_size * 1.36, tracking_em=-0.004, anchor=anchor),
        "</svg>",
    ]

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
    device_box = rotated_bounds(g, spec["rotation"])

    for name, box in [("headline", head_box), ("supporting text", sub_box)]:
        if box[0] < MARGIN - 1 or box[0] + box[2] > W - MARGIN + 1:
            raise SystemExit(
                f"template {spec['n']}: {name} breaks the {MARGIN}px margin "
                f"(x {box[0]:.0f} to {box[0] + box[2]:.0f})")
        if box[1] < 40 or box[1] + box[3] > H - 40:
            raise SystemExit(f"template {spec['n']}: {name} runs off the canvas vertically")
        if overlaps(box, device_box):
            raise SystemExit(f"template {spec['n']}: {name} overlaps the phone")
        if motif_box and overlaps(box, motif_box):
            raise SystemExit(f"template {spec['n']}: {name} overlaps the accent motif")

    # The device may bleed off an edge on purpose, but never so far that it stops being a phone.
    visible_w = min(device_box[0] + device_box[2], W) - max(device_box[0], 0)
    visible_h = min(device_box[1] + device_box[3], H) - max(device_box[1], 0)
    if visible_w < device_box[2] * 0.62 or visible_h < device_box[3] * 0.55:
        raise SystemExit(f"template {spec['n']}: too little of the phone is on the canvas")

    placement = {
        "n": spec["n"], "slug": spec["slug"], "shot": spec["shot"],
        "screen_x": round(g["screen_x"], 1), "screen_y": round(g["screen_y"], 1),
        "screen_w": round(g["screen_w"], 1), "screen_h": round(g["screen_h"], 1),
        "screen_r": round(g["screen_r"], 1),
        "rotation": spec["rotation"],
        "pivot_x": round(g["device_x"] + g["device_w"] / 2, 1),
        "pivot_y": round(g["device_y"] + g["device_h"] / 2, 1),
        "scale": round(g["screen_w"] / W, 4),
        "head_size": head_size, "sub_size": sub_size,
        "headline": " ".join(spec["headline"]),
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


def placement_guide(placements: list[dict]) -> str:
    rows = "\n".join(
        f"| {p['n']} | `{p['screen_x']}` | `{p['screen_y']}` | `{p['screen_w']}` | "
        f"`{p['screen_h']}` | `{p['screen_r']}` | `{p['rotation']}°` | {p['shot']} |"
        for p in placements
    )
    detail = "\n\n".join(
        f"""### Template {p['n']} — {p['slug']}

> {p['headline']}

**Intended screenshot:** {p['shot']}

| | |
|---|---|
| Screen opening | `{p['screen_w']} × {p['screen_h']}` px |
| Top-left corner | `x = {p['screen_x']}`, `y = {p['screen_y']}` |
| Corner radius | `{p['screen_r']}` px |
| Rotation | `{p['rotation']}°`{'' if not p['rotation'] else f" about `({p['pivot_x']}, {p['pivot_y']})`"} |
| Scale from source | `{p['scale']}` — resize the 1290 × 2796 capture to `{p['screen_w']} × {p['screen_h']}` |
"""
        for p in placements
    )

    return f"""# OffRent Ledger — App Store template placement guide

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
{rows}

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

{detail}

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
| Warm ivory | `{IVORY}` |
| Soft stone | `{STONE}` |
| Deep graphite | `{GRAPHITE}` |
| Secondary graphite | `{GRAPHITE_2}` |
| Construction orange | `{ORANGE}` |
| Blank screen, light templates | `{SCREEN_LIGHT}` |
| Blank screen, graphite template | `{SCREEN_DARK}` |

Five of the six are light — warm ivory and pale stone with graphite structure. Template 6 is the
single graphite frame, placed last so the gallery closes on its strongest contrast rather than
opening on it.

The palette is ivory, stone, graphite and one orange. There is no blue anywhere in the set, from
a sibling product or otherwise — `validate_appstore_templates.py` samples every finished PNG and
fails on any blue-dominant pixel.
"""


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    placements, pngs = [], []

    for spec in TEMPLATES:
        svg, placement = build_template(spec)
        stem = f"OffRent-AppStore-Template-{spec['n']:02d}-{spec['slug']}"
        svg_path = OUT / f"{stem}.svg"
        png_path = OUT / f"OffRent-AppStore-Template-{spec['n']:02d}.png"
        svg_path.write_text(svg)
        rasterise(svg_path, png_path)
        placements.append(placement)
        pngs.append(png_path)
        print(f"  {png_path.name}  head {placement['head_size']}px  "
              f"screen {placement['screen_w']}x{placement['screen_h']} @ "
              f"({placement['screen_x']}, {placement['screen_y']})")

    contact_sheet(pngs, OUT / "OffRent-AppStore-Contact-Sheet.png")
    (OUT / "OffRent-AppStore-Template-Placement-Guide.md").write_text(placement_guide(placements))
    print(f"wrote: {OUT.relative_to(ROOT)}/ — 6 SVG masters, 6 PNGs, contact sheet, placement guide")
    return 0


if __name__ == "__main__":
    sys.exit(main())
