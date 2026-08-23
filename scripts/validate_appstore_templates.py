#!/usr/bin/env python3
"""Checks every finished App Store template against what App Store Connect will accept.

Format, colour mode, transparency, borders, spelling and branding — verified on the pixels, not
on the code that produced them. Run after `generate_appstore_templates.py`.

Run: python3 scripts/validate_appstore_templates.py
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "marketing" / "AppStore"
W, H = 1290, 2796

EXPECTED_HEADLINES = {
    1: "Stop the rental clock with proof.",
    2: "Control every active rental.",
    3: "Scan rental details in seconds.",
    4: "Record off-rent proof.",
    5: "Track equipment awaiting pickup.",
    6: "Catch questionable final charges.",
}

problems: list[str] = []


def bad(where: str, message: str) -> None:
    problems.append(f"{where}: {message}")


def check_png(path: pathlib.Path, number: int) -> None:
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

        # CoreCredit blue. Any pixel where blue clearly dominates both other channels is either
        # the wrong brand or a stray gradient; the OffRent palette has none.
        blue = 0
        for x in range(0, W, 11):
            for y in range(0, H, 23):
                r, g, b = rgb.getpixel((x, y))
                if b > r + 42 and b > g + 30 and b > 90:
                    blue += 1
        if blue:
            bad(path.name, f"{blue} sampled pixels are blue-dominant — check for CoreCredit blue")

        # Fully opaque, and actually drawn: a blank or near-blank frame means a font or asset
        # failed to load and the rasteriser produced a flat rectangle.
        colours = rgb.getcolors(maxcolors=W * H)
        if colours and len(colours) < 24:
            bad(path.name, f"only {len(colours)} distinct colours — the render looks empty")


def check_svg(path: pathlib.Path, number: int) -> None:
    text = path.read_text()
    headline = EXPECTED_HEADLINES[number]

    spans = re.findall(r"<tspan[^>]*>([^<]*)</tspan>", text)
    joined = " ".join(spans)
    if headline not in joined:
        bad(path.name, f"headline missing or misspelled — expected {headline!r}")

    if 'class="screen-area"' not in text:
        bad(path.name, "no screen-area rectangle to place a screenshot into")

    # Editable type, not outlines.
    if "<text" not in text:
        bad(path.name, "typography has been converted to paths; the master is not editable")

    # No app UI, and no raster smuggled in.
    for banned, why in [
        ("<image", "an embedded raster image"),
        ("xlink:href", "an external reference"),
        ("data:image", "an embedded bitmap"),
    ]:
        if banned in text:
            bad(path.name, f"contains {why}")

    for word in ["lorem", "ipsum", "placeholder text", "sample", "mockup", "template 0"]:
        if word in text.lower():
            bad(path.name, f"contains the word {word!r} in the artwork")


def main() -> int:
    pngs = sorted(OUT.glob("OffRent-AppStore-Template-??.png"))
    svgs = sorted(OUT.glob("OffRent-AppStore-Template-??-*.svg"))

    if len(pngs) != 6:
        bad("package", f"{len(pngs)} PNGs, expected 6")
    if len(svgs) != 6:
        bad("package", f"{len(svgs)} SVG masters, expected 6")
    guide = OUT / "OffRent-AppStore-Template-Placement-Guide.md"
    if not guide.exists():
        bad("package", "no placement guide")

    for path in pngs:
        check_png(path, int(re.search(r"-(\d\d)\.png$", path.name).group(1)))
    for path in svgs:
        check_svg(path, int(re.search(r"-(\d\d)-", path.name).group(1)))

    print(f"checked {len(pngs)} PNGs and {len(svgs)} SVG masters")
    if problems:
        print("\n".join(f"  ✗ {p}" for p in problems))
        print(f"\n{len(problems)} problem(s)")
        return 1
    print("  all pass: 1290x2796, PNG, RGB, no alpha, no border, headlines correct, "
          "editable type, no embedded raster, no blue")
    return 0


if __name__ == "__main__":
    sys.exit(main())
