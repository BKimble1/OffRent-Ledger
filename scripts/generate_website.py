#!/usr/bin/env python3
"""Generates the OffRent Ledger production website into `Website/`.

Two rules shape this file.

**The legal pages are rendered from the Markdown the app bundles.** The app renders
`OffRentLedger/Resources/Legal/*.md`; so does the website. A privacy policy that says one thing
in the app and another on the web is an App Review problem and a broken promise, and it is
exactly the drift that happens when two copies exist. `verify_repository.py` fails the build if
the generated output stops matching.

**Nothing here is written by hand.** Editing `Website/` directly is how the two fall out of step,
so the check also fails if the output does not match what this script produces.

Nothing here deploys anything. The output is a static site for Netlify or any other host, with no
build step, no framework, no runtime and no third-party request of any kind.

Run:   python3 scripts/generate_website.py
Check: python3 scripts/generate_website.py --check
"""

import html
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LEGAL = ROOT / "OffRentLedger" / "Resources" / "Legal"
ICON = ROOT / "marketing" / "AppIcon" / "OffRentLedger-AppIcon-master.png"
OUT = ROOT / "Website"

# --- the single place every fact about the product lives ---------------------------------------

APP_NAME = "OffRent Ledger"
COMPANY = "Idlery Services LLC"
SUPPORT_EMAIL = "support@idlery.com"
SITE_URL = "https://offrent.idlery.com"

# The App Store listing.
#
# `None` until the app is actually live. While it is None the site shows a "coming soon"
# treatment — never an Apple badge, and never a link to a listing that would 404. An App Store
# Connect record exists (numeric id 6804070266) but a record is not a listing: nothing has been
# submitted to Apple, so nothing is downloadable. Set this to the real product URL on the day the
# listing goes live and re-run this script; that is the only edit required.
APP_STORE_URL = None

# Prices as documented in PROJECT_SOURCE_OF_TRUTH.md and RELEASE_CHECKLIST.md §5. They are not
# read from the app: the app deliberately never hardcodes a price, so that what a user sees always
# comes from `Product.displayPrice` and can never be stale next to a real charge. The website
# cannot do that, so these must be confirmed against App Store Connect before launch.
PRICE_MONTHLY = "$14.99"
PRICE_ANNUAL = "$119.99"

# Screenshots.
#
# Empty on purpose. The app has never been launched — not on a device, not on a simulator — so no
# screenshot of it exists, and inventing one would put a picture of software nobody has run in
# front of people deciding whether to trust it. Every showcase slot renders as a labelled reserved
# frame until real files land in `marketing/screenshots/`. Add them there, list them here, re-run.
SCREENSHOTS: list[dict[str, str]] = []

# What each reserved slot is waiting for. Filenames are the contract: drop these into
# `marketing/screenshots/` and add them to SCREENSHOTS above.
RESERVED_SHOTS = [
    {
        "file": "today.png",
        "label": "Today",
        "caption": "Estimated rent running across every open rental, and what needs attention.",
    },
    {
        "file": "rentals.png",
        "label": "Rentals",
        "caption": "Every rental with its status, searchable by machine, vendor or jobsite.",
    },
    {
        "file": "rental-detail.png",
        "label": "Rental detail",
        "caption": "Terms, running estimate, next rate change and the full timeline.",
    },
    {
        "file": "scan-review.png",
        "label": "Scan review",
        "caption": "What the scan read, with every value waiting for you to confirm it.",
    },
    {
        "file": "confirmation.png",
        "label": "Vendor confirmation recorded",
        "caption": "Confirmation number, who you spoke to, and when.",
    },
    {
        "file": "awaiting-pickup.png",
        "label": "Awaiting pickup",
        "caption": "Equipment confirmed off rent but still on the ground.",
    },
    {
        "file": "invoice-review.png",
        "label": "Invoice review",
        "caption": "The final invoice beside what the terms you entered would predict.",
    },
]

# Which of the above carries the hero. Kept separate so the hero can be filled first.
HERO_SHOT = "today.png"


# --- Markdown ----------------------------------------------------------------------------------

def markdown_to_html(source: str) -> str:
    """A deliberately small Markdown subset: headings, bullets, bold, code, links, paragraphs.

    The legal documents are written to this subset on purpose. Pulling in a Markdown library to
    render two files would add a dependency to a repository whose whole privacy story is that it
    has none.

    Wrapped lines are joined into one paragraph. The previous version emitted a `<p>` per source
    line, so a paragraph hard-wrapped at 100 columns rendered as five separate paragraphs.
    """
    def inline(text: str) -> str:
        escaped = html.escape(text)
        escaped = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped)
        escaped = re.sub(r"`(.+?)`", r"<code>\1</code>", escaped)
        escaped = re.sub(
            r"(?<![\w.])([\w.+-]+@[\w-]+\.[\w.]+)",
            r'<a href="mailto:\1">\1</a>',
            escaped,
        )
        return escaped

    out: list[str] = []
    paragraph: list[str] = []
    item: list[str] = []
    in_list = False

    def flush_paragraph() -> None:
        if paragraph:
            out.append(f"<p>{inline(' '.join(paragraph))}</p>")
            paragraph.clear()

    def flush_item() -> None:
        if item:
            out.append(f"<li>{inline(' '.join(item))}</li>")
            item.clear()

    def close_list() -> None:
        nonlocal in_list
        flush_item()
        if in_list:
            out.append("</ul>")
            in_list = False

    for raw in source.splitlines():
        line = raw.rstrip()
        stripped = line.strip()

        if not stripped:
            flush_paragraph()
            close_list()
            continue

        heading = re.match(r"^(#{1,3}) +(.*)$", stripped)
        if heading:
            flush_paragraph()
            close_list()
            level = len(heading.group(1))
            out.append(f"<h{level}>{inline(heading.group(2))}</h{level}>")
            continue

        if stripped.startswith("- "):
            flush_paragraph()
            flush_item()
            if not in_list:
                out.append("<ul>")
                in_list = True
            item.append(stripped[2:])
            continue

        if in_list and line.startswith("  "):
            # A wrapped continuation of the current bullet.
            item.append(stripped)
            continue

        if stripped.startswith("---"):
            flush_paragraph()
            close_list()
            out.append("<hr>")
            continue

        close_list()
        paragraph.append(stripped)

    flush_paragraph()
    close_list()
    return "\n".join(out)


# --- Stylesheet ---------------------------------------------------------------------------------
#
# One committed look rather than a light/dark pair. A marketing site controls its own contrast,
# and the palette here is taken straight from the app icon — graphite, construction orange, warm
# ivory — so following the reader's OS theme would mean two designs and two contrast budgets to
# keep honest. Every surface sets its own background and foreground explicitly.
#
# Contrast, measured rather than eyeballed:
#   #FF8A1F on #171A1F ....... 7.2:1   accent text and rules on graphite
#   #171A1F on #FF8A1F ....... 7.2:1   the primary button
#   #A34A08 on #FFFFFF ....... 6.0:1   link text on light  (plain #FF8A1F is 2.4:1 and is never
#   #A34A08 on #F6F1E8 ....... 5.4:1   used for small text on a light surface)
#   #4A515C on #FFFFFF ....... 8.1:1   secondary text on light
#   #A8B0BC on #171A1F ....... 7.5:1   secondary text on graphite

CSS = """
:root {
  --graphite: #171A1F;
  --graphite-2: #252A31;
  --graphite-3: #323945;
  --orange: #FF8A1F;
  --orange-ink: #A34A08;
  --ivory: #F6F1E8;
  --paper: #FFFFFF;
  --sand: #FAF7F2;
  --ink: #171A1F;
  --ink-muted: #4A515C;
  --ivory-muted: #A8B0BC;
  --rule-light: #E7E1D6;
  --rule-dark: #333B47;

  --measure: 68ch;
  --page: 1120px;
  --radius: 14px;
  --radius-lg: 22px;

  --step-0: clamp(1rem, 0.97rem + 0.15vw, 1.0625rem);
  --step-1: clamp(1.125rem, 1.06rem + 0.32vw, 1.3125rem);
  --step-2: clamp(1.375rem, 1.24rem + 0.66vw, 1.75rem);
  --step-3: clamp(1.75rem, 1.5rem + 1.2vw, 2.5rem);
  --step-4: clamp(2.25rem, 1.72rem + 2.6vw, 4rem);

  --font: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto,
          "Helvetica Neue", Arial, sans-serif;
}

*, *::before, *::after { box-sizing: border-box; }

html { -webkit-text-size-adjust: 100%; scroll-behavior: smooth; }

body {
  margin: 0;
  background: var(--paper);
  color: var(--ink);
  font-family: var(--font);
  font-size: var(--step-0);
  line-height: 1.65;
  -webkit-font-smoothing: antialiased;
  overflow-x: hidden;
}

h1, h2, h3, h4 { line-height: 1.15; letter-spacing: -0.021em; margin: 0 0 0.5em; text-wrap: balance; }
h1 { font-size: var(--step-4); font-weight: 700; }
h2 { font-size: var(--step-3); font-weight: 700; }
h3 { font-size: var(--step-2); font-weight: 650; }
h4 { font-size: var(--step-1); font-weight: 650; }
p  { margin: 0 0 1.1em; }
p:last-child, ul:last-child { margin-bottom: 0; }

a { color: var(--orange-ink); text-underline-offset: 0.18em; }
a:hover { text-decoration-thickness: 2px; }

img, svg { max-width: 100%; height: auto; display: block; }

:where(a, button, summary, [tabindex]):focus-visible {
  outline: 3px solid var(--orange);
  outline-offset: 3px;
  border-radius: 6px;
}

.skip {
  position: absolute; left: -9999px; top: 0; z-index: 100;
  background: var(--orange); color: var(--graphite);
  padding: 0.7rem 1.1rem; font-weight: 650; border-radius: 0 0 10px 0;
}
.skip:focus { left: 0; }

.shell { width: 100%; max-width: var(--page); margin-inline: auto; padding-inline: clamp(1.1rem, 4vw, 2rem); }

section { padding-block: clamp(3.5rem, 8vw, 6.5rem); }
.band-dark  { background: var(--graphite); color: var(--ivory); }
.band-dark h1, .band-dark h2, .band-dark h3,
.hero h1, .hero h2, .hero h3,
.notfound h1, .notfound h2, .notfound h3 { color: var(--ivory); }
.band-sand  { background: var(--sand); }
.band-ivory { background: var(--ivory); }

.eyebrow {
  display: inline-block; font-size: 0.78rem; font-weight: 700;
  letter-spacing: 0.1em; text-transform: uppercase; margin-bottom: 1rem;
  color: var(--orange-ink);
}
.band-dark .eyebrow, .hero .eyebrow, .notfound .eyebrow { color: var(--orange); }

.lede { font-size: var(--step-1); color: var(--ink-muted); max-width: 58ch; }
.band-dark .lede, .hero .lede, .notfound .lede { color: var(--ivory-muted); }

/* --- nav ------------------------------------------------------------------------------------ */

.nav {
  position: sticky; top: 0; z-index: 50;
  background: rgba(23, 26, 31, 0.92);
  backdrop-filter: saturate(160%) blur(12px);
  -webkit-backdrop-filter: saturate(160%) blur(12px);
  border-bottom: 1px solid var(--rule-dark);
}
.nav__inner { display: flex; align-items: center; gap: 1rem; min-height: 62px; }
.brand { display: inline-flex; align-items: center; gap: 0.6rem; text-decoration: none; color: var(--ivory); font-weight: 680; letter-spacing: -0.015em; }
.brand img { width: 30px; height: 30px; border-radius: 7px; flex: none; }
.brand span { white-space: nowrap; }
.nav__cta { display: none; }
@media (min-width: 720px) { .nav__cta { display: block; } }
.nav__links { display: none; margin-left: auto; gap: 1.6rem; align-items: center; }
.nav__links a { color: var(--ivory-muted); text-decoration: none; font-size: 0.95rem; font-weight: 500; }
.nav__links a:hover, .nav__links a[aria-current="page"] { color: var(--ivory); }
.nav__cta { margin-left: auto; }
.nav__links ~ .nav__cta { margin-left: 1.6rem; }
@media (min-width: 860px) { .nav__links { display: flex; } }

/* --- buttons -------------------------------------------------------------------------------- */

.btn {
  display: inline-flex; align-items: center; justify-content: center; gap: 0.5rem;
  min-height: 48px; padding: 0.75rem 1.35rem;
  border-radius: 999px; border: 1.5px solid transparent;
  font-weight: 650; font-size: 1rem; text-decoration: none;
  transition: transform 120ms ease, background-color 120ms ease, border-color 120ms ease;
}
.btn--primary { background: var(--orange); color: var(--graphite); }
.btn--primary:hover { background: #FFA04D; transform: translateY(-1px); }
.btn--ghost { border-color: var(--rule-dark); color: var(--ivory); }
.btn--ghost:hover { border-color: var(--orange); transform: translateY(-1px); }
.band-sand .btn--ghost, .band-ivory .btn--ghost { border-color: var(--rule-light); color: var(--ink); }
.btn--sm { min-height: 40px; padding: 0.45rem 1rem; font-size: 0.9rem; }

/* The coming-soon control. Deliberately not an Apple badge and deliberately not a link: there is
   nothing to link to, and a dead download button is worse than an honest label. */
.soon {
  display: inline-flex; align-items: center; gap: 0.6rem;
  min-height: 48px; padding: 0.7rem 1.25rem;
  border: 1.5px dashed var(--orange); border-radius: 999px;
  color: var(--ivory); font-weight: 620; font-size: 0.98rem;
}
.soon__dot { width: 8px; height: 8px; border-radius: 50%; background: var(--orange); flex: none; }
.soon--light { color: var(--ink); border-color: var(--orange-ink); }
.soon--sm { min-height: 38px; padding: 0.35rem 0.9rem; font-size: 0.86rem; }

.actions { display: flex; flex-wrap: wrap; gap: 0.85rem; align-items: center; margin-top: 2rem; }

/* --- hero ----------------------------------------------------------------------------------- */

.hero { background: var(--graphite); color: var(--ivory); position: relative; overflow: hidden; padding-block: clamp(3rem, 8vw, 5.5rem); }
.hero::after {
  content: ""; position: absolute; inset: 0; pointer-events: none;
  background: radial-gradient(120% 90% at 78% 8%, rgba(255, 138, 31, 0.16), transparent 58%);
}
.hero__grid { position: relative; z-index: 1; display: grid; gap: clamp(2.5rem, 6vw, 4rem); align-items: center; }
@media (min-width: 940px) { .hero__grid { grid-template-columns: 1.05fr 0.95fr; } }
.hero h1 { color: var(--ivory); font-size: clamp(2.1rem, 1.55rem + 2.3vw, 3.5rem); }
.hero h1 .accent { color: var(--orange); }
.hero__sub { font-size: var(--step-1); color: var(--ivory-muted); max-width: 46ch; }
.hero__note { margin-top: 1.1rem; font-size: 0.88rem; color: var(--ivory-muted); }

/* --- phone frames --------------------------------------------------------------------------- */

.phone {
  position: relative; width: 100%; max-width: 290px; margin-inline: auto;
  aspect-ratio: 9 / 19.5;
  border-radius: 40px; padding: 9px;
  background: linear-gradient(160deg, #3A424F, #1B1F26);
  box-shadow: 0 34px 70px -28px rgba(0, 0, 0, 0.75), 0 3px 10px rgba(0, 0, 0, 0.4);
}
.phone__screen {
  width: 100%; height: 100%; border-radius: 32px; overflow: hidden;
  background: var(--graphite-2); position: relative;
  display: flex; align-items: center; justify-content: center;
}
.phone__screen img { width: 100%; height: 100%; object-fit: cover; object-position: top center; }
.phone::before {
  content: ""; position: absolute; top: 9px; left: 50%; transform: translateX(-50%);
  width: 84px; height: 24px; border-radius: 0 0 14px 14px; background: #12151A; z-index: 2;
}

/* A reserved slot. It says what belongs here rather than pretending to be it. */
.reserved {
  width: 100%; height: 100%; padding: 1.5rem 1.15rem;
  display: flex; flex-direction: column; align-items: center; justify-content: center;
  gap: 0.7rem; text-align: center;
  background:
    repeating-linear-gradient(135deg, rgba(255,138,31,0.05) 0 12px, transparent 12px 24px),
    var(--graphite-2);
  color: var(--ivory-muted);
}
.reserved__tag {
  font-size: 0.66rem; font-weight: 700; letter-spacing: 0.11em; text-transform: uppercase;
  color: var(--orange); border: 1px solid var(--orange); border-radius: 999px; padding: 0.2rem 0.6rem;
}
.reserved__name { font-size: 1rem; font-weight: 650; color: var(--ivory); line-height: 1.3; }
.reserved__file { font-size: 0.72rem; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; color: var(--ivory-muted); word-break: break-all; }

/* --- grids ---------------------------------------------------------------------------------- */

.grid { display: grid; gap: 1.15rem; }
.grid--2 { grid-template-columns: 1fr; }
.grid--3 { grid-template-columns: 1fr; }
@media (min-width: 620px) { .grid--2, .grid--3 { grid-template-columns: repeat(2, 1fr); } }
@media (min-width: 980px) { .grid--3 { grid-template-columns: repeat(3, 1fr); } }

.card {
  background: var(--paper); border: 1px solid var(--rule-light);
  border-radius: var(--radius); padding: 1.5rem 1.4rem;
}
.band-dark .card, .hero .card { background: var(--graphite-2); border-color: var(--rule-dark); }
.card h3 { font-size: var(--step-1); margin-bottom: 0.4rem; }
.card p { color: var(--ink-muted); margin: 0; font-size: 0.97rem; }
.band-dark .card p, .hero .card p { color: var(--ivory-muted); }
.card__icon { color: var(--orange-ink); margin-bottom: 0.9rem; }
.band-dark .card__icon, .hero .card__icon { color: var(--orange); }
.card__icon svg { width: 30px; height: 30px; }

/* --- steps ---------------------------------------------------------------------------------- */

.steps { list-style: none; margin: 2.5rem 0 0; padding: 0; display: grid; gap: 1.15rem; counter-reset: step; }
@media (min-width: 700px) { .steps { grid-template-columns: repeat(2, 1fr); } }
@media (min-width: 1000px) { .steps { grid-template-columns: repeat(3, 1fr); } }
.steps li {
  counter-increment: step; position: relative;
  padding: 1.4rem 1.4rem 1.4rem 3.9rem;
  background: var(--graphite-2); border: 1px solid var(--rule-dark); border-radius: var(--radius);
}
.steps li::before {
  content: counter(step); position: absolute; left: 1.3rem; top: 1.35rem;
  width: 30px; height: 30px; border-radius: 50%;
  display: grid; place-items: center;
  background: var(--orange); color: var(--graphite);
  font-weight: 700; font-size: 0.9rem; font-variant-numeric: tabular-nums;
}
.steps h3 { font-size: 1.06rem; margin-bottom: 0.3rem; color: var(--ivory); }
.steps p { margin: 0; color: var(--ivory-muted); font-size: 0.95rem; }

/* --- showcase ------------------------------------------------------------------------------- */

.showcase { display: grid; gap: 2rem; margin-top: 2.75rem; }
@media (min-width: 640px) { .showcase { grid-template-columns: repeat(2, 1fr); } }
@media (min-width: 1000px) { .showcase { grid-template-columns: repeat(3, 1fr); } }
.showcase figure { margin: 0; }
.showcase figcaption { margin-top: 1rem; text-align: center; }
.showcase .shot__name { font-weight: 650; display: block; }
.showcase .shot__desc { color: var(--ink-muted); font-size: 0.93rem; }
.band-dark .showcase .shot__desc, .hero .showcase .shot__desc { color: var(--ivory-muted); }

/* --- truth panel ---------------------------------------------------------------------------- */

.truth {
  border: 1px solid var(--rule-dark); border-left: 4px solid var(--orange);
  border-radius: var(--radius); padding: 1.4rem 1.5rem; background: var(--graphite-2);
  max-width: var(--measure);
}
.truth p { margin: 0; color: var(--ivory-muted); }
.truth strong { color: var(--ivory); }
.truth--light { background: var(--paper); border-color: var(--rule-light); border-left-color: var(--orange-ink); }
.truth--light p { color: var(--ink-muted); }
.truth--light strong { color: var(--ink); }

.checks { list-style: none; margin: 2rem 0 0; padding: 0; display: grid; gap: 0.8rem; }
@media (min-width: 700px) { .checks { grid-template-columns: repeat(2, 1fr); } }
.checks li { position: relative; padding-left: 1.9rem; color: var(--ivory-muted); }
.checks li::before {
  content: ""; position: absolute; left: 0; top: 0.55em;
  width: 11px; height: 6px; border-left: 2.5px solid var(--orange); border-bottom: 2.5px solid var(--orange);
  transform: rotate(-45deg);
}

/* --- pricing -------------------------------------------------------------------------------- */

.tiers { display: grid; gap: 1.15rem; margin-top: 2.5rem; align-items: start; }
@media (min-width: 760px) { .tiers { grid-template-columns: repeat(2, 1fr); } }
.tier { background: var(--paper); border: 1px solid var(--rule-light); border-radius: var(--radius-lg); padding: 1.8rem 1.6rem; }
.tier--pro { border-color: var(--orange); box-shadow: 0 18px 44px -30px rgba(163, 74, 8, 0.5); }
.tier__name { font-size: 0.8rem; font-weight: 700; letter-spacing: 0.1em; text-transform: uppercase; color: var(--orange-ink); }
.tier__price { font-size: var(--step-3); font-weight: 700; margin: 0.5rem 0 0.1rem; letter-spacing: -0.03em; }
.tier__price span { font-size: 1rem; font-weight: 500; color: var(--ink-muted); letter-spacing: 0; }
.tier ul { list-style: none; margin: 1.2rem 0 0; padding: 0; display: grid; gap: 0.6rem; }
.tier li { position: relative; padding-left: 1.7rem; color: var(--ink-muted); font-size: 0.97rem; }
.tier li::before {
  content: ""; position: absolute; left: 0; top: 0.5em;
  width: 10px; height: 6px; border-left: 2.5px solid var(--orange-ink); border-bottom: 2.5px solid var(--orange-ink);
  transform: rotate(-45deg);
}

/* --- documents ------------------------------------------------------------------------------ */

.doc { padding-block: clamp(2.5rem, 6vw, 4rem); }
.doc__inner { max-width: var(--measure); }
.doc h1 { font-size: var(--step-3); }
.doc h2 { font-size: var(--step-2); margin-top: 2.4rem; padding-top: 1.6rem; border-top: 1px solid var(--rule-light); }
.doc h2:first-of-type { border-top: 0; padding-top: 0; }
.doc h3 { font-size: var(--step-1); margin-top: 1.8rem; }
.doc ul { padding-left: 1.2rem; margin: 0 0 1.1em; }
.doc li { margin-bottom: 0.4rem; }
.doc code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.9em; background: var(--ivory); padding: 0.1em 0.35em; border-radius: 5px; }
.doc hr { border: 0; border-top: 1px solid var(--rule-light); margin: 2rem 0; }
.doc__meta { color: var(--ink-muted); font-size: 0.92rem; margin-bottom: 2rem; }

.faq { margin-top: 2rem; }
.faq details {
  border: 1px solid var(--rule-light); border-radius: var(--radius);
  background: var(--paper); margin-bottom: 0.75rem;
}
.faq summary {
  cursor: pointer; list-style: none; padding: 1.05rem 3rem 1.05rem 1.25rem;
  font-weight: 620; position: relative; border-radius: var(--radius);
}
.faq summary::-webkit-details-marker { display: none; }
.faq summary::after {
  content: ""; position: absolute; right: 1.3rem; top: 1.45rem;
  width: 9px; height: 9px; border-right: 2px solid var(--orange-ink); border-bottom: 2px solid var(--orange-ink);
  transform: rotate(45deg); transition: transform 160ms ease;
}
.faq details[open] summary::after { transform: rotate(-135deg); top: 1.7rem; }
.faq .faq__body { padding: 0 1.25rem 1.25rem; color: var(--ink-muted); }
.faq .faq__body p:last-child { margin-bottom: 0; }

/* --- footer --------------------------------------------------------------------------------- */

.footer { background: var(--graphite); color: var(--ivory-muted); padding-block: 3rem 2.5rem; }
.footer__top { display: flex; flex-wrap: wrap; gap: 2rem; justify-content: space-between; align-items: start; }
.footer__brand { display: inline-flex; align-items: center; gap: 0.65rem; color: var(--ivory); font-weight: 650; text-decoration: none; }
.footer__brand img { width: 34px; height: 34px; border-radius: 8px; }
.footer nav { display: flex; flex-wrap: wrap; gap: 1.4rem; }
.footer nav a { color: var(--ivory-muted); text-decoration: none; }
.footer nav a:hover { color: var(--ivory); text-decoration: underline; }
.footer__legal { margin-top: 2.2rem; padding-top: 1.6rem; border-top: 1px solid var(--rule-dark); font-size: 0.87rem; display: flex; flex-wrap: wrap; gap: 0.4rem 1.4rem; }
.footer__legal p { margin: 0; }

/* --- 404 ------------------------------------------------------------------------------------ */

.notfound { min-height: 62vh; display: grid; place-items: center; text-align: center; background: var(--graphite); color: var(--ivory); }
.notfound__code { font-size: clamp(4rem, 16vw, 8rem); font-weight: 700; color: var(--orange); line-height: 1; letter-spacing: -0.04em; }

/* --- motion --------------------------------------------------------------------------------- */

@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto; }
  *, *::before, *::after {
    animation-duration: 0.001ms !important; animation-iteration-count: 1 !important;
    transition-duration: 0.001ms !important; scroll-behavior: auto !important;
  }
}

@media print {
  .nav, .footer, .skip { display: none; }
  body { background: #fff; color: #000; }
}
"""


# --- inline icons --------------------------------------------------------------------------------
#
# Inline SVG rather than an icon font or a sprite request: they inherit `currentColor`, they cost
# no extra round trip, and there is no third-party host involved. `aria-hidden` on all of them —
# each sits beside a real heading that already says what it is.

def _svg(body: str) -> str:
    return (
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" '
        'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">'
        f"{body}</svg>"
    )


ICON_CLOCK = _svg('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.2 2"/>')
ICON_TREND = _svg('<path d="M3 17.5 9.5 11l4 4L21 7.5"/><path d="M15.5 7.5H21V13"/>')
ICON_SEAL = _svg('<path d="M12 3.2 19.2 6v5.4c0 4.3-2.9 7.6-7.2 9.4-4.3-1.8-7.2-5.1-7.2-9.4V6Z"/>'
                 '<path d="m8.9 11.9 2.2 2.2 4-4.4"/>')
ICON_TRUCK = _svg('<path d="M2.8 15.6V7.2a.9.9 0 0 1 .9-.9h9.4v9.3"/>'
                  '<path d="M13.1 9.6h3.6l3.5 3.4v2.6"/>'
                  '<circle cx="7.2" cy="17.4" r="1.9"/><circle cx="16.8" cy="17.4" r="1.9"/>'
                  '<path d="M9.1 17.4h5.8"/>')
ICON_GAUGE = _svg('<path d="M4 17a8 8 0 1 1 16 0"/><path d="m12 17 3.6-4.6"/><circle cx="12" cy="17" r="1.2"/>')
ICON_INVOICE = _svg('<path d="M6.5 3.2h11v17.6l-2.7-1.7-2.8 1.7-2.8-1.7-2.7 1.7Z"/>'
                    '<path d="M9.4 8.1h5.2M9.4 11.7h5.2M9.4 15.3h3"/>')
ICON_LOCK = _svg('<rect x="4.6" y="10.4" width="14.8" height="9.4" rx="2"/>'
                 '<path d="M8.4 10.4V7.8a3.6 3.6 0 0 1 7.2 0v2.6"/>')
ICON_EXPORT = _svg('<path d="M12 15.4V4.1"/><path d="m8.2 7.6 3.8-3.5 3.8 3.5"/>'
                   '<path d="M4.8 14.2v4.1a1.6 1.6 0 0 0 1.6 1.6h11.2a1.6 1.6 0 0 0 1.6-1.6v-4.1"/>')


# --- page shell ----------------------------------------------------------------------------------

NAV_ITEMS = [
    ("Features", "/#features"),
    ("How it works", "/#how"),
    ("Privacy", "/privacy/"),
    ("Support", "/support/"),
]


def store_cta(size: str = "", light: bool = False) -> str:
    """The App Store control.

    Two shapes, and which one appears is decided by `APP_STORE_URL` rather than by the caller, so
    the site cannot end up with a live badge on one page and a coming-soon label on another. While
    the listing does not exist this is deliberately not a link and deliberately not an Apple badge:
    a button that goes nowhere is worse than an honest label, and a fake badge is a trademark
    problem on top of that.
    """
    small = " btn--sm" if size == "sm" else ""
    if APP_STORE_URL:
        return (
            f'<a class="btn btn--primary{small}" href="{APP_STORE_URL}">'
            f"Download on the App Store</a>"
        )
    soon_small = " soon--sm" if size == "sm" else ""
    soon_light = " soon--light" if light else ""
    return (
        f'<span class="soon{soon_small}{soon_light}">'
        f'<span class="soon__dot" aria-hidden="true"></span>'
        f"Coming soon to the App Store</span>"
    )


def nav(current: str) -> str:
    links = []
    for label, href in NAV_ITEMS:
        aria = ' aria-current="page"' if href == current else ""
        links.append(f'<a href="{href}"{aria}>{label}</a>')
    return f"""<header class="nav">
  <div class="shell nav__inner">
    <a class="brand" href="/">
      <img src="/assets/img/icon-64.png" width="30" height="30" alt="">
      <span>{APP_NAME}</span>
    </a>
    <nav class="nav__links" aria-label="Primary">{"".join(links)}</nav>
    <div class="nav__cta">{store_cta(size="sm")}</div>
  </div>
</header>"""


def footer() -> str:
    year = 2026
    return f"""<footer class="footer">
  <div class="shell">
    <div class="footer__top">
      <a class="footer__brand" href="/">
        <img src="/assets/img/icon-64.png" width="34" height="34" alt="">
        <span>{APP_NAME}</span>
      </a>
      <nav aria-label="Footer">
        <a href="/">Overview</a>
        <a href="/privacy/">Privacy Policy</a>
        <a href="/terms/">Terms of Use</a>
        <a href="/support/">Support</a>
        <a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a>
      </nav>
    </div>
    <div class="footer__legal">
      <p>&copy; {year} {COMPANY}. All rights reserved.</p>
      <p>offrent.idlery.com</p>
      <p>{APP_NAME} does not contact rental companies and does not end rentals.</p>
    </div>
  </div>
</footer>"""


def page(*, title: str, description: str, canonical: str, body: str, current: str = "") -> str:
    """One shell for every route, so navigation, metadata and footer cannot drift between pages."""
    full_title = title if title == APP_NAME else f"{title} · {APP_NAME}"
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(full_title)}</title>
<meta name="description" content="{html.escape(description)}">
<link rel="canonical" href="{SITE_URL}{canonical}">
<meta name="theme-color" content="#171A1F">
<meta name="color-scheme" content="light">

<meta property="og:type" content="website">
<meta property="og:site_name" content="{APP_NAME}">
<meta property="og:title" content="{html.escape(full_title)}">
<meta property="og:description" content="{html.escape(description)}">
<meta property="og:url" content="{SITE_URL}{canonical}">
<meta property="og:image" content="{SITE_URL}/assets/img/social-card.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="{APP_NAME} — stop the rental clock with proof.">
<meta name="twitter:card" content="summary_large_image">

<link rel="icon" href="/assets/img/favicon.ico" sizes="any">
<link rel="icon" href="/assets/img/icon-192.png" type="image/png" sizes="192x192">
<link rel="apple-touch-icon" href="/assets/img/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
<link rel="stylesheet" href="/assets/css/site.css">
</head>
<body>
<a class="skip" href="#main">Skip to content</a>
{nav(current)}
<main id="main">
{body}
</main>
{footer()}
</body>
</html>
"""


def phone(*, shot: str, alt: str = "", label: str = "", eager: bool = False) -> str:
    """An iPhone frame around either a real screenshot or a labelled reserved slot.

    The reserved slot is not a grey box. It names the screen that belongs there and the exact
    filename that will fill it, so an empty frame is a work item rather than a design decision.
    """
    available = {s["file"]: s for s in SCREENSHOTS}
    if shot in available:
        entry = available[shot]
        loading = "eager" if eager else "lazy"
        inner = (
            f'<img src="/assets/img/screens/{shot}" alt="{html.escape(alt or entry["alt"])}" '
            f'width="{entry["width"]}" height="{entry["height"]}" loading="{loading}" decoding="async">'
        )
    else:
        inner = f"""<div class="reserved">
        <span class="reserved__tag">Screenshot pending</span>
        <span class="reserved__name">{html.escape(label)}</span>
        <span class="reserved__file">{html.escape(shot)}</span>
      </div>"""
    return f"""<div class="phone">
    <div class="phone__screen">{inner}</div>
  </div>"""


# --- landing page ---------------------------------------------------------------------------------

BENEFITS = [
    (ICON_CLOCK, "See what is running now",
     "Estimated rent running across every open rental, from the delivery date and the rates you "
     "entered. One number on the Today screen, updated as the days pass."),
    (ICON_TREND, "See the next rate change coming",
     "Daily to weekly, weekly to four-week — the app shows when the next roll-over falls and what "
     "it is expected to add, so a decision to keep a machine is a decision, not a surprise."),
    (ICON_SEAL, "Record the off-rent confirmation",
     "Confirmation number, who you spoke to, how you reached them, and when. Written down at the "
     "moment you get it, while you are still standing in the yard."),
    (ICON_TRUCK, "Follow what is awaiting pickup",
     "Confirmed off rent is not the same as collected. Equipment stays on the Awaiting pickup list "
     "until you record that it actually left."),
    (ICON_GAUGE, "Document meter, fuel and condition",
     "Photograph the hour meter, the fuel gauge and the condition at hand-back, with the reading "
     "you noted. The state of the machine when you finished with it, kept with the rental."),
    (ICON_INVOICE, "Review the final invoice",
     "The app compares the invoice against the terms you confirmed and flags a possible mismatch "
     "— an extra rental day, a rate that is not the one you entered — for you to look at."),
]

STEPS = [
    ("Add or scan the rental",
     "Type it in, or scan the rental contract with the camera. Text recognition runs on your "
     "iPhone; every value it reads waits for you to confirm it before anything is saved."),
    ("Watch the cost and the timing",
     "Estimated rent running, the next rate change, and how long the machine has been on the "
     "ground. Based on the terms you confirmed."),
    ("Mark it done, then make the call",
     "You contact the rental company — the app opens your dialler or an email draft. It does not "
     "contact anyone for you."),
    ("Record the vendor confirmation",
     "Confirmation number, representative, method and time. Optionally a one-off location. The "
     "rental moves to Vendor confirmation recorded, and the estimate stops accruing there."),
    ("Track it until it is collected",
     "Awaiting pickup, until you record the pickup with the meter reading, the fuel level and "
     "photographs of the condition."),
    ("Check the invoice, export if you need to",
     "When the final invoice arrives, attach it and review. If you decide to question a charge, "
     "export a PDF packet with the timeline, the confirmation and the photographs."),
]

PRIVACY_POINTS = [
    "No account, no sign-up, no password",
    "No server — there is nowhere for your data to go",
    "No analytics, telemetry or crash-reporting SDK",
    "No advertising and no ad identifier",
    "Text recognition runs on your iPhone, never in a cloud",
    "Works with no signal, in a yard or a basement",
    "Location is one optional reading, only when you tap for it",
    "Export a CSV, a JSON backup or a PDF at any time — not behind the subscription",
]


def landing_page() -> str:
    benefit_cards = "\n".join(
        f"""      <article class="card">
        <div class="card__icon">{icon}</div>
        <h3>{title}</h3>
        <p>{body}</p>
      </article>"""
        for icon, title, body in BENEFITS
    )

    step_items = "\n".join(
        f"""      <li>
        <h3>{title}</h3>
        <p>{body}</p>
      </li>"""
        for title, body in STEPS
    )

    showcase = "\n".join(
        f"""      <figure>
        {phone(shot=s["file"], label=s["label"])}
        <figcaption>
          <span class="shot__name">{s["label"]}</span>
          <span class="shot__desc">{s["caption"]}</span>
        </figcaption>
      </figure>"""
        for s in RESERVED_SHOTS[:6]
    )

    privacy_checks = "\n".join(f"      <li>{point}</li>" for point in PRIVACY_POINTS)

    shots_note = ""
    if not SCREENSHOTS:
        shots_note = """
    <div class="truth truth--light" style="margin-top:2.5rem">
      <p><strong>These frames are reserved, not decorative.</strong> Real screenshots of
      %s go here. Nothing on this page is a mock-up of an interface that does not exist —
      an invented screen is not a preview, it is a picture of software nobody has run.</p>
    </div>""" % APP_NAME

    return page(
        title=APP_NAME,
        description=(
            "OffRent Ledger tracks active equipment-rental costs, records off-rent confirmations, "
            "follows equipment awaiting pickup and reviews final invoices for possible mismatches "
            "— from your iPhone."
        ),
        canonical="/",
        current="/",
        body=f"""
<section class="hero">
  <div class="shell hero__grid">
    <div>
      <span class="eyebrow">For small contractors</span>
      <h1>Stop the rental clock <span class="accent">with proof.</span></h1>
      <p class="hero__sub">Track active rental costs, document off-rent confirmations, follow
      equipment awaiting pickup, and catch questionable final charges — all from your iPhone.</p>
      <div class="actions">
        {store_cta()}
        <a class="btn btn--ghost" href="#how">See how it works</a>
      </div>
      <p class="hero__note"><strong>You</strong> call the rental company. {APP_NAME} keeps the
      record of what was said, when, and by whom — it does not contact vendors and does not end
      rentals.</p>
    </div>
    <div>{phone(shot=HERO_SHOT, label="Today", eager=True)}</div>
  </div>
</section>

<section class="band-sand">
  <div class="shell">
    <span class="eyebrow">The problem</span>
    <h2>Calling it off rent is not the end of the money.</h2>
    <p class="lede">You phone the yard on a Friday and tell them you are done with the skid steer.
    Then the machine sits on site until Wednesday. The invoice arrives three weeks later with an
    extra week on it, and nobody can remember who you spoke to, or when.</p>
    <div class="grid grid--3" style="margin-top:2.5rem">
      <article class="card">
        <h3>The call is not written down</h3>
        <p>A confirmation number on the back of a receipt is not a record. Two months later,
        neither is a memory of the call.</p>
      </article>
      <article class="card">
        <h3>Pickup is a separate event</h3>
        <p>Off rent and collected are different days. Which one the invoice bills to is worth
        knowing before you pay it.</p>
      </article>
      <article class="card">
        <h3>The invoice arrives cold</h3>
        <p>Checking a final invoice means reconstructing dates and rates from memory — which is
        why most of them are simply paid.</p>
      </article>
    </div>
  </div>
</section>

<section id="features">
  <div class="shell">
    <span class="eyebrow">What it does</span>
    <h2>Six things, done properly.</h2>
    <p class="lede">Every figure comes from the rates and dates you entered. The app does not
    interpret your contract and does not decide anything for you.</p>
    <div class="grid grid--3" style="margin-top:2.5rem">
{benefit_cards}
    </div>
  </div>
</section>

<section id="how" class="band-dark">
  <div class="shell">
    <span class="eyebrow">How it works</span>
    <h2>From delivery to the final invoice.</h2>
    <p class="lede">One workflow, six steps. You stay in control of every one of them.</p>
    <ol class="steps">
{step_items}
    </ol>
    <div class="truth" style="margin-top:2.75rem">
      <p><strong>{APP_NAME} does not contact rental companies and does not end rentals.</strong>
      It can open your dialler or start an email draft, but you make the contact. Nothing recorded
      in the app is communicated to any rental company, and nothing in it changes your rental
      agreement.</p>
    </div>
  </div>
</section>

<section>
  <div class="shell">
    <span class="eyebrow">Inside the app</span>
    <h2>The screens you will actually use.</h2>
    <div class="showcase">
{showcase}
    </div>{shots_note}
  </div>
</section>

<section class="band-dark">
  <div class="shell">
    <span class="eyebrow">Privacy and field use</span>
    <h2>It all stays on your iPhone.</h2>
    <p class="lede">Not a policy position — an architecture. There is no server, so there is
    nowhere for your rentals, documents, photographs or location to go.</p>
    <ul class="checks">
{privacy_checks}
    </ul>
    <div class="actions">
      <a class="btn btn--ghost" href="/privacy/">Read the Privacy Policy</a>
    </div>
  </div>
</section>

<section class="band-ivory">
  <div class="shell">
    <span class="eyebrow">Pricing</span>
    <h2>Free for one rental. Pro for a fleet.</h2>
    <p class="lede">Ending a subscription never removes or hides anything you have already
    recorded. You keep viewing, editing, resolving, exporting and deleting all of it.</p>
    <div class="tiers">
      <article class="tier">
        <span class="tier__name">Free</span>
        <p class="tier__price">$0</p>
        <p style="color:var(--ink-muted);margin:0">One open rental at a time.</p>
        <ul>
          <li>The complete workflow on that rental</li>
          <li>Scanning and on-device text recognition</li>
          <li>Invoice review and possible-mismatch flags</li>
          <li>CSV, JSON and PDF export</li>
        </ul>
      </article>
      <article class="tier tier--pro">
        <span class="tier__name">{APP_NAME} Pro</span>
        <p class="tier__price">{PRICE_MONTHLY} <span>/ month</span></p>
        <p style="color:var(--ink-muted);margin:0">or {PRICE_ANNUAL} a year.</p>
        <ul>
          <li>Unlimited open rentals</li>
          <li>Home-screen widget</li>
          <li>The full reminder set</li>
          <li>Everything in Free, unchanged</li>
        </ul>
      </article>
    </div>
    <p style="margin-top:1.5rem;font-size:0.9rem;color:var(--ink-muted);max-width:60ch">
      Auto-renewing subscription sold through Apple. Prices shown in the app come from the App
      Store and are current for your storefront. Manage or cancel any time in your Apple Account
      settings. See the <a href="/terms/">Terms of Use</a>.</p>
  </div>
</section>

<section class="band-dark">
  <div class="shell" style="text-align:center">
    <h2>Know what the rental cost, and be able to show it.</h2>
    <p class="lede" style="margin-inline:auto">Not a promise about what you will save. A record of
    what happened, kept while it is still fresh, and ready if you decide to question a charge.</p>
    <div class="actions" style="justify-content:center">
      {store_cta()}
      <a class="btn btn--ghost" href="/support/">Read the support guide</a>
    </div>
  </div>
</section>
""",
    )


# --- legal documents -----------------------------------------------------------------------------

def legal_page(*, source: pathlib.Path, slug: str, title: str, description: str) -> str:
    """Renders one of the app's bundled legal documents.

    The Markdown's own `# Heading` and the two identity lines under it are dropped and rebuilt as
    the page header, so the document reads as a web page rather than as a file that happens to be
    on the web. Every word of the substantive text is the app's.
    """
    raw = source.read_text()
    lines = raw.splitlines()

    # Drop the title line and the identity/effective-date block that follows it.
    body_start = 0
    for index, line in enumerate(lines):
        if line.startswith("## "):
            body_start = index
            break
    meta_lines = [ln.strip() for ln in lines[1:body_start] if ln.strip()]
    meta = " · ".join(re.sub(r"\*\*(.+?)\*\*", r"\1", ln) for ln in meta_lines)

    return page(
        title=title,
        description=description,
        canonical=f"/{slug}/",
        current=f"/{slug}/",
        body=f"""
<section class="doc">
  <div class="shell doc__inner">
    <h1>{title}</h1>
    <p class="doc__meta">{html.escape(meta)}</p>
{markdown_to_html(chr(10).join(lines[body_start:]))}
    <hr>
    <p class="doc__meta">This is the same text the app shows in Settings. Both are rendered from
    one source file, so they cannot say different things. Questions:
    <a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a>.</p>
  </div>
</section>
""",
    )


# --- support ---------------------------------------------------------------------------------------

FAQ = [
    ("Getting started",
     f"""<p>Install {APP_NAME} on an iPhone running iOS 18 or later, open it, and add your first
     rental. There is no account to create, no email to verify and no password. Nothing is sent
     anywhere, so there is nothing to sign in to.</p>
     <p>The free tier covers one open rental at a time, with the complete workflow available on
     it.</p>"""),

    ("Adding or scanning a rental",
     """<p>Tap the add button and either type the details in or tap <em>Scan the contract</em> to
     use the camera. You can also import a PDF or pick a photo you already have.</p>
     <p>Text recognition runs entirely on your iPhone, using Apple's Vision framework. Nothing is
     uploaded. Whatever it reads is shown to you on a review screen with a tick beside each value:
     only the values you tick are saved, and you can correct any of them first. A scan on its own
     never writes anything.</p>
     <p>The rates and dates you enter are what every later estimate is calculated from, so it is
     worth checking them against the contract.</p>"""),

    ("Recording an off-rent confirmation",
     f"""<p>When you have finished with a machine, mark it done. The app moves it to
     <em>Contact vendor</em> and offers you the rental company's phone number, email or link — you
     make the contact. {APP_NAME} does not contact rental companies and does not end rentals.</p>
     <p>When the yard gives you a confirmation, record it: the confirmation number, who you spoke
     to, how you reached them, and the time. You can add a one-off location reading if you want
     one. The rental then shows <em>Vendor confirmation recorded</em>, and the running estimate
     stops accruing at that moment rather than at pickup.</p>
     <p>If they would not give you a confirmation number, you can record that too — the app asks
     you to acknowledge it rather than leaving the field silently blank.</p>"""),

    ("Tracking pickup",
     """<p>Confirmed off rent is not the same as collected, so the rental stays on the
     <em>Awaiting pickup</em> list until you record the pickup.</p>
     <p>When the machine actually leaves, record the pickup with the hour or mile reading, the fuel
     level, and photographs of the condition. That is the state of the machine when it left your
     site, kept with the rental.</p>"""),

    ("Reviewing an invoice discrepancy",
     """<p>Attach the final invoice to the rental — scan it, import a PDF, or enter the lines by
     hand. The app compares it against the terms you confirmed and reports any
     <em>possible invoice mismatch</em>: an extra rental day, a rate that is not the one you
     entered, a line it has no way to derive.</p>
     <p>A possible mismatch is a prompt to look, and nothing more. The app does not determine that
     a charge is incorrect, unauthorised or unlawful, and it is not accounting or legal advice.
     Whether to accept a charge, question it or dispute it is entirely your decision.</p>
     <p>If you decide to question one, export an evidence packet (below) and take it up with the
     rental company directly.</p>"""),

    ("Exporting evidence",
     """<p>Three exports, none of them behind the subscription:</p>
     <ul>
       <li><strong>PDF packet</strong> — one rental, with its timeline, the confirmation you
       recorded, the invoice comparison and the photographs you attached.</li>
       <li><strong>CSV summary</strong> — every rental as a row, for a spreadsheet.</li>
       <li><strong>JSON backup</strong> — everything, in a format the app can import again.</li>
     </ul>
     <p>The PDF is a summary of information you entered and files you captured. Timestamps reflect
     when things were entered on your device. They are not independently witnessed and are not
     legally binding. Read anything you generate before you send it to anyone.</p>"""),

    ("Restoring purchases",
     """<p>Settings › Subscription › <em>Restore purchases</em>. This asks Apple whether the Apple
     Account signed in on this device has an active subscription, and updates the app accordingly.
     It works on a new iPhone, after a reinstall, and after a restore from backup.</p>
     <p>If nothing is restored, check that the device is signed in to the same Apple Account that
     bought the subscription.</p>"""),

    ("Managing or cancelling an Apple subscription",
     """<p>Subscriptions are sold and billed by Apple, not by us. Manage or cancel yours in
     <strong>Settings › your name › Subscriptions</strong> on your iPhone, or from the link in the
     app's Subscription screen.</p>
     <p>Cancel at least 24 hours before the end of the current period to stop the next renewal.
     Refunds are handled by Apple under Apple's policies — we cannot issue them.</p>
     <p><strong>Ending a subscription never removes or hides anything you have already
     recorded.</strong> You keep viewing, editing, resolving, exporting and deleting all of it.
     Without Pro you cannot open an additional rental beyond the free limit.</p>"""),

    ("Camera, photo and notification permissions",
     """<p><strong>Camera</strong> — asked for the first time you tap a scan or photo button. Used
     to scan contracts and invoices and to photograph condition, meters and fuel gauges.</p>
     <p><strong>Photos</strong> — the app uses the system picker, which lets you choose specific
     images without granting access to your whole library. Add-only permission is requested only
     if you ask the app to save a file back to Photos.</p>
     <p><strong>Location</strong> — asked only when you tap <em>Add current location</em> while
     recording a confirmation or a pickup. One reading, in the foreground, stored with that single
     record. No background tracking and no location history. Declining blocks nothing.</p>
     <p><strong>Notifications</strong> — asked only after you turn on a reminder. Reminders are
     scheduled locally on your iPhone; there is no server that could push one.</p>"""),

    ("Deleting your data",
     """<p>Delete an individual attachment, delete a rental (which deletes its events, photographs
     and documents), or delete everything from <strong>Settings › Data and privacy</strong>.</p>
     <p>Deleting the app from your iPhone removes all of it as well.</p>
     <p>Because there is no server, deletion on your device is deletion everywhere — which also
     means we cannot recover anything for you. Export before you delete.</p>"""),

    ("Privacy and where your data lives",
     f"""<p>Everything stays on your iPhone. There is no account, no server, no analytics, no
     advertising identifier and no crash-reporting SDK. {COMPANY} receives no data from the app.</p>
     <p>The app works with no signal at all, which is the normal condition in a yard or a
     basement.</p>
     <p>The full detail is in the <a href="/privacy/">Privacy Policy</a>.</p>"""),
]


def support_page() -> str:
    items = "\n".join(
        f"""      <details>
        <summary>{html.escape(question)}</summary>
        <div class="faq__body">{answer}</div>
      </details>"""
        for question, answer in FAQ
    )
    return page(
        title="Support",
        description=(
            f"Support for {APP_NAME}: getting started, scanning a rental, recording an off-rent "
            "confirmation, tracking pickup, reviewing an invoice, exporting evidence, "
            "subscriptions and privacy."
        ),
        canonical="/support/",
        current="/support/",
        body=f"""
<section class="doc">
  <div class="shell doc__inner">
    <h1>Support</h1>
    <p class="lede">Email is the fastest way to reach a person. There is no ticket system and no
    contact form to fill in.</p>
    <div class="actions">
      <a class="btn btn--primary" href="mailto:{SUPPORT_EMAIL}?subject={APP_NAME.replace(' ', '%20')}%20support">Email {SUPPORT_EMAIL}</a>
    </div>
    <p style="margin-top:1.5rem;color:var(--ink-muted)">Telling us your iPhone model, your iOS
    version and the app version from Settings › About makes a first reply much more useful.
    Please do not send anything confidential from a rental agreement that you would not want in an
    ordinary email.</p>
  </div>
</section>

<section class="band-sand" style="padding-top:0">
  <div class="shell doc__inner">
    <div class="faq">
      <h2 style="font-size:var(--step-2);margin-bottom:1.2rem">Common questions</h2>
{items}
    </div>
  </div>
</section>

<section>
  <div class="shell doc__inner">
    <div class="truth truth--light">
      <p><strong>{APP_NAME} does not contact rental companies and does not end rentals.</strong>
      It keeps your record of what was agreed, what you were told and when. The rental company's
      own agreement governs your rental.</p>
    </div>
  </div>
</section>
""",
    )


def not_found_page() -> str:
    return page(
        title="Page not found",
        description="That page does not exist on offrent.idlery.com.",
        canonical="/404.html",
        body=f"""
<section class="notfound">
  <div class="shell">
    <p class="notfound__code">404</p>
    <h1 style="font-size:var(--step-2)">That page is not here.</h1>
    <p class="lede" style="margin-inline:auto">The link may be old, or it may have a typo in it.</p>
    <div class="actions" style="justify-content:center">
      <a class="btn btn--primary" href="/">Go to the overview</a>
      <a class="btn btn--ghost" href="/support/">Support</a>
    </div>
  </div>
</section>
""",
    )


# --- deployment configuration ----------------------------------------------------------------------

ROBOTS = f"""User-agent: *
Allow: /

Sitemap: {SITE_URL}/sitemap.xml
"""


def sitemap() -> str:
    routes = [("/", "1.0"), ("/support/", "0.7"), ("/privacy/", "0.5"), ("/terms/", "0.5")]
    entries = "\n".join(
        f"  <url>\n    <loc>{SITE_URL}{path}</loc>\n"
        f"    <priority>{priority}</priority>\n  </url>"
        for path, priority in routes
    )
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
{entries}
</urlset>
"""


# Content-Security-Policy can be this strict because the site genuinely has no third-party
# anything: no CDN, no font host, no analytics, no embedded video. `default-src 'none'` with
# explicit allowances is the shape you can only use when it is actually true.
HEADERS = """/*
  X-Content-Type-Options: nosniff
  X-Frame-Options: DENY
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: geolocation=(), camera=(), microphone=(), payment=(), usb=(), interest-cohort=()
  Strict-Transport-Security: max-age=31536000; includeSubDomains
  Content-Security-Policy: default-src 'none'; img-src 'self'; style-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; manifest-src 'self'

/assets/*
  Cache-Control: public, max-age=31536000, immutable

/*.html
  Cache-Control: public, max-age=0, must-revalidate
"""

# Only the redirects that are genuinely needed: the extensionless legal paths the app's
# `AppConfiguration` points at (`/privacy`, `/terms`, `/support` with no trailing slash) and the
# filenames the previous version of this site published. Netlify already serves `/privacy/` from
# `privacy/index.html`, so no rule is needed for that.
REDIRECTS = """/privacy.html    /privacy/    301!
/terms.html      /terms/      301!
/support.html    /support/    301!
/index.html      /            301!
"""


def webmanifest() -> str:
    return f"""{{
  "name": "{APP_NAME}",
  "short_name": "OffRent",
  "description": "Equipment rental cost tracking, off-rent confirmations and invoice review for contractors.",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#171A1F",
  "theme_color": "#171A1F",
  "icons": [
    {{ "src": "/assets/img/icon-192.png", "sizes": "192x192", "type": "image/png" }},
    {{ "src": "/assets/img/icon-512.png", "sizes": "512x512", "type": "image/png" }}
  ]
}}
"""


WEBSITE_README = f"""# Website

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

{SUPPORT_EMAIL}
"""


# --- image assets ------------------------------------------------------------------------------

def build_images(target: pathlib.Path) -> list[str]:
    """Derives every image on the site from the one real asset: the app icon.

    Nothing here invents artwork. The favicons and the touch icon are resamples of the shipped
    1024px icon, and the social card is that icon on the same graphite the icon itself uses.
    """
    from PIL import Image, ImageDraw, ImageFont  # noqa: PLC0415

    target.mkdir(parents=True, exist_ok=True)
    written: list[str] = []
    master = Image.open(ICON).convert("RGB")

    for size in (64, 192, 512):
        name = f"icon-{size}.png"
        master.resize((size, size), Image.LANCZOS).save(target / name, optimize=True)
        written.append(name)

    # Apple wants the touch icon square and un-rounded; iOS applies the mask itself.
    master.resize((180, 180), Image.LANCZOS).save(target / "apple-touch-icon.png", optimize=True)
    written.append("apple-touch-icon.png")

    master.resize((64, 64), Image.LANCZOS).save(
        target / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)]
    )
    written.append("favicon.ico")

    # The social card: the real icon on the icon's own graphite, with the product name and the
    # line the site leads with. No invented interface, no screenshot that does not exist.
    card = Image.new("RGB", (1200, 630), "#171A1F")
    draw = ImageDraw.Draw(card)
    draw.rectangle([0, 0, 1200, 6], fill="#FF8A1F")
    logo = master.resize((208, 208), Image.LANCZOS)
    mask = Image.new("L", (208 * 4, 208 * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, 208 * 4 - 1, 208 * 4 - 1], radius=48 * 4, fill=255)
    card.paste(logo, (96, 150), mask.resize((208, 208), Image.LANCZOS))

    def font(size: int, bold: bool = True) -> "ImageFont.FreeTypeFont":
        face = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
        try:
            return ImageFont.truetype(f"/usr/share/fonts/truetype/dejavu/{face}", size)
        except OSError:
            return ImageFont.load_default()

    draw.text((360, 168), APP_NAME, font=font(66), fill="#F6F1E8")
    draw.text((360, 258), "Stop the rental clock", font=font(46), fill="#F6F1E8")
    draw.text((360, 314), "with proof.", font=font(46), fill="#FF8A1F")
    draw.text((360, 402), "Track rental costs · record off-rent confirmations",
              font=font(26, bold=False), fill="#A8B0BC")
    draw.text((360, 440), "follow pickups · review final invoices",
              font=font(26, bold=False), fill="#A8B0BC")
    draw.text((96, 528), COMPANY + "  ·  offrent.idlery.com",
              font=font(24, bold=False), fill="#A8B0BC")
    card.save(target / "social-card.png", optimize=True)
    written.append("social-card.png")

    # Real screenshots, if any have been added.
    if SCREENSHOTS:
        shots_dir = target / "screens"
        shots_dir.mkdir(exist_ok=True)
        source_dir = ROOT / "marketing" / "screenshots"
        for entry in SCREENSHOTS:
            shutil.copy2(source_dir / entry["file"], shots_dir / entry["file"])
            written.append(f"screens/{entry['file']}")

    return written


# --- writing -------------------------------------------------------------------------------------

def build() -> dict[str, bytes]:
    """The whole site as a path → bytes mapping, so `--check` can compare without writing."""
    files: dict[str, str] = {
        "index.html": landing_page(),
        "privacy/index.html": legal_page(
            source=LEGAL / "PrivacyPolicy.md",
            slug="privacy",
            title="Privacy Policy",
            description=(
                f"{APP_NAME} keeps everything on your iPhone. No account, no server, no analytics, "
                "no advertising identifier and no tracking."
            ),
        ),
        "terms/index.html": legal_page(
            source=LEGAL / "TermsOfUse.md",
            slug="terms",
            title="Terms of Use",
            description=(
                f"The terms covering {APP_NAME}, including what the app is not: it does not contact "
                "rental companies and does not end rentals."
            ),
        ),
        "support/index.html": support_page(),
        "404.html": not_found_page(),
        "assets/css/site.css": CSS.strip() + "\n",
        "robots.txt": ROBOTS,
        "sitemap.xml": sitemap(),
        "site.webmanifest": webmanifest(),
        "_headers": HEADERS,
        "_redirects": REDIRECTS,
        "README.md": WEBSITE_README,
    }
    return {path: text.encode() for path, text in files.items()}


def main() -> int:
    check = "--check" in sys.argv
    files = build()

    if check:
        stale: list[str] = []
        for path, content in files.items():
            existing = OUT / path
            if not existing.exists() or existing.read_bytes() != content:
                stale.append(path)
        for name in ["assets/img/icon-192.png", "assets/img/apple-touch-icon.png",
                     "assets/img/favicon.ico", "assets/img/social-card.png"]:
            if not (OUT / name).exists():
                stale.append(name)
        if stale:
            print("STALE: Website/ differs from scripts/generate_website.py")
            for path in sorted(stale)[:12]:
                print(f"  {path}")
            print("Run: python3 scripts/generate_website.py")
            return 1
        print(f"ok: Website/ is current ({len(files)} files)")
        return 0

    if OUT.exists():
        shutil.rmtree(OUT)
    for path, content in files.items():
        destination = OUT / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(content)

    images = build_images(OUT / "assets" / "img")

    # GitHub Pages would otherwise refuse to serve a path beginning with an underscore.
    (OUT / ".nojekyll").write_text("")

    print(f"wrote: Website/ ({len(files)} files, {len(images)} images)")
    if not SCREENSHOTS:
        print(f"       no screenshots — {len(RESERVED_SHOTS)} reserved frames render instead")
    return 0


if __name__ == "__main__":
    sys.exit(main())
