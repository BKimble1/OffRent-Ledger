# Website

**Generated. Do not edit these HTML files by hand** — run `python3 scripts/generate_website.py`.

`privacy.html` and `terms.html` are rendered from the very same Markdown the app bundles
(`OffRentLedger/Resources/Legal/`), so the text a user reads in the app and the text a reviewer
reads on the web cannot drift apart.

## Not deployed

Nothing here is live. `AppConfiguration.legalURLsAreLive` is `false`, and
`scripts/verify_repository.py` fails the build if it is flipped to `true`. The app renders its
bundled copy and links to no URL.

To publish, serve this folder at `https://offrent.idlery.com/` (GitHub Pages from `/Website`, or
any static host), load every URL in a browser, then flip the flag. See `RELEASE_CHECKLIST.md` §4.
