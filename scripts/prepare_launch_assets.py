#!/usr/bin/env python3
"""Builds the two launch-screen images from the artwork committed at the repository root.

  * `LaunchMark` — the orange tag lifted off the app icon's graphite ground, on a transparent
    square canvas. `UILaunchScreen` centres and scales its image, so the canvas has to be square
    or iOS stretches the mark; and it has to be transparent, because the launch screen paints
    `LaunchBackground` behind it.
  * `IdleryWordmark` — the "idlery" wordmark trimmed out of a 14336x14336 canvas that is 97%
    empty, then keyed so the white it was drawn on does not show as a pale slab on the warm-white
    launch background.

Both are derived rather than hand-cropped so that replacing either master and re-running this
produces the same result. Run: python3 scripts/prepare_launch_assets.py
Check: python3 scripts/prepare_launch_assets.py --check
"""

import pathlib
import sys

from PIL import Image, ImageChops, ImageOps

Image.MAX_IMAGE_PIXELS = None

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "OffRentLedger" / "Resources" / "Assets.xcassets"
ICON_MASTER = ROOT / "marketing" / "AppIcon" / "OffRentLedger-AppIcon-master.png"
IDLERY_MASTER = ROOT / "Idlery-Loading-Logo.png"

MARK_SIZE = 1024
WORDMARK_HEIGHT = 96


def _contents(filename: str, *, template: bool = False) -> str:
    # The wordmark keeps its own colour: it is somebody else's brand mark, not an icon of ours to
    # tint. Only the launch mark would ever want template rendering, and it does not want it
    # either — the tag is orange on purpose.
    rendering = '\n      "template-rendering-intent" : "template",' if template else ""
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
        '  "info" : { "author" : "xcode", "version" : 1 }' + rendering + '\n'
        '}\n'
    )


def build_mark() -> Image.Image:
    """The tag, cut off the icon's graphite ground."""
    icon = Image.open(ICON_MASTER).convert("RGB")
    ground = icon.getpixel((4, 4))

    # Keyed by distance from the ground colour rather than by an exact match, so the artwork's
    # anti-aliased edges fade out instead of leaving a one-pixel graphite fringe around the tag.
    # The tag's own punch-hole is the ground colour too, and this correctly makes it a hole.
    #
    # Built out of whole-image channel operations. The obvious per-pixel loop is a million
    # iterations of Python for the icon and two hundred million for the wordmark below, which is
    # the difference between a second and several minutes.
    near, far = 26, 78
    channels = []
    for plane, level in zip(icon.split(), ground):
        channels.append(ImageChops.difference(plane, Image.new("L", icon.size, level)))
    # max(|dr|, |dg|, |db|) — same job as Euclidean distance for keying a flat colour, and it is
    # two lighter() calls instead of a square root per pixel.
    distance = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), channels[2])
    alpha = distance.point(
        lambda d: 0 if d <= near else (255 if d >= far else int(255 * (d - near) / (far - near)))
    )
    tagged = icon.convert("RGBA")
    tagged.putalpha(alpha)

    box = alpha.getbbox()
    if box is None:
        raise SystemExit("the icon is a single flat colour; nothing to lift off it")
    tag = tagged.crop(box)

    # Square, with the mark at 76% of it. `UILaunchScreen` scales the image to fit the screen's
    # smaller dimension, so the padding is what actually sets how large the tag appears.
    side = max(tag.size)
    canvas_side = int(side / 0.76)
    canvas = Image.new("RGBA", (canvas_side, canvas_side), (0, 0, 0, 0))
    canvas.alpha_composite(tag, (
        (canvas_side - tag.width) // 2,
        (canvas_side - tag.height) // 2,
    ))
    return canvas.resize((MARK_SIZE, MARK_SIZE), Image.LANCZOS)


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


TARGETS = {
    "LaunchMark": ("LaunchMark.png", build_mark, False),
    "IdleryWordmark": ("IdleryWordmark.png", build_wordmark, False),
}


def main() -> int:
    checking = "--check" in sys.argv
    for name, (filename, build, template) in TARGETS.items():
        folder = ASSETS / f"{name}.imageset"
        target = folder / filename
        if checking:
            if not target.exists():
                print(f"MISSING: {target.relative_to(ROOT)}")
                return 1
            image = Image.open(target)
            if image.mode != "RGBA":
                print(f"NOT TRANSPARENT: {target.relative_to(ROOT)} is {image.mode}")
                return 1
            if name == "LaunchMark" and image.width != image.height:
                print(f"NOT SQUARE: {target.relative_to(ROOT)} is {image.size}")
                return 1
            print(f"ok: {target.relative_to(ROOT)} {image.size} {image.mode}")
            continue

        folder.mkdir(parents=True, exist_ok=True)
        image = build()
        image.save(target)
        (folder / "Contents.json").write_text(_contents(filename, template=template))
        print(f"wrote: {target.relative_to(ROOT)} {image.size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
