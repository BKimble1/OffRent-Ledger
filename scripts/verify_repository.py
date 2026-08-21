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
        "StoreKit/README.md", "codemagic.yaml",
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
]


def check_banned_phrases() -> None:
    check("No phrase claiming the app contacted a vendor or ended a rental")
    for path in swift_files(APP_SOURCES, SHARED_SOURCES, WIDGET_SOURCES):
        relative = path.relative_to(ROOT).as_posix()
        for literal in string_literals(path.read_text(errors="ignore")):
            lowered = literal.lower()
            for phrase in BANNED_PHRASES:
                if phrase in lowered:
                    fail("banned-phrase", f"{relative} string contains {phrase!r}")

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


def check_status_assignment_is_confined() -> None:
    check("Only RentalWorkflowService assigns rental status")
    allowed = {
        "OffRentLedger/Persistence/RentalWorkflowService.swift",
        "OffRentLedger/Persistence/SchemaV1.swift",  # the property's own declaration and init
    }
    # `=` and not `==`: a predicate comparing the column is a read, not an assignment. And the
    # discrepancy model's own status is deliberately named `discrepancyStatusRaw` so that this
    # pattern means one thing only.
    pattern = re.compile(r"\.statusRaw\s*=(?!=)")
    for path in swift_files(APP_SOURCES, WIDGET_SOURCES):
        relative = path.relative_to(ROOT).as_posix()
        if relative in allowed:
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
    required = {
        "NSCameraUsageDescription": "VNDocumentCameraViewController",
        "NSLocationWhenInUseUsageDescription": "CLLocationManager",
        "NSPhotoLibraryAddUsageDescription": None,
    }
    for key in required:
        if key not in info:
            fail("permissions", f"Info.plist is missing {key}")

    # And the reverse: no purpose string for a capability that is not used, which App Review
    # treats as a red flag.
    sources = "\n".join(without_comments(p.read_text()) for p in swift_files(APP_SOURCES, WIDGET_SOURCES))
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
        check_estimates_are_labelled,
        check_domain_is_portable,
        check_status_assignment_is_confined,
        check_display_name_is_centralised,
        check_no_unsafe_unwraps,
        check_fatal_error_is_confined,
        check_no_print,
        check_no_third_party_dependencies,
        check_identifier_consistency,
        check_storekit_products_match,
        check_no_hardcoded_prices,
        check_permission_strings,
        check_privacy_posture,
        check_legal_urls_not_claimed_live,
        check_accessibility_identifiers_are_used,
        check_accessibility_references_resolve,
        check_ui_test_identifiers_match,
        check_no_colour_only_status,
        check_generated_project_is_current,
        check_pbxproj_integrity,
        check_scheme_is_shared,
        check_file_validity,
        check_swift_delimiters_balance,
        check_ocr_fixtures_exist,
        check_call_sites_resolve,
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
