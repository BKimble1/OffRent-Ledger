#!/usr/bin/env python3
"""Checks every finished App Store template against what App Store Connect will accept.

Format, size, colour mode, transparency, borders, spelling, branding, composition and — the one
this file exists for — that every screen opening is still an *empty* opening. Verified on the
artwork rather than on the code that produced it: the generator asserts its own layout before it
writes, and this asserts the same things again by reading the SVG and sampling the PNG, so a
change that fools one has to fool both.

What is checked, and why each one is here:

  * 1290 x 2796, PNG, RGB, no alpha, no stray ICC profile — App Store Connect refuses the upload
    otherwise, and says very little about which of them was wrong.
  * No unintended border. A one-pixel frame in a different colour is what a rasteriser leaves
    when the artboard and the viewBox disagree.
  * Seven screen openings across six templates: two on template 2, one on each of the others.
    The count is the composition rule, so it is a test rather than a note in a guide.
  * Every opening is locked to 1290:2796, sits where the placement guide says, and is *blank* —
    sampled through the PNG, allowing for the rotation the SVG declares. A template with app UI
    painted into it is a picture of an interface, and this is what stops one shipping.
  * Headlines and supporting copy inside the safe margins, on the canvas, and clear of every
    device. Measured with the real Inter metrics, the same way the generator measures them.
  * No blue. The palette is ivory, stone, graphite and one orange; a cool cast anywhere means a
    sibling product's colour has leaked in, or the rasteriser has started fringing type.

Run: python3 scripts/validate_appstore_templates.py
"""

import math
import os
import pathlib
import re
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Same fontconfig as the generator, for the same reason: the measurements below have to be the
# ones the artwork was built with, not the ones this host happens to produce.
os.environ.setdefault("FONTCONFIG_FILE", str(ROOT / "scripts" / "fontconfig" / "fonts.conf"))

OUT = ROOT / "marketing" / "AppStore"
FONT_DIR = pathlib.Path("/usr/local/share/fonts/inter")
SVG_NS = "{http://www.w3.org/2000/svg}"

W, H = 1290, 2796
MARGIN = 104
SCREEN_RATIO = H / W
BEZEL_RATIO = 0.0312
SCREEN_RADIUS_RATIO = 0.1180

# The blank fills the generator paints into an opening. Anything else inside one is artwork that
# should not be there.
BLANK_FILLS = {(216, 210, 199), (74, 74, 72)}   # SCREEN_LIGHT #D8D2C7, SCREEN_DARK #4A4A48

EXPECTED_HEADLINES = {
    1: "Stop the rental clock with proof.",
    2: "Rental cost at a glance.",
    3: "Record off-rent proof.",
    4: "Find every rental on the map.",
    5: "Scan the contract. Review every field.",
    6: "Spot possible billing differences.",
}

EXPECTED_SLUGS = {
    1: "hero",
    2: "widget-glance",
    3: "off-rent-proof",
    4: "operations-map",
    5: "scan-review",
    6: "invoice-variance",
}

# Two devices on the widget frame and one everywhere else. This is the composition rule from the
# brief, written where it can fail a build: never two phones on the hero, the map, the scan, the
# proof or the invoice frame.
EXPECTED_OPENINGS = {1: 1, 2: 2, 3: 1, 4: 1, 5: 1, 6: 1}

# The frame that discloses the subscription, and the only one allowed to.
BADGE_TEMPLATE = 2
BADGE_TEXT = "Pro feature"

problems: list[str] = []


def bad(where: str, message: str) -> None:
    problems.append(f"{where}: {message}")


# --- type metrics, shared with the generator ----------------------------------------------------

_font_cache: dict = {}


def _font(weight: str, size: float):
    from PIL import ImageFont  # noqa: PLC0415

    key = (weight, round(size))
    if key not in _font_cache:
        path = FONT_DIR / f"Inter-{weight}.ttf"
        if not path.exists():
            raise SystemExit(f"missing font: {path}. Install Inter into {FONT_DIR}.")
        _font_cache[key] = ImageFont.truetype(str(path), round(size))
    return _font_cache[key]


WEIGHT_NAMES = {"700": "Bold", "600": "SemiBold", "500": "Medium", "400": "Regular"}


def advance(text: str, weight: str, size: float, letter_spacing: float) -> float:
    return _font(weight, size).getlength(text) + letter_spacing * max(len(text) - 1, 0)


# --- geometry ------------------------------------------------------------------------------------

def rotate_point(x: float, y: float, angle: float, cx: float, cy: float) -> tuple[float, float]:
    a = math.radians(angle)
    dx, dy = x - cx, y - cy
    return cx + dx * math.cos(a) - dy * math.sin(a), cy + dx * math.sin(a) + dy * math.cos(a)


def overlaps(a: tuple, b: tuple, slack: float = 0.0) -> bool:
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    return not (ax + aw + slack <= bx or bx + bw + slack <= ax
                or ay + ah + slack <= by or by + bh + slack <= ay)


def rotated_bounds(box: tuple, rotation: float) -> tuple:
    x, y, w, h = box
    if not rotation:
        return box
    cx, cy = x + w / 2, y + h / 2
    cos_a, sin_a = abs(math.cos(math.radians(rotation))), abs(math.sin(math.radians(rotation)))
    rw, rh = w * cos_a + h * sin_a, w * sin_a + h * cos_a
    return cx - rw / 2, cy - rh / 2, rw, rh


def parse_rotation(transform: str | None) -> tuple[float, float, float]:
    """`rotate(a cx cy)` -> (a, cx, cy). No transform is a rotation of zero about the origin."""
    if not transform:
        return 0.0, 0.0, 0.0
    match = re.search(r"rotate\(\s*(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s*\)", transform)
    if not match:
        return 0.0, 0.0, 0.0
    return float(match.group(1)), float(match.group(2)), float(match.group(3))


# --- the SVG master --------------------------------------------------------------------------

def read_openings(root: ET.Element) -> list[dict]:
    """Every screen opening in the master, in the order it is drawn."""
    openings = []
    for group in root.iter(f"{SVG_NS}g"):
        if group.get("class") != "device":
            continue
        rotation, pivot_x, pivot_y = parse_rotation(group.get("transform"))
        for rect in group:
            if rect.get("class") != "screen-area":
                continue
            openings.append({
                "id": rect.get("id"),
                "x": float(rect.get("x")), "y": float(rect.get("y")),
                "w": float(rect.get("width")), "h": float(rect.get("height")),
                "r": float(rect.get("rx")),
                "fill": rect.get("fill"),
                "rotation": rotation, "pivot": (pivot_x, pivot_y),
            })
    return openings


def read_text_blocks(root: ET.Element) -> list[dict]:
    """Every rendered text block, with the box its glyphs occupy.

    Reconstructed from the same numbers the generator wrote — anchor, size, weight, tracking, the
    `dy` on each tspan — rather than re-derived from the layout code, so a template hand-edited in
    a vector editor is measured as it now is rather than as it was generated.
    """
    blocks = []
    for node in root.iter(f"{SVG_NS}text"):
        size = float(node.get("font-size"))
        weight = WEIGHT_NAMES.get(node.get("font-weight", "400"), "Regular")
        tracking = float(node.get("letter-spacing") or 0)
        anchor = node.get("text-anchor", "start")
        spans = [child for child in node if child.tag == f"{SVG_NS}tspan"]
        if spans:
            lines = [(child.text or "", float(child.get("x")), float(child.get("dy") or 0))
                     for child in spans]
        else:
            lines = [(node.text or "", float(node.get("x")), 0.0)]

        baseline = float(node.get("y"))
        left, right, first, last = math.inf, -math.inf, math.inf, -math.inf
        for text, x, dy in lines:
            baseline += dy
            width = advance(text, weight, size, tracking)
            start = x - width / 2 if anchor == "middle" else (x - width if anchor == "end" else x)
            left, right = min(left, start), max(right, start + width)
            first, last = min(first, baseline), max(last, baseline)

        blocks.append({
            "text": " ".join(text for text, _, _ in lines),
            "size": size, "weight": weight,
            # Ascent and descent as fractions of the em, the same ones the generator asserts on.
            "box": (left, first - size * 0.74, right - left, (last - first) + size * 0.98),
        })
    return blocks


def check_svg(path: pathlib.Path, number: int) -> None:
    text = path.read_text()
    name = path.name
    headline = EXPECTED_HEADLINES[number]

    if EXPECTED_SLUGS[number] not in name:
        bad(name, f"expected the slug {EXPECTED_SLUGS[number]!r} in the filename")

    spans = re.findall(r"<tspan[^>]*>([^<]*)</tspan>", text)
    if headline not in " ".join(spans):
        bad(name, f"headline missing or misspelled — expected {headline!r}")

    if "<text" not in text:
        bad(name, "typography has been converted to paths; the master is not editable")

    for banned, why in [
        ("<image", "an embedded raster image"),
        ("xlink:href", "an external reference"),
        ("data:image", "an embedded bitmap"),
    ]:
        if banned in text:
            bad(name, f"contains {why}")

    rendered = " ".join(re.findall(r"<tspan[^>]*>([^<]*)</tspan>", text)
                        + re.findall(r"<title[^>]*>([^<]*)</title>", text)).lower()
    for word in ["lorem", "ipsum", "placeholder", "sample", "mockup", "your text", "headline here"]:
        if word in rendered:
            bad(name, f"the word {word!r} renders in the artwork")

    root = ET.fromstring(text)
    if (root.get("width"), root.get("height")) != (str(W), str(H)):
        bad(name, f"canvas is {root.get('width')}x{root.get('height')}, not {W}x{H}")
    if root.get("viewBox") != f"0 0 {W} {H}":
        bad(name, f"viewBox is {root.get('viewBox')!r} — it must match the canvas exactly")

    openings = read_openings(root)
    expected = EXPECTED_OPENINGS[number]
    if len(openings) != expected:
        bad(name, f"{len(openings)} screen opening(s), expected {expected}"
                  + (" — only template 2 may carry two devices" if len(openings) > expected else ""))

    for index, opening in enumerate(openings, start=1):
        where = f"{name} {opening['id'] or f'opening {index}'}"
        if opening["id"] != f"screen-{index}":
            bad(where, f"opening {index} is identified as {opening['id']!r}, expected 'screen-{index}'")

        ratio = opening["h"] / opening["w"]
        if abs(ratio - SCREEN_RATIO) > 0.002:
            bad(where, f"aspect is 1:{ratio:.4f}, not the screenshot's 1:{SCREEN_RATIO:.4f} — "
                       "a capture placed here would be stretched")

        radius = opening["r"] / opening["w"]
        if abs(radius - SCREEN_RADIUS_RATIO) > 0.002:
            bad(where, f"corner radius is {radius:.4f} of the width, not {SCREEN_RADIUS_RATIO}")

        if opening["w"] / W < 0.42:
            bad(where, f"the opening is {opening['w'] / W:.1%} of the canvas — too small to read "
                       "at App Store size")
        if expected == 1 and opening["w"] / W < 0.62:
            bad(where, f"a single-device frame's opening is {opening['w'] / W:.1%} of the canvas; "
                       "the brief's floor is 62%")

        # An opening may run off an edge on purpose. It may not be mostly off one.
        box = rotated_bounds((opening["x"], opening["y"], opening["w"], opening["h"]),
                             opening["rotation"])
        visible_w = min(box[0] + box[2], W) - max(box[0], 0)
        visible_h = min(box[1] + box[3], H) - max(box[1], 0)
        if visible_w < box[2] * 0.62 or visible_h < box[3] * 0.55:
            bad(where, f"only {visible_w / box[2]:.0%} x {visible_h / box[3]:.0%} of the opening "
                       "is on the canvas")

    blocks = read_text_blocks(root)
    if not blocks:
        bad(name, "no text at all — the headline and supporting line are missing")

    device_boxes = [
        rotated_bounds(
            (o["x"] - o["w"] * BEZEL_RATIO, o["y"] - o["w"] * BEZEL_RATIO,
             o["w"] * (1 + BEZEL_RATIO * 2), o["h"] + o["w"] * BEZEL_RATIO * 2),
            o["rotation"],
        )
        for o in openings
    ]

    for block in blocks:
        x, y, w, h = block["box"]
        label = f"{block['text'][:38]!r}"
        if x < MARGIN - 1 or x + w > W - MARGIN + 1:
            bad(name, f"{label} breaks the {MARGIN}px safe margin (x {x:.0f} to {x + w:.0f})")
        if y < 0 or y + h > H:
            bad(name, f"{label} is clipped by the canvas (y {y:.0f} to {y + h:.0f})")
        for index, device_box in enumerate(device_boxes, start=1):
            if overlaps(block["box"], device_box):
                bad(name, f"{label} collides with phone {index}")

    badge = re.search(r'class="disclosure-badge"', text)
    if number == BADGE_TEMPLATE:
        if not badge or BADGE_TEXT not in text:
            bad(name, f"the widget frame must disclose the tier: no {BADGE_TEXT!r} badge")
    elif badge:
        bad(name, "carries a tier-disclosure badge; only the widget frame may")


# --- the rasterised PNG -------------------------------------------------------------------------

def check_png(path: pathlib.Path, number: int, openings: list[dict]) -> None:
    from PIL import Image  # noqa: PLC0415

    with Image.open(path) as im:
        if im.format != "PNG":
            bad(path.name, f"format is {im.format}, not PNG")
        if im.size != (W, H):
            bad(path.name, f"size is {im.size[0]}x{im.size[1]}, not {W}x{H}")
        if im.mode != "RGB":
            bad(path.name, f"mode is {im.mode}, not RGB — App Store Connect rejects alpha")
        if "transparency" in im.info:
            bad(path.name, "carries a transparency chunk")
        # An untagged RGB PNG is read as sRGB, which is what these are. A *different* profile
        # would silently reinterpret every colour in the palette.
        profile = im.info.get("icc_profile")
        if profile and b"sRGB" not in profile:
            bad(path.name, "carries an ICC profile that is not sRGB")
        rgb = im.convert("RGB")

        # An unintended border: a one-pixel frame in a different colour than the region behind it,
        # which is what a rasteriser leaves when the artboard and the viewBox disagree.
        for name, (edge, inner) in {
            "top": ([rgb.getpixel((x, 0)) for x in range(0, W, 37)],
                    [rgb.getpixel((x, 6)) for x in range(0, W, 37)]),
            "bottom": ([rgb.getpixel((x, H - 1)) for x in range(0, W, 37)],
                       [rgb.getpixel((x, H - 7)) for x in range(0, W, 37)]),
            "left": ([rgb.getpixel((0, y)) for y in range(0, H, 79)],
                     [rgb.getpixel((6, y)) for y in range(0, H, 79)]),
            "right": ([rgb.getpixel((W - 1, y)) for y in range(0, H, 79)],
                      [rgb.getpixel((W - 7, y)) for y in range(0, H, 79)]),
        }.items():
            drifted = sum(
                1 for e, i in zip(edge, inner)
                if max(abs(a - b) for a, b in zip(e, i)) > 14
            )
            if drifted > len(edge) * 0.25:
                bad(path.name, f"{name} edge looks like an unintended border "
                               f"({drifted}/{len(edge)} samples differ from just inside)")

        # Blue-grey, not just blue.
        #
        # The first threshold here was b > r + 42, which is a *saturated* blue. It passed every
        # template while the graphite frame's blank screen was #434D5C and its comparison lines
        # were #39414E — both unmistakably blue-grey to the eye, both well inside the old margin.
        # A palette of ivory, stone, graphite and orange has no reason to drift blue at all, so
        # the test is now for any cool cast: blue meaningfully ahead of both other channels.
        #
        # Secondary graphite #252A31 (b=49, r=37) sits just under this and is allowed — it is the
        # brand's own dark from the app icon.
        offenders: dict[tuple[int, int, int], int] = {}
        for x in range(0, W, 9):
            for y in range(0, H, 17):
                r, g, b = rgb.getpixel((x, y))
                if b > r + 14 and b > g + 8 and b > 70:
                    offenders[(r, g, b)] = offenders.get((r, g, b), 0) + 1
        if offenders:
            worst = sorted(offenders.items(), key=lambda kv: -kv[1])[:3]
            listed = ", ".join(f"#{r:02X}{g:02X}{b:02X}x{n}" for (r, g, b), n in worst)
            bad(path.name, f"{sum(offenders.values())} sampled pixels have a cool/blue cast "
                           f"({listed})")

        # Fully opaque, and actually drawn: a blank or near-blank frame means a font or asset
        # failed to load and the rasteriser produced a flat rectangle.
        colours = rgb.getcolors(maxcolors=W * H)
        if colours and len(colours) < 24:
            bad(path.name, f"only {len(colours)} distinct colours — the render looks empty")

        # Every opening is still an opening.
        #
        # This is the check the whole gallery rests on. A template is a hole for a real capture;
        # the moment somebody paints a card, a figure or a status bar into one, the artwork is a
        # drawing of an app. Sampled on a grid inset from the edges — clear of the corner radius
        # and the Dynamic Island — and rotated with the device where the device is rotated.
        for opening in openings:
            angle, pivot_x, pivot_y = opening["rotation"], *opening["pivot"]
            painted, total = 0, 0
            for u in range(12, 89, 4):           # percent across the opening
                for v in range(14, 97, 3):       # percent down it, starting under the island
                    px = opening["x"] + opening["w"] * u / 100
                    py = opening["y"] + opening["h"] * v / 100
                    if angle:
                        px, py = rotate_point(px, py, angle, pivot_x, pivot_y)
                    if not (0 <= px < W and 0 <= py < H):
                        continue
                    total += 1
                    pixel = rgb.getpixel((round(px), round(py)))
                    if not any(
                        max(abs(a - b) for a, b in zip(pixel, fill)) <= 6 for fill in BLANK_FILLS
                    ):
                        painted += 1
            if total and painted / total > 0.02:
                bad(path.name, f"{opening['id']} is not blank — {painted}/{total} sampled pixels "
                               "inside it are not the empty-screen fill. A template must be a "
                               "hole for a real capture, never a drawing of one.")


def main() -> int:
    pngs = sorted(OUT.glob("OffRent-AppStore-Template-??.png"))
    svgs = sorted(OUT.glob("OffRent-AppStore-Template-??-*.svg"))

    if len(pngs) != 6:
        bad("package", f"{len(pngs)} PNGs, expected 6")
    if len(svgs) != 6:
        bad("package", f"{len(svgs)} SVG masters, expected 6")
    for expected in range(1, 7):
        if not (OUT / f"OffRent-AppStore-Template-{expected:02d}.png").exists():
            bad("package", f"OffRent-AppStore-Template-{expected:02d}.png is missing")
    guide = OUT / "OffRent-AppStore-Template-Placement-Guide.md"
    if not guide.exists():
        bad("package", "no placement guide")
    sheet = OUT / "OffRent-AppStore-Contact-Sheet.png"
    if not sheet.exists():
        bad("package", "no contact sheet")

    openings_by_number: dict[int, list[dict]] = {}
    for path in svgs:
        number = int(re.search(r"-(\d\d)-", path.name).group(1))
        check_svg(path, number)
        openings_by_number[number] = read_openings(ET.fromstring(path.read_text()))

    for path in pngs:
        number = int(re.search(r"-(\d\d)\.png$", path.name).group(1))
        check_png(path, number, openings_by_number.get(number, []))

    total_openings = sum(len(v) for v in openings_by_number.values())
    if guide.exists():
        guide_text = guide.read_text()
        # The guide is generated from the same placements the artwork is, and the pairing is
        # what somebody actually works from. A guide that has drifted from the masters sends a
        # capture to coordinates that no longer exist.
        for number, openings in openings_by_number.items():
            for opening in openings:
                needle = f"`x = {round(opening['x'], 1)}`, `y = {round(opening['y'], 1)}`"
                if needle not in guide_text:
                    bad("placement guide",
                        f"template {number} {opening['id']} is at {needle}, which the guide "
                        "does not mention — regenerate it")

    print(f"checked {len(pngs)} PNGs and {len(svgs)} SVG masters, {total_openings} screen openings")
    if problems:
        print("\n".join(f"  ✗ {p}" for p in problems))
        print(f"\n{len(problems)} problem(s)")
        return 1
    print("  all pass: 1290x2796, PNG, RGB, no alpha, no ICC surprise, no border, no blue; "
          "headlines correct, editable type, no embedded raster; 2 openings on template 2 and 1 "
          "on every other, all locked to 1290:2796, all blank; copy inside the margins and clear "
          "of every device; the placement guide matches the artwork")
    return 0


if __name__ == "__main__":
    sys.exit(main())
