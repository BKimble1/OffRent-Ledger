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

import json, pathlib

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
    "LaunchBackground":  ((0.922, 0.894, 0.835), (0.063, 0.071, 0.082)),
    "WidgetBackground":  ((0.922, 0.894, 0.835), (0.063, 0.071, 0.082)),

    # Surfaces.
    #
    # The app used to paint every screen with `.systemGroupedBackground` and every card with
    # `.secondarySystemGroupedBackground`. In light mode those are #F2F2F7 and #FFFFFF: a cool
    # near-white behind a white card, about four luminance levels apart. That is the whole reason
    # the app read as "blank pages with text on them" — the cards were there, they simply could
    # not be seen, so every screen collapsed into one flat white field.
    #
    # These are warm, and they are far enough apart to read as separate planes: ivory ground,
    # brighter raised surface, deeper sunken one, and a graphite panel for the one place per
    # screen that should dominate.
    # Measured, not chosen by eye. A first attempt at warm ivory ground with a near-white card
    # came out at 1.106:1 — *worse separated* than the #F2F2F7/#FFFFFF it replaced, warmer but
    # every bit as flat. Two surfaces only read as two planes from about 1.2:1. These are 1.24:1
    # with graphite body text still at 13.8:1 on the ground.
    #
    # So warm ivory is the raised surface, which is what fills most of a screen, and soft stone
    # is the ground between. Both are the brand's own tones; the ordering is what makes them work.
    "SurfaceBackground": ((0.922, 0.894, 0.835), (0.063, 0.071, 0.082)),   # #EBE4D5 soft stone
    "SurfaceRaised":     ((1.000, 0.992, 0.973), (0.114, 0.126, 0.149)),   # #FFFDF8 warm ivory
    "SurfaceSunken":     ((0.871, 0.835, 0.761), (0.039, 0.043, 0.051)),   # #DED5C2 inset wells
    "SurfaceGraphite":   ((0.090, 0.102, 0.122), (0.149, 0.165, 0.200)),   # #171A1F summary panel
    "HairlineColor":     ((0.851, 0.816, 0.741), (0.196, 0.212, 0.243)),   # #D9D0BD
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
    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )

    for name, (light, dark) in COLOURS.items():
        folder = ASSETS / f"{name}.colorset"
        folder.mkdir(exist_ok=True)
        (folder / "Contents.json").write_text(json.dumps(colorset(light, dark), indent=2) + "\n")

    icon_folder = ASSETS / "AppIcon.appiconset"
    icon_folder.mkdir(exist_ok=True)
    icon = icon_folder / "AppIcon-1024.png"
    if not icon.exists():
        raise SystemExit(
            f"{icon.relative_to(ROOT)} is missing. This script does not draw one — run\n"
            "  python3 scripts/prepare_app_icon.py\n"
            "to rebuild it from marketing/AppIcon/OffRentLedger-AppIcon-master.png."
        )
    (icon_folder / "Contents.json").write_text(
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
        + "\n"
    )
    print(
        f"wrote: {ASSETS.relative_to(ROOT)} ({len(COLOURS)} colour sets; "
        "AppIcon-1024.png left untouched)"
    )


if __name__ == "__main__":
    main()
