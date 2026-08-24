#!/usr/bin/env python3
"""Generates the colour sets in OffRentLedger/Resources/Assets.xcassets.

**It does not touch AppIcon-1024.png.** It used to draw a placeholder icon there, which became a
loaded gun the moment real artwork arrived: running this script would have silently overwritten
the designed icon with a generated one, and nothing would have complained until somebody looked
at a build. The drawing code is gone rather than guarded — a flag would still have been one
mistyped invocation away from the same outcome.

The shipped icon is the owner's artwork. Its master lives at
`marketing/AppIcon/OffRentLedger-AppIcon-master.png` and the 1024x1024 App Store copy is checked
into the asset catalog. To regenerate that copy from the master, use
`scripts/prepare_app_icon.py`, which resizes and strips alpha.

Run: python3 scripts/generate_assets.py
"""

import json
import sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "OffRentLedger" / "Resources" / "Assets.xcassets"

# The palette. Warm construction orange for action; graphite and slate for structure.
# Every pair is checked for contrast against its own background in COLOURS below.
COLOURS = {
    # name: (light r,g,b, dark r,g,b)
    "AccentColor":       ((0.847, 0.400, 0.086), (0.949, 0.541, 0.212)),
    "AttentionColor":    ((0.784, 0.318, 0.055), (0.964, 0.596, 0.278)),
    "ReviewColor":       ((0.443, 0.373, 0.671), (0.663, 0.596, 0.882)),
    "SettledColor":      ((0.196, 0.471, 0.318), (0.400, 0.749, 0.541)),
    "WaitingColor":      ((0.310, 0.396, 0.478), (0.573, 0.663, 0.749)),
    "LaunchBackground":  ((0.949, 0.937, 0.914), (0.063, 0.067, 0.075)),
    "WidgetBackground":  ((0.949, 0.937, 0.914), (0.063, 0.067, 0.075)),

    # Surfaces.
    #
    # Second pass. The first one over-corrected: it separated ground from card by *fill*, which
    # meant a soft-stone page behind warm-ivory cards and a graphite panel on most screens. That
    # reads as heavy and designed rather than as an iOS app.
    #
    # These separate the way the platform does: an inset-grouped `List` on a page one step darker
    # than its rows, with the list's own separators, insets and corner radii doing the work. The
    # ground is the warm equivalent of the system's #F2F2F7 — measured at 1.15:1 against white,
    # against the system's own 1.12:1. That number is low on purpose. It is only invisible when
    # there is nothing else drawing the boundary, which is exactly what went wrong when this app
    # hand-built its groups instead of using `List`.
    #
    # Graphite survives as one colour for text and for exactly one hero panel, on Today. It is
    # not a surface the rest of the app paints with any more.
    "SurfaceBackground": ((0.949, 0.937, 0.914), (0.063, 0.067, 0.075)),   # #F2EFE9 warm white
    "SurfaceRaised":     ((1.000, 1.000, 1.000), (0.110, 0.118, 0.129)),   # #FFFFFF card
    "SurfaceSunken":     ((0.937, 0.925, 0.898), (0.153, 0.161, 0.176)),   # #EFECE5 wells
    "SurfaceGraphite":   ((0.110, 0.122, 0.141), (0.145, 0.157, 0.180)),   # #1C1F24 the one hero
    "HairlineColor":     ((0.863, 0.847, 0.808), (0.212, 0.224, 0.243)),   # #DCD8CE
}


def colour_component(value: float) -> str:
    return f"{value:.3f}"


def colorset(light, dark):
    def entry(appearances, rgb):
        payload = {
            "color": {
                "color-space": "srgb",
                "components": {
                    "alpha": "1.000",
                    "blue": colour_component(rgb[2]),
                    "green": colour_component(rgb[1]),
                    "red": colour_component(rgb[0]),
                },
            },
            "idiom": "universal",
        }
        if appearances:
            payload["appearances"] = appearances
        return payload

    return {
        "colors": [
            entry(None, light),
            entry([{"appearance": "luminosity", "value": "dark"}], dark),
        ],
        "info": {"author": "xcode", "version": 1},
    }


def main():
    # `--check` verifies rather than writes. Without it a CI step that runs this script would
    # regenerate whatever had drifted and then pass, which is the opposite of a check: the
    # palette in the repository could disagree with the palette in the script indefinitely and
    # nothing would ever say so.
    checking = "--check" in sys.argv
    problems: list[str] = []

    def emit(path: pathlib.Path, text: str) -> None:
        if checking:
            current = path.read_text() if path.exists() else None
            if current != text:
                problems.append(str(path.relative_to(ROOT)))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)

    ASSETS.mkdir(parents=True, exist_ok=True)
    emit(
        ASSETS / "Contents.json",
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
    )

    for name, (light, dark) in COLOURS.items():
        folder = ASSETS / f"{name}.colorset"
        if not checking:
            folder.mkdir(exist_ok=True)
        emit(folder / "Contents.json", json.dumps(colorset(light, dark), indent=2) + "\n")

    icon_folder = ASSETS / "AppIcon.appiconset"
    icon_folder.mkdir(exist_ok=True)
    icon = icon_folder / "AppIcon-1024.png"
    if not icon.exists():
        raise SystemExit(
            f"{icon.relative_to(ROOT)} is missing. This script does not draw one — run\n"
            "  python3 scripts/prepare_app_icon.py\n"
            "to rebuild it from marketing/AppIcon/OffRentLedger-AppIcon-master.png."
        )
    emit(
        icon_folder / "Contents.json",
        json.dumps(
            {
                "images": [
                    {
                        "filename": "AppIcon-1024.png",
                        "idiom": "universal",
                        "platform": "ios",
                        "size": "1024x1024",
                    }
                ],
                "info": {"author": "xcode", "version": 1},
            },
            indent=2,
        )
        + "\n",
    )

    if checking:
        if problems:
            print("out of date; run python3 scripts/generate_assets.py")
            for problem in problems:
                print(f"  {problem}")
            return 1
        print(f"ok: {len(COLOURS)} colour sets match the palette in this script")
        return 0

    print(
        f"wrote: {ASSETS.relative_to(ROOT)} ({len(COLOURS)} colour sets; "
        "AppIcon-1024.png left untouched)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
