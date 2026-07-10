#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

repo="$(mk_repo)"; mk_origin "$repo"
git -C "$repo" checkout -q -b feature
echo a > "$repo/a.txt"; git -C "$repo" add -A; git -C "$repo" commit -qm "feat: a"

assert_eq "$(cd "$repo" && bash "$NM_SH" default-branch)" "main" "default branch resolves to main"
base="$(git -C "$repo" merge-base origin/main HEAD)"
assert_eq "$(cd "$repo" && bash "$NM_SH" diff-range)" "$base..HEAD" "diff-range is merge-base..HEAD"
