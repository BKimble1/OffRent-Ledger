#!/usr/bin/env bash
#
# Captures the six App Store screenshots from a running build of the app.
#
# It boots a 6.9-inch iPhone simulator, runs `AppStoreCaptureUITests` against it, and pulls the
# screenshots out of the result bundle into `marketing/screenshots/`. The seventh opening —
# template 2's front device, a real Home Screen with the widget on it — is not produced here and
# cannot be; see `marketing/screenshots/README.md`.
#
# Requires macOS with Xcode. Everything it depends on is already in this repository: the fixture
# (`-offrent-seed-appstore`), the frozen clock, and the UI suite that drives the screens.
#
# Usage:
#     bash scripts/capture_appstore_screenshots.sh
#     bash scripts/capture_appstore_screenshots.sh "iPhone 16 Pro Max"
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT="OffRentLedger.xcodeproj"
SCHEME="OffRentLedger"
SUITE="OffRentLedgerUITests/AppStoreCaptureUITests"
OUTPUT="marketing/screenshots"
RESULTS="build/appstore-capture.xcresult"

# The 6.9-inch iPhone. Its portrait screenshots are 1290 x 2796, which is the App Store size and
# the template size — so a capture drops into an opening with a uniform resize and no cropping.
# Any other model needs the placement guide's scale factors recomputed, which is why this is a
# named default rather than "whatever booted".
PREFERRED_DEVICES=(
  "iPhone 16 Pro Max"
  "iPhone 17 Pro Max"
  "iPhone 16 Plus"
)

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This needs macOS and Xcode: it boots an iOS simulator." >&2
  echo "Everything else — the fixture, its tests, the templates, the validator — runs anywhere." >&2
  exit 1
fi

DEVICE_NAME="${1:-}"
if [ -z "$DEVICE_NAME" ]; then
  for candidate in "${PREFERRED_DEVICES[@]}"; do
    if xcrun simctl list devices available | grep -q "^ *${candidate} ("; then
      DEVICE_NAME="$candidate"
      break
    fi
  done
fi

if [ -z "$DEVICE_NAME" ]; then
  echo "No 6.9-inch iPhone simulator is installed. Install one of:" >&2
  printf '  %s\n' "${PREFERRED_DEVICES[@]}" >&2
  echo "Xcode > Settings > Platforms, or pass a device name as the first argument." >&2
  exit 1
fi

DEVICE_ID=$(
  xcrun simctl list devices available \
    | grep "^ *${DEVICE_NAME} (" \
    | head -1 \
    | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
)

if [ -z "$DEVICE_ID" ]; then
  echo "Could not resolve a device id for \"${DEVICE_NAME}\"." >&2
  exit 1
fi

echo "Capturing on ${DEVICE_NAME} (${DEVICE_ID})"

# A cold, known simulator. `erase` is what makes the run repeatable: the app's on-disk store, its
# App Group snapshot and its UserDefaults all survive an ordinary reinstall, so without this the
# second capture session inherits the first one's onboarding flags and widget snapshot.
xcrun simctl shutdown "$DEVICE_ID" >/dev/null 2>&1 || true
xcrun simctl erase "$DEVICE_ID"
xcrun simctl boot "$DEVICE_ID"
xcrun simctl bootstatus "$DEVICE_ID" -b

# A status bar that says the same thing in every screenshot. Apple's own marketing convention,
# and without it the six frames carry six different clocks and three different battery levels.
xcrun simctl status_bar "$DEVICE_ID" override \
  --time "9:41" \
  --dataNetwork "wifi" \
  --wifiMode "active" \
  --wifiBars 3 \
  --cellularMode "active" \
  --cellularBars 4 \
  --batteryState "charged" \
  --batteryLevel 100

rm -rf "$RESULTS"
mkdir -p build "$OUTPUT"

set +e
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "id=$DEVICE_ID" \
  -only-testing:"$SUITE" \
  -resultBundlePath "$RESULTS" \
  CODE_SIGNING_ALLOWED=NO \
  | tee build/appstore-capture.log
STATUS=${PIPESTATUS[0]}
set -e

bash scripts/ci/summarize_test_log.sh build/appstore-capture.log || true

if [ "$STATUS" -ne 0 ]; then
  echo "The capture run failed. No screenshot was written; the previous ones are untouched." >&2
  exit "$STATUS"
fi

echo
echo "Extracting screenshots from the result bundle"

STAGING="build/appstore-capture-attachments"
rm -rf "$STAGING"
mkdir -p "$STAGING"

# `xcresulttool export attachments` is the modern spelling; older Xcodes need `--legacy`, and
# older ones still have no `export` verb at all. Each fallback is tried in turn rather than the
# newest being assumed, because "unrecognised argument" here is a run that has already spent five
# minutes booting a simulator.
if xcrun xcresulttool export attachments \
      --path "$RESULTS" --output-path "$STAGING" >/dev/null 2>&1; then
  :
elif xcrun xcresulttool export attachments --legacy \
      --path "$RESULTS" --output-path "$STAGING" >/dev/null 2>&1; then
  :
else
  echo "xcresulttool could not export the attachments from $RESULTS." >&2
  echo "Open it in Xcode (Window > Organizer, or 'open $RESULTS'), find the six screenshots on" >&2
  echo "the test's report, and drag them into $OUTPUT/ under the names in the placement guide." >&2
  exit 1
fi

# The attachments come out under generated names with a manifest mapping them back to the names
# the test gave them. Match on the manifest, not on the order they happen to be written in.
python3 - "$STAGING" "$OUTPUT" <<'PYEOF'
import json
import pathlib
import shutil
import sys

staging = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)

manifests = list(staging.rglob("manifest.json"))
wanted = [
    "appstore-01-today",
    "appstore-02-rentals",
    "appstore-03-off-rent-proof",
    "appstore-04-operations-map",
    "appstore-05-scan-review",
    "appstore-06-invoice-review",
]

found: dict[str, pathlib.Path] = {}
for manifest in manifests:
    entries = json.loads(manifest.read_text())
    for test in entries if isinstance(entries, list) else [entries]:
        for attachment in test.get("attachments", []):
            name = attachment.get("suggestedHumanReadableName") or attachment.get("name") or ""
            exported = attachment.get("exportedFileName")
            if not exported:
                continue
            stem = pathlib.Path(name).stem
            if stem in wanted:
                found[stem] = manifest.parent / exported

# Some Xcode versions write the attachment out under its own name and no manifest at all.
for candidate in staging.rglob("*.png"):
    stem = candidate.stem
    if stem in wanted:
        found.setdefault(stem, candidate)

missing = [name for name in wanted if name not in found]
for name in wanted:
    source = found.get(name)
    if source is None or not source.exists():
        continue
    shutil.copyfile(source, output / f"{name}.png")
    print(f"  wrote {output / f'{name}.png'}")

if missing:
    print()
    print("MISSING: " + ", ".join(missing))
    print("The run did not attach these. Open the result bundle and check what the test saw.")
    sys.exit(1)
PYEOF

echo
echo "Six app captures are in $OUTPUT/."
echo
echo "Still to do by hand — it cannot be automated and must not be drawn:"
echo "  $OUTPUT/appstore-02-home-screen-widget.png"
echo "  A real iOS Home Screen with the medium OffRent Summary widget on it."
echo "  Step-by-step: $OUTPUT/README.md"
echo
echo "Then: python3 scripts/validate_appstore_templates.py"
