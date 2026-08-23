#!/usr/bin/env python3
"""Packs the App Store templates into one delivery ZIP.

Contents sit under a single clearly named folder, unlike the website archive: this one is not
drag-and-drop deployed anywhere, it is opened and worked in, and a loose spill of eighteen files
into whatever directory someone unzips it in is worse than a folder.

Run: python3 scripts/package_appstore_templates.py
"""

import pathlib
import shutil
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "marketing" / "AppStore"
DIST = ROOT / "dist"
ZIP_NAME = "OffRent-AppStore-Templates.zip"
FOLDER = "OffRent-AppStore-Templates"
FONTS = pathlib.Path("/usr/local/share/fonts/inter")


def main() -> int:
    if not SRC.exists():
        print("marketing/AppStore/ is missing — run scripts/generate_appstore_templates.py first")
        return 1

    pngs = sorted(SRC.glob("OffRent-AppStore-Template-??.png"))
    svgs = sorted(SRC.glob("OffRent-AppStore-Template-??-*.svg"))
    guide = SRC / "OffRent-AppStore-Template-Placement-Guide.md"
    sheet = SRC / "OffRent-AppStore-Contact-Sheet.png"

    if len(pngs) != 6 or len(svgs) != 6 or not guide.exists():
        print(f"incomplete: {len(pngs)} PNGs, {len(svgs)} SVGs, guide={guide.exists()}")
        return 1

    DIST.mkdir(exist_ok=True)
    target = DIST / ZIP_NAME
    if target.exists():
        target.unlink()

    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in pngs:
            archive.write(path, f"{FOLDER}/{path.name}")
        for path in svgs:
            archive.write(path, f"{FOLDER}/masters/{path.name}")
        archive.write(guide, f"{FOLDER}/{guide.name}")
        archive.write(sheet, f"{FOLDER}/preview/{sheet.name}")

        # Inter, so the masters open with the type they were designed in rather than reflowing
        # into a fallback. SIL Open Font License, and the licence travels with the fonts.
        for weight in ["Bold", "SemiBold", "Medium", "Regular"]:
            font = FONTS / f"Inter-{weight}.ttf"
            if font.exists():
                archive.write(font, f"{FOLDER}/fonts/{font.name}")
        licence = ROOT / "marketing" / "AppStore" / "fonts-LICENSE.txt"
        if licence.exists():
            archive.write(licence, f"{FOLDER}/fonts/LICENSE.txt")

    with zipfile.ZipFile(target) as check:
        entries = check.namelist()
    print(f"wrote: {target.relative_to(ROOT)}")
    print(f"       {len(entries)} entries, {target.stat().st_size / 1024:.0f} KB")
    for entry in entries:
        print(f"         {entry}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
