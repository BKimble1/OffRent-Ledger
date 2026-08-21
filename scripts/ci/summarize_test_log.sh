#!/bin/bash
# Reprints every failure at the end of a test log.
#
# The log runs to tens of thousands of lines and the CI view shows only its tail, which is
# whichever tests happened to finish last — usually passes. Without this, a red build says
# "3 issues" and hides all three.
#
# Matched on ASCII markers rather than on Swift Testing's U+2718 glyph: macOS ships bash 3.2,
# which does not understand $'\uXXXX' escapes. A bare "error:" is not usable either — CoreData
# logs hundreds of "CoreData: error:" diagnostics on a perfectly healthy run and they crowd out
# the real results.
LOG="${1:?usage: summarize_test_log.sh <logfile>}"

echo ""
echo "================= TEST FAILURE SUMMARY ================="
echo "--- Recorded test issues (Swift Testing) ---"
grep -a "recorded an issue" "$LOG" | head -n 60 || echo "(none)"
echo "--- Failing test cases (XCTest) ---"
grep -aE "^Test Case .* failed" "$LOG" | head -n 40 || echo "(none)"
echo "--- Compile errors ---"
# Both forms: Swift diagnostics carry a file:line:col, and some (linker, asset catalog,
# code-signing) do not. Missing the second kind is how a build "fails with no errors".
grep -aE '\.swift:[0-9]+(:[0-9]+)?: (error|warning: .*will never be executed)' "$LOG" \
  | head -n 40 || echo "(none with a source location)"
echo "--- Other errors ---"
grep -aE '^(error|.*: error:)' "$LOG" \
  | grep -avE 'CoreData: error|error: unable to attach DB' \
  | head -n 25 || echo "(none)"
echo "--- Failing build commands ---"
grep -aA6 "The following build commands failed" "$LOG" | head -n 12 || echo "(none)"
echo "--- Run summary ---"
grep -aE "Executed [0-9]+ test|Test run with" "$LOG" | tail -n 5 || echo "(none)"
echo "======================================================="
