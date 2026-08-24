#!/usr/bin/env python3
"""Builds the two launch-screen images from the artwork committed at the repository root.

  * `LaunchMark` — the orange tag lifted off the app icon's ground, on a transparent square
    canvas, rendered at 1x, 2x and 3x.

    The scales are the whole point. `UILaunchScreen` draws its image at the image's own *point*
    size — it does not scale to the screen. A single 1024-pixel file in the 1x slot is therefore
    1024 points wide, two and a half times the width of an iPhone, and the launch screen opens on
    a gigantic cropped tag that then jumps to the size `LaunchSplashView` draws. Emitting real
    1x/2x/3x renditions of one point size is what makes the handover invisible.
  * `IdleryWordmark` — the "idlery" wordmark trimmed out of a 14336x14336 canvas that is 97%
    empty, then keyed so the white it was drawn on does not show as a pale slab on the warm-white
    launch background.

Both are derived rather than hand-cropped so that replacing either master and re-running this
produces the same result. Run: python3 scripts/prepare_launch_assets.py
Check: python3 scripts/prepare_launch_assets.py --check
"""

import pathlib
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps

Image.MAX_IMAGE_PIXELS = None

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "OffRentLedger" / "Resources" / "Assets.xcassets"
ICON_MASTER = ROOT / "marketing" / "AppIcon" / "OffRentLedger-AppIcon-master.png"
IDLERY_MASTER = ROOT / "Idlery-Loading-Logo.png"

# The mark's point size. `LaunchSplashView.markPoints` carries the same number, and
# `LaunchScreenTests` fails if they drift: `UILaunchScreen` draws its image at the image's own
# point size, so a disagreement means the tag changes size the instant SwiftUI takes over.
MARK_POINTS = 204
MARK_SCALES = (1, 2, 3)
WORDMARK_HEIGHT = 96


def _mark_contents() -> str:
    entries = ",\n".join(
        '    {\n'
        f'      "filename" : "LaunchMark@{scale}x.png",\n'
        '      "idiom" : "universal",\n'
        f'      "scale" : "{scale}x"\n'
        '    }'
        for scale in MARK_SCALES
    )
    return '{\n  "images" : [\n' + entries + '\n  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n'


def _single_contents(filename: str) -> str:
    return (
        '{\n'
        '  "images" : [\n'
        '    {\n'
        f'      "filename" : "{filename}",\n'
        '      "idiom" : "universal",\n'
        '      "scale" : "1x"\n'
        '    },\n'
        '    { "idiom" : "universal", "scale" : "2x" },\n'
        '    { "idiom" : "universal", "scale" : "3x" }\n'
        '  ],\n'
        '  "info" : { "author" : "xcode", "version" : 1 }\n'
        '}\n'
    )


def build_mark() -> Image.Image:
    """The tag, cut off the icon's ground, at the largest size any scale needs."""
    icon = Image.open(ICON_MASTER).convert("RGB")

    # Flood-filled from the border rather than keyed on colour distance.
    #
    # Distance keying worked while the icon was a tag on graphite: nothing inside the tag came
    # near that colour. The icon is a tag on warm white now, and the tick inside the tag is also
    # near-white — a global key would punch the tick straight out. Filling inward from the edges
    # only removes ground that is actually connected to the edge, so the tick survives whatever
    # colour the ground becomes next.
    mask = Image.new("L", icon.size, 0)
    mask.paste(icon.convert("L"))
    flood = Image.new("L", icon.size, 0)
    flood.paste(255, (0, 0, icon.width, icon.height))
    ground = icon.getpixel((2, 2))

    filled = icon.copy()
    marker = (255, 0, 255)
    for corner in ((1, 1), (icon.width - 2, 1), (1, icon.height - 2),
                   (icon.width - 2, icon.height - 2)):
        if filled.getpixel(corner) == marker:
            continue
        ImageDraw.floodfill(filled, corner, marker, thresh=26)

    # Anything the fill reached is ground; everything else is artwork.
    r, g, b = filled.split()
    is_marker = ImageChops.multiply(
        ImageChops.multiply(r.point(lambda v: 255 if v == 255 else 0),
                            g.point(lambda v: 255 if v == 0 else 0)),
        b.point(lambda v: 255 if v == 255 else 0),
    )
    alpha = is_marker.point(lambda v: 0 if v else 255)

    # Feather the edge back on. The fill leaves a hard, aliased boundary because it either takes
    # a pixel or does not; without this the tag has a visible staircase along its curves.
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.8)).point(
        lambda v: 0 if v < 40 else (255 if v > 215 else int((v - 40) * 255 / 175))
    )

    tagged = icon.convert("RGBA")
    tagged.putalpha(alpha)
    box = alpha.getbbox()
    if box is None:
        raise SystemExit("nothing left after removing the icon's ground")
    tag = tagged.crop(box)

    # Square, with the mark at 76% of it, so the tag has the breathing room around it that the
    # icon gives it.
    side = max(tag.size)
    canvas_side = int(side / 0.76)
    canvas = Image.new("RGBA", (canvas_side, canvas_side), (0, 0, 0, 0))
    canvas.alpha_composite(tag, (
        (canvas_side - tag.width) // 2,
        (canvas_side - tag.height) // 2,
    ))
    return canvas


def build_wordmark() -> Image.Image:
    """The Idlery wordmark, trimmed and lifted off its white."""
    art = Image.open(IDLERY_MASTER).convert("RGB")

    # The master is a 14336-square canvas that is almost entirely white, with the wordmark in the
    # middle. Find the ink first on a grayscale copy, crop to it, and only then do the per-pixel
    # work — so the expensive part runs over the wordmark rather than over 205 million empty
    # pixels.
    ink = ImageOps.invert(art.convert("L"))
    box = ink.point(lambda v: 255 if v > 8 else 0).getbbox()
    if box is None:
        raise SystemExit("the Idlery master is blank")

    cropped = art.crop(box)
    width, height = cropped.size
    source = cropped.load()
    out = Image.new("RGBA", cropped.size, (0, 0, 0, 0))
    target = out.load()

    # Un-premultiply against white, rather than taking alpha straight from the luminance.
    #
    # Every pixel of an anti-aliased wordmark drawn on white is `coverage * ink + (1 - coverage)
    # * white`. Using the luminance as alpha keeps that blend and then makes it translucent as
    # well, which is why the first attempt came out a washed-out pale teal instead of the teal in
    # the file. Recovering the coverage and the original ink colour keeps it exact.
    near, far = 6, 40
    for y in range(height):
        for x in range(width):
            r, g, b = source[x, y]
            deviation = max(255 - r, 255 - g, 255 - b)
            if deviation <= near:
                continue
            coverage = 1.0 if deviation >= far else (deviation - near) / (far - near)
            recovered = tuple(
                max(0, min(255, round((channel - 255 * (1 - coverage)) / coverage)))
                for channel in (r, g, b)
            )
            target[x, y] = (*recovered, round(255 * coverage))

    scale = WORDMARK_HEIGHT / height
    return out.resize((max(1, round(width * scale)), WORDMARK_HEIGHT), Image.LANCZOS)


def main() -> int:
    checking = "--check" in sys.argv
    problems: list[str] = []

    mark_folder = ASSETS / "LaunchMark.imageset"
    word_folder = ASSETS / "IdleryWordmark.imageset"

    if checking:
        for scale in MARK_SCALES:
            target = mark_folder / f"LaunchMark@{scale}x.png"
            if not target.exists():
                problems.append(f"MISSING: {target.relative_to(ROOT)}")
                continue
            image = Image.open(target)
            expected = MARK_POINTS * scale
            if image.size != (expected, expected):
                problems.append(
                    f"WRONG SIZE: {target.relative_to(ROOT)} is {image.size}, "
                    f"expected {expected}x{expected} for {scale}x at {MARK_POINTS}pt"
                )
            if image.mode != "RGBA":
                problems.append(f"NOT TRANSPARENT: {target.relative_to(ROOT)} is {image.mode}")
        word = word_folder / "IdleryWordmark.png"
        if not word.exists():
            problems.append(f"MISSING: {word.relative_to(ROOT)}")
        elif Image.open(word).mode != "RGBA":
            problems.append(f"NOT TRANSPARENT: {word.relative_to(ROOT)}")

        if problems:
            for problem in problems:
                print(problem)
            print("run: python3 scripts/prepare_launch_assets.py")
            return 1
        print(f"ok: LaunchMark at {MARK_POINTS}pt in {len(MARK_SCALES)} scales; wordmark present")
        return 0

    mark_folder.mkdir(parents=True, exist_ok=True)
    master = build_mark()
    for scale in MARK_SCALES:
        pixels = MARK_POINTS * scale
        target = mark_folder / f"LaunchMark@{scale}x.png"
        master.resize((pixels, pixels), Image.LANCZOS).save(target)
        print(f"wrote: {target.relative_to(ROOT)} {pixels}x{pixels}")
    (mark_folder / "Contents.json").write_text(_mark_contents())

    # Any earlier single-scale file would still be in the catalog and would still be the 1x, which
    # is the exact bug this replaces.
    stale = mark_folder / "LaunchMark.png"
    if stale.exists():
        stale.unlink()
        print(f"removed stale {stale.relative_to(ROOT)}")

    word_folder.mkdir(parents=True, exist_ok=True)
    wordmark = build_wordmark()
    wordmark.save(word_folder / "IdleryWordmark.png")
    (word_folder / "Contents.json").write_text(_single_contents("IdleryWordmark.png"))
    print(f"wrote: IdleryWordmark.png {wordmark.size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
