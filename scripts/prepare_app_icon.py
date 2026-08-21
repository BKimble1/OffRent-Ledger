#!/usr/bin/env python3
"""Rebuilds the App Store app icon from the master artwork.

The master is `marketing/AppIcon/OffRentLedger-AppIcon-master.png`. This produces the exact file
the App Store requires and the asset catalog ships:

  * exactly 1024x1024 — Apple rejects any other size for the marketing icon;
  * **no alpha channel** — Apple rejects an app icon that has one, and it is the single most
    common icon rejection there is;
  * Lanczos resampling, because the master is not an integer multiple of 1024 and the artwork has
    thin strokes (the clock hands, the tread outline) that cheaper filters visibly chew.

Alpha is flattened onto the artwork's own corner colour rather than white, so a master that
picks up transparency later cannot produce a pale halo on a dark icon.

Run: python3 scripts/prepare_app_icon.py
Check: python3 scripts/prepare_app_icon.py --check
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MASTER = ROOT / "marketing" / "AppIcon" / "OffRentLedger-AppIcon-master.png"
TARGET = (
    ROOT / "OffRentLedger" / "Resources" / "Assets.xcassets"
    / "AppIcon.appiconset" / "AppIcon-1024.png"
)
SIZE = 1024


def build() -> bytes:
    try:
        from PIL import Image
    except ImportError:
        raise SystemExit("Pillow is required: pip install Pillow")

    import io

    image = Image.open(MASTER)
    if image.mode in ("RGBA", "LA", "P"):
        image = image.convert("RGBA")
        corner = image.convert("RGB").getpixel((0, 0))
        flattened = Image.new("RGB", image.size, corner)
        flattened.paste(image, mask=image.split()[-1])
        image = flattened
    else:
        image = image.convert("RGB")

    resized = image.resize((SIZE, SIZE), Image.LANCZOS)
    buffer = io.BytesIO()
    resized.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def main() -> int:
    if not MASTER.exists():
        raise SystemExit(f"master artwork is missing: {MASTER.relative_to(ROOT)}")

    data = build()
    if "--check" in sys.argv:
        # Compares dimensions and colour type rather than bytes: Pillow's encoder output is not
        # guaranteed stable across versions, and a byte-diff would fail for no real reason.
        import struct

        if not TARGET.exists():
            print(f"MISSING: {TARGET.relative_to(ROOT)}", file=sys.stderr)
            return 1
        existing = TARGET.read_bytes()
        width, height, _, colour_type = struct.unpack(">IIBB", existing[16:26])
        if (width, height) != (SIZE, SIZE):
            print(f"STALE: icon is {width}x{height}, expected {SIZE}x{SIZE}", file=sys.stderr)
            return 1
        if colour_type != 2:
            print("STALE: icon has an alpha channel; the App Store rejects that", file=sys.stderr)
            return 1
        print(f"ok: {TARGET.relative_to(ROOT)} is {SIZE}x{SIZE}, RGB, no alpha")
        return 0

    TARGET.write_bytes(data)
    print(f"wrote: {TARGET.relative_to(ROOT)} ({SIZE}x{SIZE}, RGB, {len(data):,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
