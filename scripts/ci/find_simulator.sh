#!/bin/bash
# Prints the UDID of an available iPhone simulator, newest runtime first.
#
# The device is *discovered* rather than named, because the runner's simulator set changes with
# every Xcode image. Hard-coding "iPhone 15 Pro" fails the day that model is dropped, and it fails
# as an unhelpful "destination not found" rather than as anything actionable. Any iPhone will do:
# these are unit and workflow tests with no device-specific behaviour.
set -euo pipefail

LIST=$(xcrun simctl list devices available)

# simctl groups devices under runtime headings like "-- iOS 18.2 --". Take the last iOS section,
# which is the newest runtime, and the first iPhone in it.
UDID=$(printf '%s\n' "$LIST" \
  | awk '/^-- iOS/ { section = 1; buffer = ""; next }
         /^-- / { section = 0 }
         section { buffer = buffer $0 "\n" }
         END { printf "%s", buffer }' \
  | grep -E 'iPhone' \
  | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
  | tail -n 1)

if [ -z "${UDID:-}" ]; then
  # Fall back to any available iPhone in any section before giving up.
  UDID=$(printf '%s\n' "$LIST" \
    | grep -E 'iPhone' \
    | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
    | tail -n 1)
fi

if [ -z "${UDID:-}" ]; then
  echo "No available iPhone simulator was found on this runner." >&2
  printf '%s\n' "$LIST" >&2
  exit 1
fi

printf '%s' "$UDID"
