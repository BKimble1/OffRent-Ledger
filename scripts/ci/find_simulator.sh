#!/bin/bash
# Prints the UDID of an available simulator, newest runtime first.
#
#   find_simulator.sh            # an iPhone (the default)
#   find_simulator.sh iPad       # an iPad
#
# The device is *discovered* rather than named, because the runner's simulator set changes with
# every Xcode image. Hard-coding "iPhone 15 Pro" fails the day that model is dropped, and it fails
# as an unhelpful "destination not found" rather than as anything actionable. Any device of the
# requested family will do: the tests are written against the app's own accessibility identifiers
# and its layout rules, not against a model.
#
# Asking for an iPad and silently getting an iPhone would be worse than failing, so there is no
# cross-family fallback: `IPadLayoutUITests` would then run letterboxed and pass nothing
# meaningful. This exits non-zero instead, and `IPadLayoutUITests` asserts the window size again
# on the other side in case a destination is ever hard-coded past this script.
set -euo pipefail

FAMILY="${1:-iPhone}"
case "$FAMILY" in
  iPhone|iPad) ;;
  *) echo "Unknown simulator family '$FAMILY'. Use iPhone or iPad." >&2; exit 2 ;;
esac

LIST=$(xcrun simctl list devices available)

# simctl groups devices under runtime headings like "-- iOS 18.2 --". Take the last iOS section,
# which is the newest runtime, and the last device of the requested family in it.
UDID=$(printf '%s\n' "$LIST" \
  | awk '/^-- iOS/ { section = 1; buffer = ""; next }
         /^-- / { section = 0 }
         section { buffer = buffer $0 "\n" }
         END { printf "%s", buffer }' \
  | grep -E "$FAMILY" \
  | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
  | tail -n 1)

if [ -z "${UDID:-}" ]; then
  # Fall back to any available device of the same family in any section before giving up.
  UDID=$(printf '%s\n' "$LIST" \
    | grep -E "$FAMILY" \
    | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
    | tail -n 1)
fi

if [ -z "${UDID:-}" ]; then
  echo "No available $FAMILY simulator was found on this runner." >&2
  printf '%s\n' "$LIST" >&2
  exit 1
fi

printf '%s' "$UDID"
