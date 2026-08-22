# Website

**Generated. Do not edit these files by hand** — run `python3 scripts/generate_website.py`.
`scripts/verify_repository.py` fails the build if this directory stops matching its generator.

`privacy/` and `terms/` are rendered from the very same Markdown the app bundles
(`OffRentLedger/Resources/Legal/`), so the text a user reads in the app and the text a reviewer
reads on the web cannot drift apart. That is the reason this is generated rather than written.

## Deploying

    python3 scripts/generate_website.py     # build
    python3 scripts/package_website.py      # -> dist/OffRent-Ledger-Website-Netlify.zip

Drag the ZIP onto Netlify. Its contents sit at the archive root, so `index.html` is the site root
with no publish directory to configure. There is no build command, no Node, and no dependency.

## Not live yet

`AppConfiguration.legalURLsAreLive` is `false`, and `verify_repository.py` fails the build if it
is flipped while the URLs are unconfirmed. Deploy, load every URL in a browser, then flip it.
See `RELEASE_CHECKLIST.md` §4.

## Screenshots

`SCREENSHOTS` in the generator is empty, so every phone frame renders as a labelled reserved
slot naming the file it wants. Drop real captures into `marketing/screenshots/`, list them in
`SCREENSHOTS`, and re-run. Nothing here fabricates an app screen.

## Support

support@idlery.com
