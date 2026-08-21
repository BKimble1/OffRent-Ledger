#!/usr/bin/env python3
"""Generates OffRentLedger/Resources/Assets.xcassets and an original placeholder app icon.

The icon is an ORIGINAL geometric mark drawn here in code: an orange octagonal stop outline with a
graphite clock hand at the off-rent hour. It borrows nothing from any other app — in particular it
shares no shape, colour or motif with the owner's CoreCredit project, whose identity is blue.

It is a placeholder. It is legally clean and it will render correctly at every size, but it is not
finished brand work; RELEASE_CHECKLIST.md §5 lists final marketing artwork as outstanding.

Run: python3 scripts/generate_assets.py
"""

import json, math, pathlib, struct, zlib

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
    "LaunchBackground":  ((0.976, 0.973, 0.965), (0.086, 0.090, 0.098)),
    "WidgetBackground":  ((0.976, 0.973, 0.965), (0.098, 0.102, 0.110)),
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


# --- PNG writing, with no third-party dependency -------------------------------------------

def write_png(path: pathlib.Path, pixels, width, height):
    """pixels: flat list of (r,g,b,a) bytes rows."""
    raw = b"".join(b"\x00" + bytes(row) for row in pixels)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def draw_icon(size: int):
    """An orange octagon outline with a graphite clock hand, on a warm off-white ground.

    Drawn with 3x supersampling so the diagonals of the octagon are not jagged at 1024px, and
    stay clean when iOS downsamples for the smaller slots.
    """
    ss = 3
    n = size * ss
    centre = n / 2.0
    background = (0.988, 0.984, 0.976)
    orange = (0.847, 0.400, 0.086)
    graphite = (0.169, 0.180, 0.196)

    outer = n * 0.36
    inner = n * 0.27          # octagon stroke thickness lives between these
    hand_length = n * 0.20
    hand_width = n * 0.055
    hub = n * 0.045

    def octagon_radius(angle: float, circumradius: float) -> float:
        # Apothem/cos of the angle within one of the eight sectors.
        sector = math.pi / 8
        theta = (angle + sector) % (2 * sector) - sector
        return circumradius * math.cos(sector) / math.cos(theta)

    # The hand points to roughly 4 o'clock: a clock stopped, not a clock running.
    hand_angle = math.radians(-52)
    hand_dx, hand_dy = math.cos(hand_angle), math.sin(hand_angle)

    rows = []
    for y in range(n):
        row = bytearray()
        dy = y - centre
        for x in range(n):
            dx = x - centre
            distance = math.hypot(dx, dy)
            angle = math.atan2(dy, dx)

            colour = background
            if octagon_radius(angle, inner) <= distance <= octagon_radius(angle, outer):
                colour = orange
            else:
                # Clock hand: distance from the point to the segment centre→tip.
                projection = dx * hand_dx + dy * hand_dy
                if 0 <= projection <= hand_length:
                    perpendicular = abs(dx * -hand_dy + dy * hand_dx)
                    if perpendicular <= hand_width / 2:
                        colour = graphite
                if distance <= hub:
                    colour = graphite

            row += bytes(
                (int(colour[0] * 255), int(colour[1] * 255), int(colour[2] * 255), 255)
            )
        rows.append(row)

    # Box-downsample the supersampled buffer.
    out = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            r = g = b = 0
            for sy in range(ss):
                source = rows[y * ss + sy]
                for sx in range(ss):
                    index = ((x * ss) + sx) * 4
                    r += source[index]
                    g += source[index + 1]
                    b += source[index + 2]
            count = ss * ss
            row += bytes((r // count, g // count, b // count, 255))
        out.append(row)
    return out, size, size


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
    pixels, width, height = draw_icon(1024)
    write_png(icon_folder / "AppIcon-1024.png", pixels, width, height)
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
    print(f"wrote: {ASSETS.relative_to(ROOT)} ({len(COLOURS)} colour sets, 1 app icon)")


if __name__ == "__main__":
    main()
