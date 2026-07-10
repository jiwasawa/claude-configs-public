#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# pr-existing extracts the first open PR number from gh's JSON output.
( fake_bin gh 'printf "%s" "[{\"number\":42}]"'
  assert_eq "$(bash "$NM_SH" pr-existing feature)" "42" "parses existing PR number" )

# pr-existing empty when none.
( fake_bin gh 'printf "%s" "[]"'
  assert_eq "$(bash "$NM_SH" pr-existing feature)" "" "no PR -> empty" )

# pr-existing empty (not an error) when gh itself fails, e.g. no repo resolved.
( fake_bin gh 'exit 1'
  assert_eq "$(bash "$NM_SH" pr-existing feature)" "" "gh failure -> empty" )

# pr-create forwards flags, title, and the body file.
( argfile="$(mktemp)"
  fake_bin gh "printf '%s\n' \"\$@\" > $argfile"
  df="$(mktemp)"; printf 'body line\n' > "$df"
  assert_ok bash "$NM_SH" pr-create feature main "feat: thing" "$df"
  args="$(cat "$argfile")"
  assert_contains "$args" "--head" "passes head branch"
  assert_contains "$args" "--base" "passes base branch"
  assert_contains "$args" "feat: thing" "passes title"
  assert_contains "$args" "--body-file" "passes body via file"
  assert_contains "$args" "$df" "passes the description file path" )

# pr-create forwards a failing gh exit code.
( fake_bin gh 'exit 7'
  df="$(mktemp)"; echo x > "$df"
  bash "$NM_SH" pr-create feature main t "$df" >/dev/null 2>&1
  assert_eq "$?" "7" "forwards gh failure" )

# pr-update passes number, title, body file.
( argfile="$(mktemp)"
  fake_bin gh "printf '%s\n' \"\$@\" > $argfile"
  df="$(mktemp)"; printf 'updated body\n' > "$df"
  assert_ok bash "$NM_SH" pr-update 42 "feat: edited" "$df"
  args="$(cat "$argfile")"
  assert_contains "$args" "edit" "calls edit"
  assert_contains "$args" "42" "passes number"
  assert_contains "$args" "feat: edited" "passes new title"
  assert_contains "$args" "$df" "passes the body file path" )
