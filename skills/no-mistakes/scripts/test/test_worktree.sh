#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

repo="$(mk_repo)"; mk_origin "$repo"
git -C "$repo" checkout -q -b feature
echo a > "$repo/a.txt"; git -C "$repo" add -A; git -C "$repo" commit -qm "feat: a"
base="$(git -C "$repo" rev-parse HEAD)"

obs="$(cd "$repo" && bash "$NM_SH" observe feature)"
assert_contains "$obs" "BASE_SHA $base" "observe reports base sha"
assert_contains "$obs" "REMOTE_SHA" "observe reports remote line"

git -C "$repo" push -q origin feature
obs2="$(cd "$repo" && bash "$NM_SH" observe feature)"
assert_contains "$obs2" "REMOTE_SHA $(git -C "$repo" rev-parse origin/feature)" "observe reports remote sha when present"

wt="$(cd "$repo" && bash "$NM_SH" worktree-add "$base")"
assert_ok test -d "$wt"
assert_eq "$(git -C "$wt" rev-parse HEAD)" "$base" "worktree checked out at base"
assert_fail git -C "$wt" symbolic-ref -q HEAD

echo fix > "$wt/a.txt"; git -C "$wt" add -A; git -C "$wt" commit -qm "fix: x"
fixsha="$(git -C "$wt" rev-parse HEAD)"
( cd "$wt" && bash "$NM_SH" rescue run123 )
assert_eq "$(git -C "$repo" rev-parse refs/no-mistakes/run123)" "$fixsha" "rescue ref points at fix"

( cd "$repo" && bash "$NM_SH" worktree-remove "$wt" )
assert_fail test -d "$wt"
