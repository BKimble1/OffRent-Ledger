#!/usr/bin/env python3
"""Packs Website/ into the Netlify drag-and-drop ZIP.

The site files sit at the ZIP root, not inside a folder: Netlify treats the archive root as the
publish directory, so one wrapping folder is the difference between a working deploy and a
directory listing.

Run: python3 scripts/package_website.py
"""

import pathlib
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SITE = ROOT / "Website"
DIST = ROOT / "dist"
ZIP_NAME = "OffRent-Ledger-Website-Netlify.zip"

# Anything matching these never goes in: editor droppings, OS metadata, and the GitHub Pages
# marker, which means nothing to Netlify.
# `README.md` documents the directory for anyone reading the repository; it is not part of
# the deployable site. `.nojekyll` is a GitHub Pages marker and means nothing to Netlify.
EXCLUDE_NAMES = {".DS_Store", "Thumbs.db", ".nojekyll", "desktop.ini", "README.md"}
EXCLUDE_SUFFIXES = {".map", ".log", ".tmp", ".bak", ".orig"}


def main() -> int:
    if not SITE.exists():
        print("Website/ does not exist — run scripts/generate_website.py first")
        return 1

    DIST.mkdir(exist_ok=True)
    target = DIST / ZIP_NAME
    if target.exists():
        target.unlink()

    members: list[pathlib.Path] = []
    for path in sorted(SITE.rglob("*")):
        if not path.is_file():
            continue
        if path.name in EXCLUDE_NAMES or path.suffix in EXCLUDE_SUFFIXES:
            continue
        if any(part.startswith(".") and part not in (".",) for part in path.relative_to(SITE).parts[:-1]):
            continue
        members.append(path)

    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in members:
            # `arcname` relative to Website/, so `index.html` lands at the archive root.
            archive.write(path, path.relative_to(SITE).as_posix())

    total = sum(path.stat().st_size for path in members)
    print(f"wrote: {target.relative_to(ROOT)}")
    print(f"       {len(members)} files, {total / 1024:.0f} KB uncompressed, "
          f"{target.stat().st_size / 1024:.0f} KB zipped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
