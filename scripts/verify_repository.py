#!/usr/bin/env python3
"""Repository invariants for OffRent Ledger.

These are the rules that no compiler enforces and that a reviewer will not reliably catch:
a phrase that claims the app contacted a vendor, a CoreCredit identifier left behind, a status
assigned outside the one service allowed to assign it, an App Group that drifted between the
entitlement and the Swift constant, a placeholder legal URL presented as live.

Every check here exists because getting it wrong is either a shipped falsehood or a bug that
only appears on a device nobody has yet.

Run:  python3 scripts/verify_repository.py
Exit: 0 clean, 1 with failures listed.
"""

from __future__ import annotations

import json
import pathlib
import plistlib
import re
import shutil
import subprocess
import sys
import xml.dom.minidom

ROOT = pathlib.Path(__file__).resolve().parent.parent

APP_SOURCES = ROOT / "OffRentLedger"
SHARED_SOURCES = ROOT / "OffRentShared"
WIDGET_SOURCES = ROOT / "OffRentLedgerWidget"
DOMAIN = APP_SOURCES / "Domain"
TESTS = [ROOT / "OffRentLedgerTests", ROOT / "OffRentLedgerUITests", ROOT / "Tests"]

failures: list[str] = []
checks_run = 0


def fail(check: str, detail: str) -> None:
    failures.append(f"{check}: {detail}")


def check(name: str):
    global checks_run
    checks_run += 1
    print(f"  · {name}")


def swift_files(*roots: pathlib.Path) -> list[pathlib.Path]:
    out: list[pathlib.Path] = []
    for root in roots:
        if root.exists():
            out.extend(sorted(root.rglob("*.swift")))
    return out


def all_text_files() -> list[pathlib.Path]:
    patterns = ("*.swift", "*.md", "*.html", "*.yaml", "*.json", "*.plist", "*.xcconfig", "*.storekit")
    out: list[pathlib.Path] = []
    for pattern in patterns:
        for path in ROOT.rglob(pattern):
            if any(part in {".git", ".build", "DerivedData"} for part in path.parts):
                continue
            out.append(path)
    return sorted(out)


def without_comments(source: str) -> str:
    """Strips Swift comments.

    Needed because several checks look for a symbol that must not be *used*, and the file most
    likely to mention it is the one explaining why it is never used. `LocationProvider.swift`
    says "there is no `startUpdatingLocation` in this file", and a check that cannot tell code
    from prose fails on the very comment documenting the invariant it is enforcing.
    """
    stripped = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return re.sub(r"//[^\n]*", "", stripped)


def string_literals(source: str) -> list[str]:
    """User-facing string literals, including multi-line ones."""
    literals = re.findall(r'"""(.*?)"""', source, re.S)
    without_multiline = re.sub(r'"""(.*?)"""', '""', source, flags=re.S)
    literals += re.findall(r'"((?:[^"\\\n]|\\.)*)"', without_multiline)
    return literals


# ---------------------------------------------------------------------------------------------
# 1. No CoreCredit inheritance
# ---------------------------------------------------------------------------------------------

def check_no_corecredit() -> None:
    check("No CoreCredit identifiers, names or bundle IDs anywhere")
    # "CoreCredit" is allowed only where this repository explicitly *discusses* the other project.
    allowed = {
        "PROJECT_SOURCE_OF_TRUTH.md", "IMPLEMENTATION_PLAN.md", "RELEASE_CHECKLIST.md",
        "TEST_MATRIX.md", "README.md", "docs/RISK_REGISTER.md",
        "scripts/verify_repository.py", "scripts/generate_xcodeproj.py",
        "scripts/generate_assets.py", "Config/Identifiers.xcconfig",
        "StoreKit/README.md",
    }
    banned = ["CoreCredit", "corecredit", "com.blakekimble", "QuickScanWidget", "Money at Risk"]
    for path in all_text_files():
        relative = path.relative_to(ROOT).as_posix()
        if relative in allowed:
            continue
        text = path.read_text(errors="ignore")
        for token in banned:
            if token in text:
                fail("corecredit-inheritance", f"{relative} contains {token!r}")


# ---------------------------------------------------------------------------------------------
# 2. Truth and safety language
# ---------------------------------------------------------------------------------------------

BANNED_PHRASES = [
    "rental successfully ended",
    "rental ended",
    "vendor notified",
    "we notified",
    "we contacted the vendor",
    "guaranteed savings",
    "verified overcharge",
    "legal proof",
    "legally binding proof",
    "tamper-proof",
    "tamper proof",
    # Closing a rental out is an act between a contractor and a yard. The app's own record moving
    # to Resolved is a different thing, and the acceptance confirmation used to blur the two.
    # Narrow on purpose: "Closed" on its own is a real status and a real section header.
    "closed out",
    "close out the rental",
]

# Phrases that are the banned ones with words inserted, which a substring test cannot see.
#
# `"You closed this item out."` shipped past the list for eight builds: it means exactly what
# "closed out" means and shares none of its characters in order. A list of literals always fails
# this way, so the few worth catching are expressed as patterns.
BANNED_PATTERNS = [
    (r"clos(?:e|ed|ing)\b[^.]{0,24}\bout\b", "claims a rental was closed out"),
    (r"\bend(?:ed|s|ing)?\b\s+(?:your|the|this|any)\s+rental\b", "claims a rental was ended"),
    (r"\bwe\b[^.]{0,16}\b(?:called|phoned|emailed|contacted|notified)\b", "claims the app contacted someone"),
]

# The app's most important copy is the copy that *denies* doing these things — "does not notify
# the rental company or end your rental" is a required disclosure, not a violation. So a match is
# only a failure when nothing negates it just before, which is the same shape the legal-document
# check already uses.
NEGATION_WINDOW = 60
NEGATIONS = ("not ", "never ", "n't ", "without ", "cannot ", "no one ", "nothing ")


def check_banned_phrases() -> None:
    check("No phrase claiming the app contacted a vendor or ended a rental")
    for path in swift_files(APP_SOURCES, SHARED_SOURCES, WIDGET_SOURCES):
        relative = path.relative_to(ROOT).as_posix()
        for literal in string_literals(path.read_text(errors="ignore")):
            lowered = literal.lower()
            for phrase in BANNED_PHRASES:
                if phrase in lowered:
                    fail("banned-phrase", f"{relative} string contains {phrase!r}")
            for pattern, why in BANNED_PATTERNS:
                for match in re.finditer(pattern, lowered):
                    start = max(0, match.start() - NEGATION_WINDOW)
                    run_up = lowered[start: match.start()]
                    if any(negation in run_up for negation in NEGATIONS):
                        continue
                    excerpt = lowered[match.start(): match.end()]
                    fail("banned-phrase", f"{relative} string {why}: …{excerpt}…")

    # The shipped legal text and the website are user-facing too. "not legally binding" and
    # "not a chain of custody" are denials, so the check looks for the claim without its negation.
    for path in list((ROOT / "OffRentLedger" / "Resources" / "Legal").glob("*.md")) + list(
        (ROOT / "Website").rglob("*.html")
    ):
        text = path.read_text(errors="ignore").lower()
        for phrase in ["guaranteed savings", "verified overcharge", "tamper-proof"]:
            if phrase in text:
                fail("banned-phrase", f"{path.relative_to(ROOT)} contains {phrase!r}")
        for claim in ["legally binding", "legal proof"]:
            for match in re.finditer(re.escape(claim), text):
                # Scoped to the enclosing section rather than a fixed character count. A legal
                # document denies these claims in a bulleted list under a heading like "does not
                # and cannot", and the negation can be several bullets above the phrase — which
                # is exactly how a reader parses it. An affirmative claim in a section that never
                # denies it still fails.
                section_start = text.rfind("\n#", 0, match.start())
                window = text[max(section_start, 0): match.start()]
                if not any(
                    negation in window
                    for negation in ("not ", "never ", "cannot", "no ", "nothing ", "does not")
                ):
                    fail("banned-phrase", f"{path.relative_to(ROOT)} asserts {claim!r} undenied")


def check_end_rental_label() -> None:
    check('No control labelled "End Rental"')
    pattern = re.compile(r'"(?:End|Terminate|Cancel)\s+(?:the\s+)?Rental"', re.I)
    for path in swift_files(APP_SOURCES, SHARED_SOURCES, WIDGET_SOURCES):
        if pattern.search(without_comments(path.read_text(errors="ignore"))):
            fail("end-rental-label", f"{path.relative_to(ROOT)} labels a control as ending a rental")


def check_required_disclosure() -> None:
    check("The off-rent disclosure exists and says the required things")
    copy = (APP_SOURCES / "Configuration" / "AppCopy.swift").read_text()
    for required in ["does not notify the rental company", "obtain its confirmation number"]:
        if required not in copy:
            fail("disclosure", f"AppCopy.offRentDisclosure is missing {required!r}")

    # And it is actually rendered where it matters.
    for name in ["RecordConfirmationSheet.swift", "RentalItemDetailView.swift"]:
        matches = list(APP_SOURCES.rglob(name))
        if not matches:
            fail("disclosure", f"{name} not found")
            continue
        if "OffRentDisclosureBanner" not in matches[0].read_text():
            fail("disclosure", f"{name} does not render OffRentDisclosureBanner")


def check_launch_screen_is_wired() -> None:
    """The launch screen names assets that exist, and nothing regenerates it.

    `UILaunchScreen` fails silently: a name the catalog does not have simply leaves that layer
    out, and the only symptom is the app opening on a white flash. `LaunchScreenTests` pins this
    at runtime; this pins it at commit time, where it is cheaper to notice.
    """
    check("The launch screen names assets that exist")
    info = ROOT / "Config" / "OffRentLedger-Info.plist"
    with info.open("rb") as handle:
        plist = plistlib.load(handle)
    launch = plist.get("UILaunchScreen")
    if not isinstance(launch, dict):
        fail("launch-screen", "Config/OffRentLedger-Info.plist has no UILaunchScreen dictionary")
        return
    for key, folder, suffix in (
        ("UIColorName", "colorset", ""),
        ("UIImageName", "imageset", ""),
    ):
        name = launch.get(key)
        if not name:
            fail("launch-screen", f"UILaunchScreen has no {key}")
            continue
        catalog = APP_SOURCES / "Resources" / "Assets.xcassets"
        if not (catalog / f"{name}.{folder}").is_dir():
            fail("launch-screen", f"UILaunchScreen names {name}, which is not in the catalog")

    # A generated UILaunchScreen key merges an *empty* dictionary on top of the file above.
    project = (ROOT / "OffRentLedger.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
    if "INFOPLIST_KEY_UILaunchScreen_Generation = YES" in project:
        fail(
            "launch-screen",
            "INFOPLIST_KEY_UILaunchScreen_Generation is on; it would blank the launch screen",
        )

    # The SwiftUI layer draws the same assets and the credit. Matched against the *call*, not
    # against the name appearing anywhere in the file: the first version of this check was
    # satisfied by the phrase in a doc comment, so deleting the credit line from the body left it
    # passing.
    splash = (APP_SOURCES / "SharedUI" / "LaunchSplashView.swift").read_text(encoding="utf-8")
    for call in (
        'Image("LaunchMark")',
        'Color("LaunchBackground")',
        'Image("IdleryWordmark")',
        'Text("Powered by")',
    ):
        if call not in splash:
            fail("launch-screen", f"LaunchSplashView no longer contains {call}")


def check_every_swift_file_parses() -> None:
    """Every Swift file in the repository is syntactically valid.

    `swiftc -parse` runs the parser alone: it needs no SwiftUI, no SwiftData and no module map,
    so it works on a Linux container with no Xcode. It does not type-check — that still needs a
    real build — but it catches the whole class of failure that cost several CI rounds during
    this project: an unbalanced brace, a malformed multi-line string literal, a `Section` written
    with a modifier that does not exist as written.

    Skipped, loudly, when no Swift toolchain is on PATH, so the check cannot silently pass.
    """
    check("Every Swift file parses")
    swiftc = shutil.which("swiftc") or "/opt/swift/usr/bin/swiftc"
    if not pathlib.Path(swiftc).exists():
        print("    (no swiftc on this machine — parse check skipped)")
        return
    roots = ["OffRentLedger", "OffRentLedgerWidget", "OffRentShared",
             "OffRentLedgerTests", "OffRentLedgerUITests", "Tests", "Tools"]
    files: list[pathlib.Path] = []
    for root in roots:
        directory = ROOT / root
        if directory.exists():
            files.extend(sorted(directory.rglob("*.swift")))
    for path in files:
        result = subprocess.run(
            [swiftc, "-parse", str(path)], capture_output=True, text=True, check=False
        )
        if result.returncode != 0 or result.stderr.strip():
            first = (result.stderr.strip().splitlines() or ["unknown parse failure"])[0]
            fail("swift-parse", f"{path.relative_to(ROOT)}: {first}")


def check_no_duplicate_top_level_types() -> None:
    """No two Swift files in a target may declare the same top-level type.

    Added after a redesign introduced a generic `TimelineRow<Content>` in the shared component
    file while a concrete `TimelineRow` already existed in the detail screen. Swift calls that an
    invalid redeclaration and the whole target fails; without a macOS toolchain here, nothing else
    in this repository would have caught it before Codemagic did.
    """
    check("No duplicate top-level type declarations")
    pattern = re.compile(
        r"^(?:public |internal |private |fileprivate |final |@[\w()]+\s+)*"
        r"(?:struct|class|enum|actor|protocol)\s+([A-Z]\w*)",
        re.MULTILINE,
    )
    # The app target compiles OffRentLedger + OffRentShared; the widget compiles
    # OffRentLedgerWidget + OffRentShared. A name may repeat across app and widget, but not
    # within either.
    targets = {
        "app": ["OffRentLedger", "OffRentShared"],
        "widget": ["OffRentLedgerWidget", "OffRentShared"],
        "tests": ["OffRentLedgerTests"],
        "uitests": ["OffRentLedgerUITests"],
    }
    for target, roots in targets.items():
        seen: dict[str, str] = {}
        for root in roots:
            for path in sorted((ROOT / root).rglob("*.swift")):
                text = path.read_text(encoding="utf-8")
                # Only top-level declarations: nested types are legal duplicates.
                for match in pattern.finditer(text):
                    if match.start() != 0 and text[match.start() - 1] != "\n":
                        continue
                    name = match.group(1)
                    where = str(path.relative_to(ROOT))
                    if name in seen and seen[name] != where:
                        fail(
                            "duplicate-type",
                            f"{target}: '{name}' is declared in both {seen[name]} and {where}",
                        )
                    seen[name] = where


def check_estimates_are_labelled() -> None:
    check("Derived amounts render through EstimateLabel")
    components = (APP_SOURCES / "SharedUI" / "Components.swift").read_text()
    if "AppCopy.estimateQualifier" not in components:
        fail("estimate-label", "EstimateLabel no longer renders the estimate qualifier")
    if 'static let estimateQualifier = "Estimate"' not in (
        APP_SOURCES / "Configuration" / "AppCopy.swift"
    ).read_text():
        fail("estimate-label", "AppCopy.estimateQualifier changed unexpectedly")


# ---------------------------------------------------------------------------------------------
# 3. Architecture
# ---------------------------------------------------------------------------------------------

FORBIDDEN_DOMAIN_IMPORTS = [
    "SwiftUI", "SwiftData", "StoreKit", "Vision", "VisionKit", "UIKit", "CoreLocation",
    "PDFKit", "WidgetKit", "UserNotifications", "AppIntents", "PhotosUI", "CryptoKit", "OSLog",
]


def check_domain_is_portable() -> None:
    check("Domain and OffRentShared import Foundation only")
    for path in swift_files(DOMAIN, SHARED_SOURCES):
        source = path.read_text()
        for module in FORBIDDEN_DOMAIN_IMPORTS:
            if re.search(rf"^\s*import\s+{module}\b", source, re.M):
                fail(
                    "portable-domain",
                    f"{path.relative_to(ROOT)} imports {module}; the SwiftPM package will not build",
                )


def check_saves_are_not_silent() -> None:
    check("No screen discards a save failure")
    # `try? context.save()` in a view is the app telling somebody their record was filed when it
    # may not have been. `PersistentStore.save` returns a sentence to show them;
    # `PersistentStore.saveDerived` logs, and is only for caches the app recomputes anyway.
    # Neither is `try?`, which is why this looks for `try?` and nothing else.
    pattern = re.compile(r"try\?\s+\w*[cC]ontext\.save\(\)")
    for path in swift_files(APP_SOURCES, WIDGET_SOURCES):
        relative = path.relative_to(ROOT).as_posix()
        if relative == "OffRentLedger/Persistence/PersistentStore.swift":
            continue
        source = without_comments(path.read_text())
        for match in pattern.finditer(source):
            line = source[: match.start()].count("\n") + 1
            fail(
                "silent-save",
                f"{relative}:{line} discards a save failure; "
                "use PersistentStore.save or PersistentStore.saveDerived",
            )


def check_status_assignment_is_confined() -> None:
    check("Only RentalWorkflowService assigns rental status")
    allowed = {"OffRentLedger/Persistence/RentalWorkflowService.swift"}
    # The property's own declaration and initialiser, in every schema version there is. Matched
    # by shape rather than listed, so adding SchemaV5 does not silently fail this check.
    schema_file = re.compile(r"^OffRentLedger/Persistence/SchemaV\d+\.swift$")
    # `=` and not `==`: a predicate comparing the column is a read, not an assignment. And the
    # discrepancy model's own status is deliberately named `discrepancyStatusRaw` so that this
    # pattern means one thing only.
    pattern = re.compile(r"\.statusRaw\s*=(?!=)")
    for path in swift_files(APP_SOURCES, WIDGET_SOURCES):
        relative = path.relative_to(ROOT).as_posix()
        if relative in allowed or schema_file.match(relative):
            continue
        source = without_comments(path.read_text())
        for match in pattern.finditer(source):
            line = source[: match.start()].count("\n") + 1
            fail(
                "status-assignment",
                f"{relative}:{line} assigns statusRaw outside RentalWorkflowService",
            )


def check_display_name_is_centralised() -> None:
    check("The product name is written in exactly one place")
    # SharedBranding holds the literal; AppConfiguration re-exports it for app code.
    allowed = {
        "OffRentShared/SharedBranding.swift",
    }
    for path in swift_files(APP_SOURCES, SHARED_SOURCES, WIDGET_SOURCES):
        relative = path.relative_to(ROOT).as_posix()
        if relative in allowed:
            continue
        for literal in string_literals(path.read_text(errors="ignore")):
            if "OffRent Ledger" in literal:
                fail(
                    "display-name",
                    f"{relative} hardcodes the product name; use AppConfiguration.displayName",
                )


def check_app_intents_metadata_is_literal() -> None:
    check("AppIntents static metadata interpolates nothing at runtime")
    # `appintentsmetadataprocessor` runs after the Swift compile and extracts intent titles,
    # descriptions and display names from the source *as literals*. It cannot evaluate a runtime
    # property, so an IntentDescription interpolating AppConfiguration.displayName compiles
    # cleanly and then fails the build at the very last step with
    #   'LocalizedStringResource' is passed in an Interpolated String with an invalid segment.
    # That cost a full CI round to find, and it would cost another one to find again.
    #
    # The one exception is the leading-dot token form the processor does understand — the
    # applicationName token used in `phrases`. Interpolation in an *instance* property such as
    # `displayRepresentation` is fine and is deliberately not matched here: that is evaluated at
    # runtime by the app, not at build time by the processor.
    static_metadata = re.compile(
        r"(IntentDescription\s*\(|TypeDisplayRepresentation\s*\(|"
        r"static\s+(?:var|let)\s+title\s*:\s*LocalizedStringResource\s*=|"
        r"@Parameter\s*\(|shortTitle\s*:)"
    )
    for path in swift_files(APP_SOURCES, SHARED_SOURCES, WIDGET_SOURCES):
        source = without_comments(path.read_text())
        if "import AppIntents" not in source:
            continue
        relative = path.relative_to(ROOT).as_posix()
        for match in static_metadata.finditer(source):
            region = _metadata_region(source, match.end())
            for literal in string_literals(region):
                for segment in re.findall(r"\\\((.*?)\)", literal, re.S):
                    if segment.strip().startswith("."):
                        continue  # A token the processor resolves for itself.
                    line = source[: match.start()].count("\n") + 1
                    fail(
                        "appintents-metadata",
                        f"{relative}:{line} interpolates `{segment.strip()}` into static intent "
                        "metadata; appintentsmetadataprocessor can only read literals",
                    )


def _metadata_region(source: str, start: int) -> str:
    """The value that follows a static-metadata marker.

    A small lexer rather than a paren count, because both shapes occur: a title assigned with
    `=` ends at its line break, while an `IntentDescription(` opens a parenthesis and may not
    reach its literal until the next line. Counting parens alone stops too late on the first;
    stopping at a newline alone stops immediately on the second, before the literal has been
    reached at all.

    So: skip the leading whitespace first, then read tokens, treating string literals — the
    triple-quoted ones included — as opaque, so a bracket or a line break inside one cannot end
    the region early.
    """
    index = start
    while index < len(source) and source[index] in " \t\n":
        index += 1
    begin = index
    depth = 0
    while index < len(source):
        if source.startswith('"' * 3, index):
            closing = source.find('"' * 3, index + 3)
            index = len(source) if closing == -1 else closing + 3
            continue
        character = source[index]
        if character == '"':
            index += 1
            while index < len(source) and source[index] != '"':
                index += 2 if source[index] == "\\" else 1
            index += 1
            continue
        if character in "([":
            depth += 1
        elif character in ")]":
            if depth == 0:
                return source[begin:index]
            depth -= 1
        elif character == "\n" and depth == 0:
            return source[begin:index]
        index += 1
    return source[begin:]


def check_tests_import_foundation() -> None:
    check("Every test file imports Foundation explicitly")
    # `@testable import OffRentLedger` does not re-export Foundation, and neither does
    # `import Testing` or `import SwiftData`. A test file that happens to use only inferred
    # types compiles anyway; the moment somebody writes `Date()`, `Decimal(string:)` or
    # `Bundle.main` it fails with "cannot find 'Date' in scope".
    #
    # That is a nasty failure to find, because the Xcode test bundle only compiles on a Mac —
    # so the mistake is a full CI round away from whoever made it, and it lands in a file that
    # looks identical to the six around it that happen to still build. One unconditional import
    # removes the class of problem.
    for directory in TESTS:
        for path in swift_files(directory):
            source = path.read_text()
            if not re.search(r"^import Foundation$", source, re.M):
                relative = path.relative_to(ROOT).as_posix()
                fail("test-imports", f"{relative} does not import Foundation")


def check_decimal_parsing_pins_the_locale() -> None:
    check("Every Decimal built from a string pins en_US_POSIX")
    # `Decimal(string:)` and `Decimal(string:locale:)` are not the same function. With no locale
    # the string is read through whatever locale the *device* is set to, so "285.00" on a device
    # set to German is 28500 — a rate card off by a factor of a hundred, from a line that reads
    # correctly. `MoneyMath.parse` pins en_US_POSIX on the path a user's typing takes; nothing
    # else may take a different one, fixtures and placeholders included.
    pattern = re.compile(r"Decimal\(\s*string:\s*([^)]*)\)")
    for path in swift_files(APP_SOURCES, SHARED_SOURCES, WIDGET_SOURCES, *TESTS):
        source = without_comments(path.read_text())
        relative = path.relative_to(ROOT).as_posix()
        for match in pattern.finditer(source):
            if "locale:" in match.group(1):
                continue
            line = source[: match.start()].count("\n") + 1
            fail(
                "money-locale",
                f"{relative}:{line} builds a Decimal from a string without a locale; "
                "use MoneyMath.parse, or pass locale: Locale(identifier: \"en_US_POSIX\")",
            )


def check_tests_do_not_sleep_for_a_result() -> None:
    check("No test waits on the clock for an async result")
    # `Task.sleep` in a test is a guess about how fast the machine is. Six of them in
    # ScanReviewCommitTests passed on an idle CI machine and failed on a loaded one, reporting
    # four different symptoms that were all the same thing: the assertion ran before the work
    # finished. A test that sleeps does not fail when the code is wrong — it fails when the
    # machine is busy, which is worse than useless, because it trains everybody to re-run it.
    #
    # The fix is an awaitable completion point on the type under test, not a longer sleep.
    for directory in TESTS:
        for path in swift_files(directory):
            source = without_comments(path.read_text())
            relative = path.relative_to(ROOT).as_posix()
            for match in re.finditer(r"Task\.sleep", source):
                line = source[: match.start()].count("\n") + 1
                fail(
                    "test-sleep",
                    f"{relative}:{line} sleeps instead of awaiting; a sleep is a guess about "
                    "how fast the machine is, and it fails on the machine that is busy",
                )


def check_website_is_generated() -> None:
    check("Website/ matches its generator and the bundled legal text")
    # The site's privacy and terms pages are rendered from the same Markdown the app displays in
    # Settings. That is the whole reason the site is generated rather than written: a policy that
    # says one thing in the app and another on the web is an App Review problem and a broken
    # promise. This check is what stops somebody fixing a typo in the HTML and leaving the app
    # saying the old thing.
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "generate_website.py"), "--check"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        fail("website-stale", (result.stdout + result.stderr).strip())


def check_no_unsafe_unwraps() -> None:
    check("No force-try or force-cast on production paths")
    for path in swift_files(APP_SOURCES, SHARED_SOURCES, WIDGET_SOURCES):
        source = path.read_text()
        relative = path.relative_to(ROOT).as_posix()
        for line_number, line in enumerate(source.splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue
            if re.search(r"\btry!\s", line):
                fail("force-try", f"{relative}:{line_number}")
            if re.search(r"\bas!\s", line):
                fail("force-cast", f"{relative}:{line_number}")


ALLOWED_FATAL_ERROR = {
    # Preview/test infrastructure only: a failure there is a programmer error in a preview, and
    # there is no recovery that means anything to a user.
    "OffRentLedger/Persistence/ModelContainerFactory.swift",
}


def check_fatal_error_is_confined() -> None:
    check("fatalError only where a user could never reach it")
    for path in swift_files(APP_SOURCES, SHARED_SOURCES, WIDGET_SOURCES):
        relative = path.relative_to(ROOT).as_posix()
        if relative in ALLOWED_FATAL_ERROR:
            continue
        source = path.read_text()
        for line_number, line in enumerate(source.splitlines(), start=1):
            if line.strip().startswith("//"):
                continue
            if "fatalError(" in line:
                fail("fatal-error", f"{relative}:{line_number}")


def check_no_print() -> None:
    check("No print() in shipped sources")
    for path in swift_files(APP_SOURCES, SHARED_SOURCES, WIDGET_SOURCES):
        source = path.read_text()
        for line_number, line in enumerate(source.splitlines(), start=1):
            if line.strip().startswith("//"):
                continue
            if re.search(r"(?<![.\w])print\(", line):
                fail("print", f"{path.relative_to(ROOT)}:{line_number} uses print(); use Logger")


def check_no_third_party_dependencies() -> None:
    check("No third-party packages")
    pbxproj = (ROOT / "OffRentLedger.xcodeproj" / "project.pbxproj").read_text()
    for marker in ["XCRemoteSwiftPackageReference", "XCSwiftPackageProductDependency"]:
        if marker in pbxproj:
            fail("dependencies", f"project.pbxproj contains {marker}")
    if (ROOT / "Podfile").exists() or (ROOT / "Cartfile").exists():
        fail("dependencies", "a CocoaPods or Carthage manifest is present")


# ---------------------------------------------------------------------------------------------
# 4. Identifier consistency
# ---------------------------------------------------------------------------------------------

def read_xcconfig() -> dict[str, str]:
    values: dict[str, str] = {}
    for line in (ROOT / "Config" / "Identifiers.xcconfig").read_text().splitlines():
        line = line.split("//")[0].strip()
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip()
    return values


def check_identifier_consistency() -> None:
    check("App Group, URL scheme and bundle IDs agree everywhere")
    config = read_xcconfig()
    prefix = config.get("OFFRENT_BUNDLE_PREFIX", "")
    if prefix != "com.idlery.offrent":
        fail("identifiers", f"unexpected bundle prefix {prefix!r}")

    shared = (SHARED_SOURCES / "SharedIdentifiers.swift").read_text()
    expected_group = f"group.{prefix}"
    if f'"{expected_group}"' not in shared:
        fail("identifiers", f"SharedIdentifiers does not declare {expected_group}")

    scheme = config.get("OFFRENT_URL_SCHEME", "")
    if f'urlScheme = "{scheme}"' not in shared:
        fail("identifiers", f"SharedIdentifiers URL scheme does not match xcconfig {scheme!r}")

    for name in ["OffRentLedger.entitlements", "OffRentLedgerWidget.entitlements"]:
        data = plistlib.loads((ROOT / "Config" / name).read_bytes())
        groups = data.get("com.apple.security.application-groups", [])
        if expected_group not in groups:
            fail("identifiers", f"{name} does not contain {expected_group}")

    info = (ROOT / "Config" / "OffRentLedger-Info.plist").read_text()
    if "$(OFFRENT_URL_SCHEME)" not in info:
        fail("identifiers", "the app Info.plist does not use $(OFFRENT_URL_SCHEME)")


def check_storekit_products_match() -> None:
    check("StoreKit product identifiers match AppConfiguration")
    configuration = (APP_SOURCES / "Configuration" / "AppConfiguration.swift").read_text()
    declared = set(re.findall(r'"(com\.idlery\.offrent\.pro\.[a-z]+)"', configuration))

    storekit = json.loads((ROOT / "StoreKit" / "OffRentLedger.storekit").read_text())
    in_file = {
        subscription["productID"]
        for group in storekit.get("subscriptionGroups", [])
        for subscription in group.get("subscriptions", [])
    }
    if declared != in_file:
        fail("storekit", f"AppConfiguration has {sorted(declared)}, .storekit has {sorted(in_file)}")
    if len(storekit.get("subscriptionGroups", [])) != 1:
        fail("storekit", "there must be exactly one subscription group")


def check_no_hardcoded_prices() -> None:
    check("No price is hardcoded on a shipped path")
    for path in swift_files(APP_SOURCES, SHARED_SOURCES, WIDGET_SOURCES):
        relative = path.relative_to(ROOT).as_posix()
        # The stub service exists to give previews and UI tests a deterministic price.
        if relative.endswith("Services/SubscriptionService.swift"):
            continue
        for literal in string_literals(path.read_text(errors="ignore")):
            if re.fullmatch(r"\$\d+\.\d{2}", literal.strip()):
                fail("hardcoded-price", f"{relative} hardcodes {literal!r}; use Product.displayPrice")


def check_permission_strings() -> None:
    check("Every permission the app requests has a purpose string")
    info = (ROOT / "Config" / "OffRentLedger-Info.plist").read_text()
    sources = "\n".join(without_comments(p.read_text()) for p in swift_files(APP_SOURCES, WIDGET_SOURCES))

    # Both directions, because App Review reads both.
    #
    # A permission the code needs and the plist lacks is a crash the moment the user taps the
    # button. A permission the plist declares and the code never reaches is a question at review
    # — and worse, its purpose string describes a feature that does not exist. This app shipped
    # `NSPhotoLibraryAddUsageDescription` for eight builds promising to "save an evidence photo
    # back to your library", and nothing in it has ever written to the photo library:
    # `PhotosPicker` reads out of process and needs no entitlement at all.
    permissions = {
        "NSCameraUsageDescription": r"VNDocumentCameraViewController|AVCaptureDevice|UIImagePickerController",
        "NSLocationWhenInUseUsageDescription": r"CLLocationManager",
        "NSPhotoLibraryAddUsageDescription": r"UIImageWriteToSavedPhotosAlbum|PHPhotoLibrary|PHAssetCreationRequest",
        "NSPhotoLibraryUsageDescription": r"PHImageManager|PHAsset\b|ALAssetsLibrary",
        "NSMicrophoneUsageDescription": r"AVAudioRecorder|AVCaptureDevice\.default\(\.builtInMicrophone",
        "NSContactsUsageDescription": r"CNContactStore",
        "NSCalendarsUsageDescription": r"EKEventStore",
        "NSFaceIDUsageDescription": r"LAContext",
    }
    for key, pattern in permissions.items():
        declared = key in info
        used = re.search(pattern, sources) is not None
        if used and not declared:
            fail("permissions", f"Info.plist is missing {key}, which the code needs — that is a crash")
        if declared and not used:
            fail(
                "permissions",
                f"Info.plist declares {key}, but nothing in the app reaches an API that needs it",
            )
    if "NSLocationAlwaysAndWhenInUseUsageDescription" in info:
        fail("permissions", "the app declares always-on location, which it must not use")
    if "startUpdatingLocation" in sources or "startMonitoringSignificantLocationChanges" in sources:
        fail("permissions", "continuous location monitoring found; v1 is one-shot foreground only")
    if "UIBackgroundModes" in info:
        modes = plistlib.loads(
            (ROOT / "Config" / "OffRentLedger-Info.plist").read_bytes()
        ).get("UIBackgroundModes", [])
        if modes:
            fail("permissions", f"background modes declared: {modes}")


# The required-reason API categories, and the token in Swift source that means the app uses one.
#
# Apple's list is longer than this; these are the categories a local, offline, SwiftData app can
# plausibly reach. A category with no match in the source must not appear in a manifest, and one
# with a match must.
REQUIRED_REASON_APIS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": (
        r"\bUserDefaults\b",
        {"CA92.1", "1C8F.1", "AC6B.1", "C56D.1"},
    ),
    "NSPrivacyAccessedAPICategoryFileTimestamp": (
        r"\.creationDateKey|\.contentModificationDateKey|attributesOfItem|\bNSFileCreationDate\b"
        r"|\bNSFileModificationDate\b|\bgetattrlist\b|\bfstat\b",
        {"DDA9.1", "C617.1", "3B52.1", "0A2A.1"},
    ),
    "NSPrivacyAccessedAPICategoryDiskSpace": (
        r"volumeAvailableCapacity|volumeTotalCapacity|NSFileSystemFreeSize|systemFreeSize",
        {"85F4.1", "E174.1", "7D9E.1", "B728.1"},
    ),
    "NSPrivacyAccessedAPICategorySystemBootTime": (
        r"systemUptime|mach_absolute_time|mach_continuous_time",
        {"35F9.1", "8FFB.1", "3D61.1"},
    ),
    "NSPrivacyAccessedAPICategoryActiveKeyboards": (
        r"activeInputModes",
        {"3EC4.1", "54BD.1"},
    ),
}


def check_planned_urls_are_gated() -> None:
    check("A URL that is not live yet cannot be opened")
    # `AppConfiguration.legalURLsAreLive` is false while offrent.idlery.com has not been stood
    # up. It used to be documentation: three controls opened the planned Privacy Policy, Terms
    # and Support pages regardless, dropping the reader into Safari on an error page — from
    # screens App Review opens on purpose.
    #
    # The flag is a switch now, and this keeps it one. Flip it to true in AppConfiguration once
    # RELEASE_CHECKLIST.md records the domain as live and every gate opens at once.
    for path in swift_files(APP_SOURCES, WIDGET_SOURCES):
        if path.name == "AppConfiguration.swift":
            continue
        lines = path.read_text().splitlines()
        for index, line in enumerate(lines):
            if not re.search(r"\bplanned\w*URL\b", line):
                continue
            # A line that *declares* the property is not a line that reaches the URL. The gate
            # for `var plannedURL: URL? { ... }` lives inside its own body, on the next line.
            if re.match(r"\s*(?:@\w+\s+)*(?:private |static |var |let |func )+\w*[Uu]rl\b", line, re.IGNORECASE):
                continue
            if re.search(r"\b(?:var|let|func)\s+planned\w*URL\b", line):
                continue
            # Five lines, not one: the gate is allowed to be a `guard` at the top of the
            # property that returns the URL, which is the better place for it.
            window = "\n".join(lines[max(0, index - 5): index + 1])
            if "legalURLsAreLive" not in window:
                fail(
                    "planned-url",
                    f"{path.relative_to(ROOT)}:{index + 1} reaches a planned URL without "
                    "checking AppConfiguration.legalURLsAreLive first",
                )


def check_text_colours_meet_contrast() -> None:
    check("Every colour used as text clears 4.5:1 on every surface it sits on")
    # WCAG 1.4.3, which is also what an App Review accessibility pass measures. 4.5:1 for body
    # text; a *fill* only needs 3:1, which is why `AccentColor` and `AccentTextColor` are
    # different values rather than one compromise.
    #
    # The accent shipped for eight builds as the label colour of every secondary button in the
    # app — Accept, Question, Record a follow-up, Reopen — at 3.14:1 on the page. That is not a
    # close call, and nothing here would have caught it.
    import ast

    source = (ROOT / "scripts" / "generate_assets.py").read_text()
    tree = ast.parse(source)
    palette: dict[str, tuple] = {}
    for node in ast.walk(tree):
        if not isinstance(node, ast.Dict):
            continue
        for key, value in zip(node.keys, node.values):
            if not isinstance(key, ast.Constant) or not isinstance(key.value, str):
                continue
            try:
                palette[key.value] = ast.literal_eval(value)
            except ValueError:
                continue

    def channel(value: float) -> float:
        return value / 12.92 if value <= 0.03928 else ((value + 0.055) / 1.055) ** 2.4

    def luminance(rgb) -> float:
        red, green, blue = (channel(component) for component in rgb)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue

    def contrast(a, b) -> float:
        first, second = luminance(a), luminance(b)
        high, low = max(first, second), min(first, second)
        return (high + 0.05) / (low + 0.05)

    surfaces = ["SurfaceBackground", "SurfaceRaised", "SurfaceSunken"]
    missing = [name for name in surfaces if name not in palette]
    if missing:
        fail("contrast", f"generate_assets.py no longer defines {', '.join(missing)}")
        return

    # Only the tokens the app uses as text. A fill is measured against a different bar.
    for name in [key for key in palette if key.endswith("TextColor")] + ["TextPrimary", "TextSecondary"]:
        if name not in palette:
            continue
        for index, mode in enumerate(("light", "dark")):
            colour = palette[name][index]
            for surface in surfaces:
                background = palette[surface][index]
                ratio = contrast(colour, background)
                if ratio < 4.5:
                    fail(
                        "contrast",
                        f"{name} on {surface} in {mode} mode is {ratio:.2f}:1, "
                        "below the 4.5:1 that body text requires",
                    )


def check_privacy_manifests() -> None:
    check("Both privacy manifests exist and describe what the code actually does")
    # Required for App Store submission since May 2024. Its absence is not a warning — the
    # upload is accepted and the review is not, which is the most expensive possible way to find
    # out. An app extension needs its own; the app's does not cover it.
    #
    # Checked against the source rather than merely present, so that adding a required-reason API
    # later fails the build here instead of at review.
    targets = [
        (ROOT / "OffRentLedger" / "PrivacyInfo.xcprivacy", [APP_SOURCES, SHARED_SOURCES]),
        (ROOT / "OffRentLedgerWidget" / "PrivacyInfo.xcprivacy", [WIDGET_SOURCES, SHARED_SOURCES]),
    ]

    for path, roots in targets:
        relative = path.relative_to(ROOT)
        if not path.exists():
            fail("privacy-manifest", f"{relative} is missing; App Review requires one per target")
            continue
        try:
            manifest = plistlib.loads(path.read_bytes())
        except Exception as error:  # noqa: BLE001 - the message is the point
            fail("privacy-manifest", f"{relative} is not a readable plist: {error}")
            continue

        if manifest.get("NSPrivacyTracking") is not False:
            fail("privacy-manifest", f"{relative} must declare NSPrivacyTracking false")
        for key in ("NSPrivacyTrackingDomains", "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes"):
            if key not in manifest:
                fail("privacy-manifest", f"{relative} is missing {key}")

        # Nothing leaves the device, so a collected-data entry would contradict
        # `check_privacy_posture` and the shipped privacy policy.
        if manifest.get("NSPrivacyCollectedDataTypes"):
            fail(
                "privacy-manifest",
                f"{relative} declares collected data, but the app has no network client of its own",
            )

        declared: dict[str, set[str]] = {}
        for entry in manifest.get("NSPrivacyAccessedAPITypes", []):
            declared[entry.get("NSPrivacyAccessedAPIType", "")] = set(
                entry.get("NSPrivacyAccessedAPITypeReasons", [])
            )

        source = "\n".join(without_comments(p.read_text()) for p in swift_files(*roots))
        for category, (pattern, valid_reasons) in REQUIRED_REASON_APIS.items():
            used = re.search(pattern, source) is not None
            if used and category not in declared:
                fail(
                    "privacy-manifest",
                    f"{relative} does not declare {category}, but the target's source uses it",
                )
            if not used and category in declared:
                fail(
                    "privacy-manifest",
                    f"{relative} declares {category}, which this target's source never reaches",
                )
            for reason in declared.get(category, set()):
                if reason not in valid_reasons:
                    fail(
                        "privacy-manifest",
                        f"{relative} gives {reason!r} for {category}, which is not one of Apple's "
                        f"reason codes for it ({', '.join(sorted(valid_reasons))})",
                    )


def check_privacy_posture() -> None:
    check("No analytics, ads, tracking or network client")
    sources = swift_files(APP_SOURCES, SHARED_SOURCES, WIDGET_SOURCES)
    banned_symbols = [
        "URLSession", "Analytics", "Firebase", "Crashlytics", "AppsFlyer", "Mixpanel",
        "Amplitude", "Sentry", "AdSupport", "ASIdentifierManager", "ATTrackingManager",
        "GADBanner", "CloudKit", "NSUbiquitousKeyValueStore",
    ]
    for path in sources:
        source = without_comments(path.read_text())
        relative = path.relative_to(ROOT).as_posix()
        for symbol in banned_symbols:
            if not re.search(rf"\b{symbol}\b", source):
                continue
            # `cloudKitDatabase: .none` is the opposite of using CloudKit: it is the line that
            # stops a future capability change turning sync on by accident.
            if symbol == "CloudKit" and "cloudKitDatabase: .none" in source \
                    and not re.search(r"^\s*import\s+CloudKit\b", source, re.M):
                continue
            fail("privacy", f"{relative} references {symbol}")


def check_legal_urls_not_claimed_live() -> None:
    check("Placeholder legal URLs are not presented as live")
    configuration = (APP_SOURCES / "Configuration" / "AppConfiguration.swift").read_text()
    match = re.search(r"legalURLsAreLive\s*=\s*(true|false)", configuration)
    if not match:
        fail("legal-urls", "AppConfiguration.legalURLsAreLive is missing")
        return
    if match.group(1) == "true":
        fail(
            "legal-urls",
            "legalURLsAreLive is true. Only set it once every URL has actually been loaded "
            "and RELEASE_CHECKLIST.md §4 is signed off.",
        )
    for name in ["PrivacyPolicy.md", "TermsOfUse.md"]:
        path = APP_SOURCES / "Resources" / "Legal" / name
        if not path.exists() or len(path.read_text()) < 500:
            fail("legal-urls", f"{name} is missing or too short to be a real document")


# ---------------------------------------------------------------------------------------------
# 5. Accessibility
# ---------------------------------------------------------------------------------------------

def check_accessibility_identifiers_are_used() -> None:
    check("Every declared accessibility identifier is set somewhere")
    declarations = (APP_SOURCES / "SharedUI" / "AccessibilityIdentifiers.swift").read_text()
    names = re.findall(r"static let (\w+)\s*=", declarations)
    usage = "\n".join(
        p.read_text() for p in swift_files(APP_SOURCES, WIDGET_SOURCES) if "AccessibilityIdentifiers" not in p.name
    )
    for name in names:
        if not re.search(rf"\.{name}\b", usage):
            fail("a11y-unused", f"A11yID …{name} is declared but never set on a view")


def check_accessibility_references_resolve() -> None:
    check("Every A11yID reference resolves to a declaration")
    # The other direction from the "declared but never used" check. A reference to a member that
    # no longer exists is a compile error on a Mac, but this repository has no compiler — so the
    # check exists here instead, and catches a rename before somebody spends an afternoon on it.
    source = (APP_SOURCES / "SharedUI" / "AccessibilityIdentifiers.swift").read_text()
    declared: set[str] = set()
    current: str | None = None
    for line in source.splitlines():
        match = re.match(r"\s*enum (\w+) \{", line)
        if match:
            current = match.group(1)
            continue
        match = re.match(r"\s*static (?:let|func) (\w+)", line)
        if match and current:
            declared.add(f"{current}.{match.group(1)}")

    for path in swift_files(APP_SOURCES, WIDGET_SOURCES):
        if path.name == "AccessibilityIdentifiers.swift":
            continue
        for match in re.finditer(r"A11yID\.(\w+)\.(\w+)", path.read_text()):
            reference = f"{match.group(1)}.{match.group(2)}"
            if reference not in declared:
                fail(
                    "a11y-missing",
                    f"{path.relative_to(ROOT)} references A11yID.{reference}, which is not declared",
                )

    # The same, for the UI suite's own copy.
    #
    # `check_ui_test_identifiers_match` below compares the two lists of *strings*, which does not
    # catch a test referencing a member the copy never gained: the string exists on the app side,
    # so the lists agree, and the only thing wrong is a symbol that does not resolve. That is a
    # compile error on a Mac and nothing at all here, which cost a CI round for
    # `A11yUI.Jobsite.none`.
    ui_source = ROOT / "OffRentLedgerUITests" / "A11yUI.swift"
    if ui_source.exists():
        ui_declared: set[str] = set()
        current = None
        for line in ui_source.read_text().splitlines():
            match = re.match(r"\s*enum (\w+) \{", line)
            if match:
                current = match.group(1)
                continue
            match = re.match(r"\s*static (?:let|func) (\w+)", line)
            if match and current:
                ui_declared.add(f"{current}.{match.group(1)}")

        for path in swift_files(ROOT / "OffRentLedgerUITests"):
            if path.name == "A11yUI.swift":
                continue
            for match in re.finditer(r"A11yUI\.(\w+)\.(\w+)", path.read_text()):
                reference = f"{match.group(1)}.{match.group(2)}"
                if reference not in ui_declared:
                    fail(
                        "a11y-missing",
                        f"{path.relative_to(ROOT)} references A11yUI.{reference}, "
                        "which the UI suite's copy does not declare",
                    )


def check_one_identifier_per_modifier_chain() -> None:
    check("No view carries two accessibility identifiers")
    # `.accessibilityIdentifier` sets one property on one element, so a second call on the same
    # modifier chain silently *replaces* the first. Nothing warns, the file compiles, and the
    # identifier that lost appears nowhere in the accessibility tree.
    #
    # `RentalsView` had `rentals.root` on its List and then `rentals.search` on the `.searchable`
    # below it. `rentals.root` was gone, and eleven UI tests failed eight seconds apart saying
    # only "the rentals list never appeared".
    #
    # A chain is found by delimiter depth rather than by indentation: a modifier's trailing
    # closure sits one level deeper, and the first version of this check treated the body of
    # `.safeAreaInset { … }` as the end of the chain — which is precisely how it missed the bug
    # it was written for.
    for path in swift_files(APP_SOURCES, WIDGET_SOURCES):
        lines = path.read_text().splitlines()
        depth = 0
        in_multiline_string = False
        chain: list[int] = []
        base: int | None = None

        def report() -> None:
            marked = [i for i in chain if ".accessibilityIdentifier(" in lines[i]]
            if len(marked) > 1:
                where = ", ".join(str(i + 1) for i in marked)
                fail(
                    "a11y-overwritten",
                    f"{path.relative_to(ROOT)} sets two accessibility identifiers on one view "
                    f"(lines {where}); only the last one survives",
                )

        for index, raw in enumerate(lines):
            stripped = raw.strip()
            fences = stripped.count('"""')
            if in_multiline_string:
                if fences:
                    in_multiline_string = False
                continue
            if fences % 2 == 1:
                in_multiline_string = True
                continue

            depth_before = depth
            code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', raw)
            code = code.split("//", 1)[0]
            depth += sum(code.count(c) for c in "{([") - sum(code.count(c) for c in ")]}")

            if not stripped or stripped.startswith("//"):
                continue
            if base is not None and depth_before > base:
                continue  # inside a modifier's trailing closure — still the same chain
            if stripped.startswith("."):
                if base is None or depth_before != base:
                    report()
                    chain, base = [], depth_before
                chain.append(index)
            else:
                report()
                chain, base = [], None
        report()


def check_container_identifiers_do_not_shadow_children() -> None:
    check("A stack that names itself does not rename its children")
    # An accessibility modifier applied to a *plain layout container* — VStack, HStack, ZStack,
    # Group — is pushed down onto every element inside it. So an identifier meant to name the
    # container instead overwrites the identifier of everything it contains, and the container
    # itself gets no element of its own.
    #
    # This is not theoretical. The operations map's result list carried `map.searchResults`, and
    # the row inside it lost `map.searchResult`: the search ran, the row was on screen with the
    # right label, and two tests waited eight seconds for an element their own parent had
    # renamed. The welcome screen had already hit this once and been fixed; nothing stopped the
    # next one.
    #
    # `.accessibilityElement(children: .contain)` before the identifier is the fix — it makes the
    # view a real container that owns the identifier while its children keep theirs.
    #
    # Deliberately limited to plain stacks. `List`, `Form` and `ScrollView` are backed by UIKit
    # containers that already own an element, and CI dumps show their rows keeping their own
    # identifiers; requiring `.contain` on those would be noise.
    #
    # `Group` is exempt for the same reason rather than by assumption. It is transparent: the
    # modifier is applied to each child, and where those children are scroll containers the
    # identifier lands on them. `RentalItemDetailView` has had exactly that shape since b3057d1,
    # a commit whose UI suite was green while asserting `itemDetail.markDone`,
    # `itemDetail.status` and `itemDetail.disclosure` as separate elements.
    stacks = ("VStack", "HStack", "ZStack")
    declaration = re.compile(
        r"^\s*(?:@\w+\s+)*(?:private |internal |public |fileprivate )?(?:static )?(?:var|func)\s+(\w+)"
    )

    for path in swift_files(APP_SOURCES, WIDGET_SOURCES):
        lines = path.read_text().splitlines()
        depth = 0
        in_multiline_string = False
        open_declarations: list[list] = []

        for index, raw in enumerate(lines):
            stripped = raw.strip()
            if in_multiline_string:
                if '"""' in stripped:
                    in_multiline_string = False
                continue
            if stripped.count('"""') % 2 == 1:
                in_multiline_string = True
                continue

            code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', raw).split("//", 1)[0]
            opens = code.count("{")
            closes = code.count("}")
            before = depth

            match = declaration.match(raw)
            if match and "some View" in raw and opens:
                # name, base depth, root expression, identifier hits, has `.contain`
                open_declarations.append([match.group(1), before, None, [], False])

            if open_declarations:
                current = open_declarations[-1]
                if current[2] is None and before == current[1] + 1 and stripped and not stripped.startswith("//"):
                    current[2] = stripped
                if ".accessibilityIdentifier(" in raw:
                    current[3].append((before - current[1], index + 1))
                if ".accessibilityElement(children: .contain)" in raw and before == current[1] + 1:
                    current[4] = True

            depth += opens - closes
            while open_declarations and depth <= open_declarations[-1][1]:
                name, base, root, hits, contained = open_declarations.pop()
                if contained or not root or not root.startswith(stacks):
                    continue
                outer = [line for relative, line in hits if relative == 1]
                inner = [line for relative, line in hits if relative > 1]
                if outer and inner:
                    fail(
                        "a11y-shadowed",
                        f"{path.relative_to(ROOT)} «{name}» names a plain stack at line "
                        f"{outer[0]}, which overwrites the identifiers set inside it "
                        f"(lines {', '.join(str(line) for line in inner[:4])}). "
                        "Add .accessibilityElement(children: .contain) before it.",
                    )


def check_identifiers_are_set_before_insets() -> None:
    check("A screen names itself before it grows a bar")
    # `.safeAreaInset` and `.overlay` add a whole subtree beside the view they are applied to.
    # An accessibility identifier applied *over* that composition is pushed down into the added
    # subtree too — so a screen root set outside a sticky action bar renames the bar's buttons.
    #
    # `EditRentalView` put `editRental.root` on a `Group` wrapping the form and its save bar. The
    # dump read `Button, identifier: 'editRental.root', label: 'Save changes'`, and the test
    # waited eight seconds for a button that was on screen, enabled, and renamed by its own
    # ancestor. `AddRentalView` had the identifier before its inset all along and was fine.
    #
    # The rule is about *depth*, not order within one chain: an identifier at the top level of a
    # declaration whose inset lives deeper is an identifier applied over that inset. Two
    # modifiers side by side in one chain are fine, because the one written first applies first.
    # Gated on the root expression, the same way the shadowing check is. `NavigationStack`,
    # `ScrollView`, `List`, `Form` and `Button` are backed by things that own an accessibility
    # element, and an identifier set on one of those stays on it: `OperationsMapView` has
    # `map.root` on a `NavigationStack` over a `safeAreaInset`, and CI resolved `map.openRecord`,
    # `map.editRecord` and `map.addLocation` inside that inset in the same run. A plain stack or
    # a `Group` owns nothing, so the identifier goes to whatever it wraps — inset included.
    roots = ("VStack", "HStack", "ZStack", "Group")
    insets = (".safeAreaInset(", ".overlay(")
    declaration = re.compile(
        r"^\s*(?:@\w+\s+)*(?:private |internal |public |fileprivate )?(?:static )?(?:var|func)\s+(\w+)"
    )

    for path in swift_files(APP_SOURCES, WIDGET_SOURCES):
        lines = path.read_text().splitlines()
        depth = 0
        in_multiline_string = False
        open_declarations: list[list] = []

        for index, raw in enumerate(lines):
            stripped = raw.strip()
            if in_multiline_string:
                if '"""' in stripped:
                    in_multiline_string = False
                continue
            if stripped.count('"""') % 2 == 1:
                in_multiline_string = True
                continue

            code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', raw).split("//", 1)[0]
            opens = code.count("{")
            closes = code.count("}")
            before = depth

            match = declaration.match(raw)
            if match and "some View" in raw and opens:
                # name, base depth, root expression, identifier lines, inset lines, `.contain`
                open_declarations.append([match.group(1), before, None, [], [], False])

            if open_declarations:
                current = open_declarations[-1]
                relative = before - current[1]
                if current[2] is None and relative == 1 and stripped and not stripped.startswith("//"):
                    current[2] = stripped
                if ".accessibilityIdentifier(" in raw and relative == 1:
                    current[3].append(index + 1)
                if any(token in raw for token in insets) and relative > 1:
                    current[4].append(index + 1)
                if ".accessibilityElement(children: .contain)" in raw and relative == 1:
                    current[5] = True

            depth += opens - closes
            while open_declarations and depth <= open_declarations[-1][1]:
                name, base, root, identifiers, nested_insets, contained = open_declarations.pop()
                if contained or not identifiers or not nested_insets:
                    continue
                if not root or not root.startswith(roots):
                    continue
                fail(
                    "a11y-over-inset",
                    f"{path.relative_to(ROOT)} «{name}» sets an accessibility identifier at line "
                    f"{identifiers[0]} over a view that grows an inset at line "
                    f"{nested_insets[0]}, so the identifier lands on the inset's contents too. "
                    "Set it on the inner view before the inset, or add "
                    ".accessibilityElement(children: .contain).",
                )


def check_ui_test_identifiers_match() -> None:
    check("The UI suite's identifier copy matches the app's")
    # The UI test target drives the app as a black box and cannot @testable import it, so it
    # keeps its own copy of the identifier strings. Without this check a rename in the app turns
    # into a UI test that times out looking for an element that no longer has that identifier —
    # a failure that reads like a broken feature rather than a stale constant.
    def literals(path: pathlib.Path) -> set[str]:
        found = set(re.findall(r'static let \w+ = "([^"]+)"', path.read_text()))
        # Identifiers are dotted ("today.root"); visible titles are not ("Today"). The UI suite
        # addresses tab-bar buttons by title because `.tabItem` builds the button itself.
        return {value for value in found if "." in value}

    app = literals(APP_SOURCES / "SharedUI" / "AccessibilityIdentifiers.swift")
    ui = literals(ROOT / "OffRentLedgerUITests" / "A11yUI.swift")

    missing = ui - app
    if missing:
        fail(
            "a11y-drift",
            f"the UI suite expects identifiers the app does not declare: {sorted(missing)}",
        )


def check_no_colour_only_status() -> None:
    check("Status is never communicated by colour alone")
    chip = (APP_SOURCES / "SharedUI" / "Components.swift").read_text()
    if "status.displayName" not in chip or "status.symbolName" not in chip:
        fail("a11y-colour", "StatusChip no longer draws both a label and a symbol")


# ---------------------------------------------------------------------------------------------
# 6. Generated artefacts and file validity
# ---------------------------------------------------------------------------------------------

def check_generated_project_is_current() -> None:
    check("project.pbxproj matches its generator")
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "generate_xcodeproj.py"), "--check"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        fail("pbxproj-stale", result.stdout.strip() + result.stderr.strip())


def check_pbxproj_integrity() -> None:
    check("Every pbxproj object reference resolves")
    source = (ROOT / "OffRentLedger.xcodeproj" / "project.pbxproj").read_text()
    defined = set(re.findall(r"^\t\t([0-9A-F]{24}) ", source, re.M))
    referenced = set(re.findall(r"\b([0-9A-F]{24})\b", source))
    dangling = referenced - defined
    if dangling:
        fail("pbxproj", f"references undefined objects: {sorted(dangling)}")
    if source.count("{") != source.count("}"):
        fail("pbxproj", "unbalanced braces")

    for target in ["OffRentLedger", "OffRentLedgerTests", "OffRentLedgerUITests", "OffRentLedgerWidget"]:
        if f"name = {target};" not in source:
            fail("pbxproj", f"target {target} is missing")
    # OffRentShared must be a member of both the app and the widget, or the widget cannot decode
    # the snapshot the app writes and will silently show its placeholder forever.
    if source.count("/* OffRentShared */,") < 3:
        fail("pbxproj", "OffRentShared is not a member of both the app and the widget targets")


def check_slow_type_check_warnings_enabled() -> None:
    check("Debug builds warn about slow type-checking before it becomes fatal")
    # When the Swift type checker gives up it emits a hard error — "unable to type-check this
    # expression in reasonable time" — and stops that file. Found that way, each such expression
    # costs a full CI round. These two frontend flags turn the same condition into a located
    # warning at 300ms, so one build lists every candidate at once. They are the early-warning
    # system for a failure mode this project has already hit, so losing them silently is the
    # thing worth catching.
    source = (ROOT / "OffRentLedger.xcodeproj" / "project.pbxproj").read_text()
    for flag in ["-warn-long-expression-type-checking=300", "-warn-long-function-bodies=300"]:
        if flag not in source:
            fail("slow-typecheck", f"the Debug configuration no longer passes {flag}")

    summariser = (ROOT / "scripts" / "ci" / "summarize_test_log.sh").read_text()
    if "took [0-9]+ms to type-check" not in summariser:
        fail(
            "slow-typecheck",
            "summarize_test_log.sh no longer reports the warnings, so nobody would read them",
        )


def check_scheme_is_shared() -> None:
    check("The scheme is shared and runs both test bundles")
    path = ROOT / "OffRentLedger.xcodeproj" / "xcshareddata" / "xcschemes" / "OffRentLedger.xcscheme"
    if not path.exists():
        fail("scheme", "no shared scheme; CI cannot build with -scheme")
        return
    text = path.read_text()
    for bundle in ["OffRentLedgerTests.xctest", "OffRentLedgerUITests.xctest"]:
        if bundle not in text:
            fail("scheme", f"{bundle} is not in the scheme's Testables")
    if "OffRentLedger.storekit" not in text:
        fail("scheme", "the StoreKit configuration is not referenced; local purchase tests cannot run")


def check_file_validity() -> None:
    check("plists, JSON and XML parse")
    for path in (ROOT / "Config").glob("*.plist"):
        try:
            plistlib.loads(path.read_bytes())
        except Exception as error:
            fail("plist", f"{path.name}: {error}")
    for path in (ROOT / "Config").glob("*.entitlements"):
        try:
            plistlib.loads(path.read_bytes())
        except Exception as error:
            fail("plist", f"{path.name}: {error}")
    for path in ROOT.rglob("*.storekit"):
        try:
            json.loads(path.read_text())
        except Exception as error:
            fail("json", f"{path.name}: {error}")
    for path in ROOT.rglob("*.xcscheme"):
        try:
            xml.dom.minidom.parse(str(path))
        except Exception as error:
            fail("xml", f"{path.name}: {error}")
    for path in (ROOT / "OffRentLedger" / "Resources" / "Assets.xcassets").rglob("Contents.json"):
        try:
            json.loads(path.read_text())
        except Exception as error:
            fail("json", f"{path.relative_to(ROOT)}: {error}")


def check_swift_delimiters_balance() -> None:
    check("Swift sources have balanced delimiters")
    for path in swift_files(APP_SOURCES, SHARED_SOURCES, WIDGET_SOURCES, *TESTS):
        source = path.read_text()
        # Strip comments and string literals before counting, so a brace inside a comment or a
        # regex pattern does not produce a false alarm.
        stripped = re.sub(r'"""(.*?)"""', '""', source, flags=re.S)
        stripped = re.sub(r"#\"(?:[^\"]|\"(?!#))*\"#", '""', stripped)
        stripped = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', stripped)
        stripped = re.sub(r"//[^\n]*", "", stripped)
        stripped = re.sub(r"/\*.*?\*/", "", stripped, flags=re.S)
        for opener, closer, label in [("{", "}", "braces"), ("(", ")", "parens"), ("[", "]", "brackets")]:
            if stripped.count(opener) != stripped.count(closer):
                fail(
                    "swift-delimiters",
                    f"{path.relative_to(ROOT)} has unbalanced {label} "
                    f"({stripped.count(opener)} vs {stripped.count(closer)})",
                )


def check_multiline_string_indentation() -> None:
    check("Multi-line string literals satisfy Swift's indentation rule")
    # Swift requires every line inside a `"""` literal to be indented at least as far as the
    # closing delimiter. `swift test` enforces this for Domain and OffRentShared, which it
    # compiles — but the app layer, the widget and the test targets are compiled only by Xcode,
    # so nothing here checked them.
    #
    # This check exists because a stray `sed` in this repository's own history replaced a string
    # continuation line with a bare `X` at column 0, and every other gate passed: it balanced,
    # it resolved, it was inside a string so no symbol was missing. The first thing to notice was
    # the Xcode build, forty minutes of CI later.
    for path in swift_files(APP_SOURCES, SHARED_SOURCES, WIDGET_SOURCES, *TESTS):
        lines = path.read_text().splitlines()
        inside = False
        opened_at = 0
        body: list[tuple[int, str]] = []

        for number, line in enumerate(lines, start=1):
            if not inside:
                # An opening delimiter ends the line; anything after it would be a single-line
                # literal, which this rule does not apply to.
                if line.rstrip().endswith('"""') and line.count('"""') % 2 == 1:
                    inside = True
                    opened_at = number
                    body = []
                continue

            if line.strip().startswith('"""'):
                closing_indent = len(line) - len(line.lstrip())
                for body_number, body_line in body:
                    if not body_line.strip():
                        continue
                    indent = len(body_line) - len(body_line.lstrip())
                    if indent < closing_indent:
                        fail(
                            "string-indentation",
                            f"{path.relative_to(ROOT)}:{body_number} is indented {indent}, "
                            f"less than the closing delimiter at {closing_indent} "
                            f"(literal opened at line {opened_at})",
                        )
                inside = False
                continue

            body.append((number, line))

        if inside:
            fail(
                "string-indentation",
                f"{path.relative_to(ROOT)}: unterminated multi-line literal opened at {opened_at}",
            )


def check_swiftui_section_forms() -> None:
    check("No Section combines a string title with a header or footer closure")
    # `Section(_ titleKey:content:)` has no header/footer variant, so
    # `Section("Title") { } footer: { }` does not compile — and it fails with three misleading
    # errors ("generic parameter 'Content' could not be inferred") that point at the Section
    # rather than at the footer. Cheap to detect, expensive to diagnose.
    for path in swift_files(APP_SOURCES, WIDGET_SOURCES):
        lines = path.read_text().splitlines()
        for index, line in enumerate(lines):
            if not re.search(r'\bSection\(\s*"', line):
                continue
            depth = 0
            for offset in range(index, min(index + 120, len(lines))):
                depth += lines[offset].count("{") - lines[offset].count("}")
                if offset > index and depth <= 0:
                    break
                if offset > index and re.match(r"\s*\}\s*(footer|header):\s*\{", lines[offset]):
                    fail(
                        "swiftui-section",
                        f"{path.relative_to(ROOT)}:{index + 1} gives Section a string title and "
                        f"a {lines[offset].strip().split(':')[0].lstrip('} ')} closure; use "
                        "`Section { } header: { Text(...) } footer: { }`",
                    )
                    break


def check_sequence_map_on_strings() -> None:
    check("No `.map` applied to a non-optional String property")
    # `someOptional?.name.map { ... }` where `name` is a non-optional String binds to
    # `Sequence.map` — mapping over the characters — and yields `[String]`, not `String?`. It is
    # visually identical to the optional-map idiom beside it. Detected by name, using the
    # non-optional String properties this repository actually declares.
    declarations = "\n".join(
        p.read_text() for p in swift_files(APP_SOURCES / "Persistence", DOMAIN, SHARED_SOURCES)
    )
    non_optional_strings = set(
        re.findall(r"\bvar\s+(\w+)\s*:\s*String\s*(?:=|$)", declarations, re.M)
    ) | set(re.findall(r"\blet\s+(\w+)\s*:\s*String\s*(?:=|$)", declarations, re.M))
    # Anything also declared as String? somewhere is ambiguous; leave those alone.
    optional_strings = set(re.findall(r"\b(?:var|let)\s+(\w+)\s*:\s*String\?", declarations))
    candidates = non_optional_strings - optional_strings
    if not candidates:
        return

    pattern = re.compile(r"\.(" + "|".join(sorted(re.escape(c) for c in candidates)) + r")\.map\s*\{")
    for path in swift_files(APP_SOURCES, WIDGET_SOURCES):
        source = without_comments(path.read_text())
        for match in pattern.finditer(source):
            line = source[: match.start()].count("\n") + 1
            fail(
                "sequence-map",
                f"{path.relative_to(ROOT)}:{line} calls .map on `{match.group(1)}`, a "
                "non-optional String — that is Sequence.map over its characters, not Optional.map",
            )


def check_app_icon() -> None:
    check("The app icon meets Apple's marketing-icon requirements")
    # Both of these are outright App Store rejections, and both are invisible until upload:
    # a marketing icon that is not exactly 1024x1024, or one carrying an alpha channel.
    import struct

    icon = (
        APP_SOURCES / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"
    )
    if not icon.exists():
        fail("app-icon", "AppIcon-1024.png is missing")
        return

    data = icon.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        fail("app-icon", "AppIcon-1024.png is not a PNG")
        return

    width, height, _, colour_type = struct.unpack(">IIBB", data[16:26])
    if (width, height) != (1024, 1024):
        fail("app-icon", f"the icon is {width}x{height}; Apple requires exactly 1024x1024")
    if colour_type in (4, 6):
        fail("app-icon", "the icon has an alpha channel, which the App Store rejects")

    master = ROOT / "marketing" / "AppIcon" / "OffRentLedger-AppIcon-master.png"
    if not master.exists():
        fail("app-icon", "the master artwork is missing from marketing/AppIcon/")

    # The generator must never overwrite real artwork again.
    generator = (ROOT / "scripts" / "generate_assets.py").read_text()
    if "AppIcon-1024.png" in generator and "write_png" in generator:
        fail("app-icon", "generate_assets.py can still draw over the app icon")


def check_ocr_fixtures_exist() -> None:
    check("OCR fixtures are present and synthetic")
    folder = APP_SOURCES / "Resources" / "OCRFixtures"
    fixtures = sorted(folder.glob("*.txt"))
    if len(fixtures) < 5:
        fail("fixtures", f"expected at least 5 OCR fixtures, found {len(fixtures)}")
    readme = folder / "README.md"
    if not readme.exists() or "invented for this repository" not in readme.read_text():
        fail("fixtures", "OCRFixtures/README.md must state that the fixtures are synthetic")


def check_call_sites_resolve() -> None:
    check("Initialiser and static-call sites match their declarations")
    # The app layer has never been compiled. This is the nearest thing available to a type check
    # of our own API surface: every `Type(...)` and `Type.staticFunc(...)` in the repository is
    # matched against the signatures declared in it. See scripts/check_swift_call_sites.py.
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "check_swift_call_sites.py")],
        capture_output=True, text=True, cwd=ROOT,
    )
    if result.returncode != 0:
        detail = [line for line in result.stdout.splitlines() if line.strip().startswith(("Off", "Tests"))]
        fail("call-sites", "; ".join(detail[:6]) or result.stdout.strip()[-400:])


def check_every_ui_suite_actually_runs() -> None:
    """Every UI test class is named in the workflow step that runs UI tests.

    `verify.yml` lists its UI suites with `-only-testing:`, which is deliberate — it keeps the
    step's runtime predictable and its failures attributable. The cost is that a suite added to
    the target and *not* added to that list never runs, and CI stays green while it does nothing.

    That happened: four new suites, twenty-two tests, compiled and shipped and never executed.
    The run reported "Executed 17 tests" and looked exactly like a pass. A test that passes by
    not running is the failure this whole file exists to prevent, so it is checked here.
    """
    check("Every UI test suite is named in the workflow that runs them")
    workflow = ROOT / ".github" / "workflows" / "verify.yml"
    ui_tests = ROOT / "OffRentLedgerUITests"
    if not workflow.exists() or not ui_tests.exists():
        return

    listed = set(re.findall(r"-only-testing:OffRentLedgerUITests/(\w+)", workflow.read_text()))
    for path in swift_files(ui_tests):
        for match in re.finditer(r"^(?:final )?class (\w+): XCTestCase", path.read_text(), re.M):
            suite = match.group(1)
            if suite not in listed:
                fail(
                    "ui-suite-not-run",
                    f"{suite} in {path.relative_to(ROOT)} is never run: add "
                    f"-only-testing:OffRentLedgerUITests/{suite} to verify.yml",
                )

    # And the other direction: a name in the workflow that no longer exists fails the whole step
    # with "no tests matching", after the build.
    declared: set[str] = set()
    for path in swift_files(ui_tests):
        declared.update(re.findall(r"^(?:final )?class (\w+): XCTestCase", path.read_text(), re.M))
    for suite in sorted(listed - declared):
        fail(
            "ui-suite-missing",
            f"verify.yml runs OffRentLedgerUITests/{suite}, which does not exist",
        )


def check_github_workflows() -> None:
    """The two GitHub Actions workflows still do what their names say.

    Carried over from the Codemagic version of this check, and for the same reason. The worst
    kind of green build is a workflow named for TestFlight that archives a correctly signed .ipa
    and stops: it succeeds, reports nothing wrong, and produces no build for anybody to install.
    That is exactly what happened here once, and the first anyone knew was a TestFlight page with
    nothing on it and no email.
    """
    check("The GitHub Actions workflows are internally consistent")
    try:
        import yaml  # noqa: PLC0415
    except ImportError:
        print("      (pyyaml not installed; skipping the parse)")
        return

    workflows = ROOT / ".github" / "workflows"
    verify = workflows / "verify.yml"
    testflight = workflows / "testflight.yml"

    for path in (verify, testflight):
        if not path.exists():
            fail("workflows", f"{path.relative_to(ROOT)} is missing")
            return

    parsed = {}
    for path in (verify, testflight):
        try:
            parsed[path.name] = yaml.safe_load(path.read_text()) or {}
        except Exception as error:
            fail("workflows", f"{path.name} does not parse: {error}")
            return

    # `on:` is YAML 1.1's boolean true, so safe_load gives back the key `True`, not "on". Reading
    # it by the string silently finds nothing and every trigger check below passes vacuously.
    def triggers(document: dict) -> dict:
        return document.get(True) or document.get("on") or {}

    verify_on = triggers(parsed["verify.yml"])
    if "push" not in verify_on and "pull_request" not in verify_on:
        fail("workflows", "verify.yml runs on neither push nor pull_request, so it never gates")

    flight_on = triggers(parsed["testflight.yml"])
    for automatic in ("push", "pull_request", "schedule"):
        if automatic in flight_on:
            fail("workflows", f"testflight.yml would run on {automatic}; publishing stays manual")
    if "workflow_dispatch" not in flight_on:
        fail("workflows", "testflight.yml cannot be run by hand")

    body = testflight.read_text()

    # An archive with no upload is the failure this check exists for. Either uploader counts —
    # `altool` is deprecated and the workflow falls back to xcodebuild's own — but at least one
    # has to be there.
    uploaders = ("altool --upload-app", "Set :destination upload")
    if not any(uploader in body for uploader in uploaders):
        fail("workflows", "testflight.yml is named for TestFlight but never uploads anything")

    # Submission and tester assignment stay human decisions.
    for forbidden in ("--submit-for-review", "submit_for_review", "app-store-review"):
        if forbidden in body:
            fail("workflows", f"testflight.yml contains {forbidden}; submission stays manual")

    # Credentials come from secrets, never from the file. Each one is read under the name this
    # repository actually uses, with the longer alias accepted.
    for names in (
        ("ASC_KEY_ID", "APP_STORE_CONNECT_KEY_ID"),
        ("ASC_ISSUER_ID", "APP_STORE_CONNECT_ISSUER_ID"),
        ("ASC_PRIVATE_KEY", "APP_STORE_CONNECT_PRIVATE_KEY"),
    ):
        if not any(f"secrets.{name}" in body for name in names):
            fail("workflows", f"testflight.yml reads none of {' or '.join(names)} from secrets")
    if "BEGIN PRIVATE KEY" in body:
        fail("workflows", "testflight.yml has a private key in it")

    if (ROOT / "codemagic.yaml").exists():
        fail(
            "workflows",
            "codemagic.yaml is still here alongside the GitHub workflows; two CI systems "
            "watching one repository is two places to look when a build fails",
        )


def check_docs_exist() -> None:
    check("The four required documents exist and are not stubs")
    for name in [
        "PROJECT_SOURCE_OF_TRUTH.md", "IMPLEMENTATION_PLAN.md",
        "TEST_MATRIX.md", "RELEASE_CHECKLIST.md",
    ]:
        path = ROOT / name
        if not path.exists() or len(path.read_text()) < 400:
            fail("docs", f"{name} is missing or a stub")


def main() -> int:
    print("Verifying OffRent Ledger repository invariants\n")
    for function in [
        check_no_corecredit,
        check_banned_phrases,
        check_end_rental_label,
        check_required_disclosure,
        check_launch_screen_is_wired,
        check_every_swift_file_parses,
        check_no_duplicate_top_level_types,
        check_estimates_are_labelled,
        check_domain_is_portable,
        check_status_assignment_is_confined,
        check_display_name_is_centralised,
        check_app_intents_metadata_is_literal,
        check_tests_import_foundation,
        check_tests_do_not_sleep_for_a_result,
        check_decimal_parsing_pins_the_locale,
        check_no_unsafe_unwraps,
        check_fatal_error_is_confined,
        check_no_print,
        check_no_third_party_dependencies,
        check_identifier_consistency,
        check_storekit_products_match,
        check_no_hardcoded_prices,
        check_permission_strings,
        check_planned_urls_are_gated,
        check_text_colours_meet_contrast,
        check_privacy_manifests,
        check_privacy_posture,
        check_legal_urls_not_claimed_live,
        check_accessibility_identifiers_are_used,
        check_accessibility_references_resolve,
        check_ui_test_identifiers_match,
        check_one_identifier_per_modifier_chain,
        check_container_identifiers_do_not_shadow_children,
        check_identifiers_are_set_before_insets,
        check_no_colour_only_status,
        check_generated_project_is_current,
        check_website_is_generated,
        check_pbxproj_integrity,
        check_slow_type_check_warnings_enabled,
        check_scheme_is_shared,
        check_file_validity,
        check_swift_delimiters_balance,
        check_multiline_string_indentation,
        check_swiftui_section_forms,
        check_sequence_map_on_strings,
        check_app_icon,
        check_ocr_fixtures_exist,
        check_saves_are_not_silent,
        check_call_sites_resolve,
        check_every_ui_suite_actually_runs,
        check_github_workflows,
        check_docs_exist,
    ]:
        function()

    print()
    if failures:
        print(f"FAILED — {len(failures)} problem(s) across {checks_run} checks:\n")
        for line in failures:
            print(f"  ✗ {line}")
        return 1
    print(f"PASSED — {checks_run} checks, no problems found.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
