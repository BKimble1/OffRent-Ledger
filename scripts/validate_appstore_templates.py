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
    6: "Spot possible billing differences.",
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
