#!/usr/bin/env python3
"""Generates Website/ from the legal Markdown the app bundles.

The app renders `OffRentLedger/Resources/Legal/*.md`; the website renders the same files. That is
the point of generating rather than hand-writing: a privacy policy that says one thing in the app
and another on the web is an App Review problem and a broken promise, and it is exactly the kind
of drift that happens when two copies exist.

Nothing here deploys anything. The output is a static site ready for GitHub Pages or any host,
and until it is actually served, `AppConfiguration.legalURLsAreLive` stays false and the app
links to nothing.

Run:   python3 scripts/generate_website.py
Check: python3 scripts/generate_website.py --check
"""

import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LEGAL = ROOT / "OffRentLedger" / "Resources" / "Legal"
OUT = ROOT / "Website"

APP_NAME = "OffRent Ledger"
COMPANY = "Idlery Services LLC"
SUPPORT_EMAIL = "support@idlery.com"

STYLE = """
:root {
  color-scheme: light dark;
  --ink: #1a1c22;
  --muted: #5b6270;
  --bg: #fbfaf7;
  --card: #ffffff;
  --accent: #d86616;
  --rule: #e3e0d9;
}
@media (prefers-color-scheme: dark) {
  :root {
    --ink: #eceef2; --muted: #a2aab8; --bg: #16181c;
    --card: #1e2126; --accent: #f28a36; --rule: #313640;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0; padding: 0;
  background: var(--bg); color: var(--ink);
  font: 16px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
}
.wrap { max-width: 46rem; margin: 0 auto; padding: 2.5rem 1.25rem 4rem; }
header { border-bottom: 1px solid var(--rule); padding-bottom: 1.25rem; margin-bottom: 2rem; }
.mark { display: flex; align-items: center; gap: .65rem; }
.mark svg { width: 34px; height: 34px; flex: none; }
.mark strong { font-size: 1.1rem; letter-spacing: -0.01em; }
.mark span { color: var(--muted); font-size: .85rem; }
nav { margin-top: 1rem; display: flex; flex-wrap: wrap; gap: 1.1rem; font-size: .9rem; }
nav a { color: var(--accent); text-decoration: none; }
nav a:hover { text-decoration: underline; }
h1 { font-size: 1.75rem; letter-spacing: -0.02em; margin: 0 0 .5rem; }
h2 { font-size: 1.15rem; margin: 2.2rem 0 .6rem; letter-spacing: -0.01em; }
h3 { font-size: 1rem; margin: 1.5rem 0 .4rem; }
p, li { color: var(--ink); }
ul { padding-left: 1.2rem; }
li { margin: .3rem 0; }
strong { font-weight: 650; }
hr { border: 0; border-top: 1px solid var(--rule); margin: 2.5rem 0; }
.note {
  background: var(--card); border: 1px solid var(--rule);
  border-left: 3px solid var(--accent);
  border-radius: 10px; padding: 1rem 1.15rem; margin: 1.5rem 0;
}
.note p { margin: 0; }
footer { margin-top: 3rem; padding-top: 1.25rem; border-top: 1px solid var(--rule); color: var(--muted); font-size: .85rem; }
footer a { color: var(--accent); }
code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .9em; }
"""

# The same original mark as the app icon: an orange octagon with a graphite hand.
LOGO = (
    '<svg viewBox="0 0 100 100" aria-hidden="true">'
    '<path d="M30 6 H70 L94 30 V70 L70 94 H30 L6 70 V30 Z" fill="none" '
    'stroke="var(--accent)" stroke-width="11" stroke-linejoin="round"/>'
    '<circle cx="50" cy="55" r="6" fill="var(--ink)"/>'
    '<path d="M50 55 L70 34" stroke="var(--ink)" stroke-width="8" stroke-linecap="round"/>'
    "</svg>"
)


def markdown_to_html(source: str) -> str:
    """A deliberately small Markdown subset: headings, bullets, bold, and paragraphs.

    The legal documents are written to this subset on purpose. Pulling in a Markdown library to
    render two files would add a dependency to a repository whose whole privacy story is that it
    has none.
    """
    lines = source.splitlines()
    out: list[str] = []
    in_list = False

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

    def close_list() -> None:
        nonlocal in_list
        if in_list:
            out.append("</ul>")
            in_list = False

    for raw in lines:
        line = raw.rstrip()
        if not line.strip():
            close_list()
            continue
        if line.startswith("### "):
            close_list(); out.append(f"<h3>{inline(line[4:])}</h3>")
        elif line.startswith("## "):
            close_list(); out.append(f"<h2>{inline(line[3:])}</h2>")
        elif line.startswith("# "):
            close_list(); out.append(f"<h1>{inline(line[2:])}</h1>")
        elif line.startswith("- "):
            if not in_list:
                out.append("<ul>"); in_list = True
            out.append(f"<li>{inline(line[2:])}</li>")
        elif line.startswith("---"):
            close_list(); out.append("<hr>")
        else:
            close_list(); out.append(f"<p>{inline(line)}</p>")
    close_list()
    return "\n".join(out)


def page(title: str, body: str, description: str) -> str:
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} · {APP_NAME}</title>
<meta name="description" content="{html.escape(description)}">
<style>{STYLE}</style>
</head>
<body>
<div class="wrap">
<header>
  <div class="mark">
    {LOGO}
    <div>
      <strong>{APP_NAME}</strong><br>
      <span>{COMPANY}</span>
    </div>
  </div>
  <nav>
    <a href="./">Overview</a>
    <a href="./privacy.html">Privacy</a>
    <a href="./terms.html">Terms</a>
    <a href="./support.html">Support</a>
  </nav>
</header>
{body}
<footer>
  <p>{APP_NAME} is a record-keeping tool. It does not contact rental companies and does not end
  rentals.</p>
  <p>{COMPANY} · <a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a></p>
</footer>
</div>
</body>
</html>
"""


INDEX_BODY = f"""
<h1>Know what every rental is costing you</h1>
<p>{APP_NAME} is an iPhone app for contractors who rent equipment. Track what a machine is
costing while it sits on the jobsite, capture the rental company's off-rent confirmation number,
record pickup, and check the final invoice against the terms you confirmed.</p>

<div class="note">
  <p><strong>{APP_NAME} does not notify the rental company or end your rental.</strong>
  Contact the vendor directly and obtain its confirmation number. The app helps you record what
  happened, reminds you to get that number, and keeps the evidence together.</p>
</div>

<h2>What it does</h2>
<ul>
  <li>Estimates what each rental is costing, from the rates and dates you confirm.</li>
  <li>Reminds you before a rate change so you can decide whether to keep the machine.</li>
  <li>Walks you through contacting the vendor and recording its confirmation number.</li>
  <li>Records pickup, meter readings, fuel level and condition photographs.</li>
  <li>Lays a final invoice next to the terms you confirmed and flags anything worth a look.</li>
  <li>Assembles it all into one PDF you can keep or send.</li>
</ul>

<h2>What it is not</h2>
<ul>
  <li>It is not a way to contact a rental company. You do that.</li>
  <li>Its figures are estimates, not invoices, and not a statement of what you owe.</li>
  <li>A "possible mismatch" means an invoice differs from what you entered. It is not a finding
  that any charge is wrong.</li>
  <li>It does not provide legal, accounting, insurance or contract advice.</li>
</ul>

<h2>Your data</h2>
<p>Everything stays on your iPhone. There is no account, no server, no analytics and no tracking.
Scanning and text recognition run on the device. See the
<a href="./privacy.html">privacy policy</a>.</p>

<h2>Pricing</h2>
<p>Free for one open rental at a time, with the complete workflow available on it. {APP_NAME} Pro
adds unlimited open rentals, the invoice audit, evidence packet PDFs, the widget, advanced
reminders and full history export. Current prices are shown in the App Store.</p>
<p>Cancelling never removes or hides anything you have already recorded.</p>
"""

SUPPORT_BODY = f"""
<h1>Support</h1>
<p>Email <a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a>. {APP_NAME} collects no diagnostics
of its own, so please describe what you were doing and what happened.</p>

<h2>Does {APP_NAME} contact my rental company?</h2>
<p>No. It never has. It helps you record what you did, reminds you to get a confirmation number,
and keeps the evidence together. Calling the yard is still your job.</p>

<h2>Are the amounts what I owe?</h2>
<p>No. They are estimates built from the rates and dates you entered. Your invoice and your rental
agreement are what count.</p>

<h2>Does a possible mismatch mean I was overcharged?</h2>
<p>No. It means an invoice differs from the terms you told the app about. That could be the
vendor, your entry, or a term the app cannot see.</p>

<h2>Where is my data?</h2>
<p>On your iPhone. There is no account and no server. Export from Settings before deleting the app
— we hold no copy and cannot recover anything for you.</p>

<h2>What happens if I cancel Pro?</h2>
<p>Nothing you have is removed or hidden. You keep editing, resolving, exporting and deleting
everything. You just cannot open a new rental beyond the free limit.</p>
"""

README = f"""# Website

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
"""


def build() -> dict[str, str]:
    files = {
        "index.html": page("Overview", INDEX_BODY, f"{APP_NAME} — equipment rental off-rent and invoice tracking for contractors."),
        "support.html": page("Support", SUPPORT_BODY, f"Support for {APP_NAME}."),
        "README.md": README,
        ".nojekyll": "",
    }
    for name, source in [("privacy.html", "PrivacyPolicy.md"), ("terms.html", "TermsOfUse.md")]:
        markdown = (LEGAL / source).read_text()
        title = "Privacy Policy" if "privacy" in name else "Terms of Use"
        files[name] = page(
            title,
            markdown_to_html(markdown),
            f"{title} for {APP_NAME} by {COMPANY}.",
        )
    return files


def main() -> int:
    files = build()
    if "--check" in sys.argv:
        stale = [
            name for name, content in files.items()
            if not (OUT / name).exists() or (OUT / name).read_text() != content
        ]
        if stale:
            print(f"STALE: {stale} — run python3 scripts/generate_website.py", file=sys.stderr)
            return 1
        print("ok: Website/ is current")
        return 0

    OUT.mkdir(exist_ok=True)
    for name, content in files.items():
        (OUT / name).write_text(content)
    print(f"wrote: Website/ ({len(files)} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
