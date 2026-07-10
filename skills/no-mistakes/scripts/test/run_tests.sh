#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# Refuse to run at all if temp files are unavailable: tests build throwaway
# repos under mktemp, and running without it risks touching the real repo.
run_log="$(mktemp)" && fail_log="$(mktemp)" && tmpd_probe="$(mktemp -d)" && rmdir "$tmpd_probe" || {
  echo "fatal: mktemp failed (TMPDIR misconfigured?); refusing to run tests" >&2
  exit 1
}
export NM_RUN_LOG="$run_log" NM_FAIL_LOG="$fail_log"
for t in "$here"/test_*.sh; do
  [ -e "$t" ] || continue
  echo "== $(basename "$t")"
  # shellcheck disable=SC1090
  ( source "$t" ) || true
done
run="$(wc -c < "$run_log" | tr -d '[:space:]')"
failed="$(wc -l < "$fail_log" | tr -d '[:space:]')"
rm -f "$run_log" "$fail_log"
echo "---"
echo "asserts: $run, failed: $failed"
[ "$failed" -eq 0 ]
