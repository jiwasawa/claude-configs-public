#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
V="$(dirname "$NM_SH")/validate_findings.py"

repo="$(mk_repo)"; mk_origin "$repo"
git -C "$repo" checkout -q -b feature
echo a > "$repo/a.txt"; git -C "$repo" add -A; git -C "$repo" commit -qm "feat: a"
git -C "$repo" push -q origin feature

cd "$repo"
obs="$(bash "$NM_SH" observe feature)"
base="$(echo "$obs" | sed -n 's/^BASE_SHA //p')"
remote="$(echo "$obs" | sed -n 's/^REMOTE_SHA //p')"
wt="$(bash "$NM_SH" worktree-add "$base")"

# Reviewer output validates.
findings='[{"id":"r1","severity":"info","file":"a.txt","line":1,"action":"no-op","description":"fine"}]'
echo "$findings" | python3 "$V" >/dev/null; assert_eq "$?" "0" "findings validate"

# A fix commit, drift-check, lease push.
echo a2 >> "$wt/a.txt"; git -C "$wt" add -A; git -C "$wt" commit -qm "fix: tidy"
( cd "$wt"
  assert_ok bash "$NM_SH" drift-check feature "$base" "$remote"
  assert_ok bash "$NM_SH" push feature "$remote" )
assert_eq "$(git -C "$repo" rev-parse origin/feature)" "$(git -C "$wt" rev-parse HEAD)" "e2e: remote advanced"

# Build a full PR body and assert the required sections.
df="$(mktemp)"
cat > "$df" <<'BODY'
## Intent
add a
## Related issues
None.
## Changed files
- a.txt
## Review findings
r1 info no-op fine
## Fixes applied
fix: tidy
## Checks
format: none -> ok
lint: none -> ok
test: none -> ok
BODY
for h in "## Intent" "## Related issues" "## Changed files" "## Review findings" "## Fixes applied" "## Checks"; do
  assert_contains "$(cat "$df")" "$h" "PR body has $h"
done

# New-PR path: no existing PR -> pr-create invoked.
( cd "$wt"
  calls="$(mktemp)"
  fake_bin gh "printf 'call\n' >> $calls"
  assert_eq "$(bash "$NM_SH" pr-existing feature)" "" "no existing PR"
  assert_ok bash "$NM_SH" pr-create feature main "feat: a" "$df"
  assert_contains "$(cat "$calls")" "call" "pr-create invoked" )

# Existing-PR path: pr-existing returns a number -> pr-update invoked.
( cd "$wt"
  calls="$(mktemp)"
  fake_bin gh 'case "$2" in list) printf "%s" "[{\"number\":9}]" ;; edit) printf "update\n" >> '"$calls"' ;; esac'
  number="$(bash "$NM_SH" pr-existing feature)"
  assert_eq "$number" "9" "finds existing PR number"
  assert_ok bash "$NM_SH" pr-update "$number" "feat: a" "$df"
  assert_contains "$(cat "$calls")" "update" "pr-update invoked" )

( cd "$repo" && bash "$NM_SH" worktree-remove "$wt" )
assert_fail test -d "$wt"
