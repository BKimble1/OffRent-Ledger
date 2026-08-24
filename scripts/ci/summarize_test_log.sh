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
echo "--- What was on screen when an element was not found ---"
# `expect()` prints every identified element and its type when it times out. That answer — is the
# control a StaticText where the test asked for an Other? did the screen appear at all? — is the
# whole of the diagnosis, and it is thousands of lines up in the raw log.
grep -aA 40 "Identified elements on screen:" "$LOG" | head -n 160 || echo "(none)"
echo "--- Compile errors ---"
# Both forms: Swift diagnostics carry a file:line:col, and some (linker, asset catalog,
# code-signing) do not. Missing the second kind is how a build "fails with no errors".
grep -aE '\.swift:[0-9]+(:[0-9]+)?: (error|warning: .*will never be executed)' "$LOG" \
  | head -n 40 || echo "(none with a source location)"
echo "--- Slow type-checking (Debug diagnostic flags) ---"
# The Debug configuration passes -warn-long-expression-type-checking=300 and
# -warn-long-function-bodies=300, so an expression heading for the compiler's hard
# "unable to type-check this expression in reasonable time" error shows up here first, with a
# file and a line, on the build *before* it becomes fatal. Slowest first.
#
# Captured into a variable rather than piped straight to head: `grep ... | head` reports head's
# exit status, so a `|| echo "(none)"` on the pipeline would never fire and an empty section
# would be indistinguishable from a section that was never reached.
SLOW=$(grep -aE '\.swift:[0-9]+:[0-9]+: warning: .*took [0-9]+ms to type-check' "$LOG" \
  | sed -E 's|^.*/([^/]+\.swift:)|\1|' \
  | sort -u \
  | awk '{ ms = 0
           if (match($0, /[0-9]+ms to type-check/)) ms = substr($0, RSTART, RLENGTH - 16) + 0
           print ms "\t" $0 }' \
  | sort -rn \
  | cut -f2- \
  | head -n 25)
if [ -n "$SLOW" ]; then echo "$SLOW"; else echo "(none over the 300ms threshold)"; fi
echo "--- Other errors ---"
grep -aE '^(error|.*: error:)' "$LOG" \
  | grep -avE 'CoreData: error|error: unable to attach DB' \
  | head -n 25 || echo "(none)"
echo "--- Failing build commands ---"
grep -aA6 "The following build commands failed" "$LOG" | head -n 12 || echo "(none)"
echo "--- Run summary ---"
grep -aE "Executed [0-9]+ test|Test run with" "$LOG" | tail -n 5 || echo "(none)"
echo "======================================================="
