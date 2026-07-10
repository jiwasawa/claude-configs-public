#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

setup() { # echoes "repo wt base remote"
  local repo wt base remote
  repo="$(mk_repo)"; mk_origin "$repo"
  git -C "$repo" checkout -q -b feature
  echo a > "$repo/a.txt"; git -C "$repo" add -A; git -C "$repo" commit -qm "feat: a"
  git -C "$repo" push -q origin feature
  base="$(git -C "$repo" rev-parse HEAD)"
  remote="$(git -C "$repo" rev-parse origin/feature)"
  wt="$(cd "$repo" && bash "$NM_SH" worktree-add "$base")"
  echo fix > "$wt/a.txt"; git -C "$wt" add -A; git -C "$wt" commit -qm "fix: x"
  echo "$repo $wt $base $remote"
}

# Happy path: no drift, lease push succeeds.
read -r repo wt base remote <<<"$(setup)"
assert_ok bash -c "cd '$wt' && bash '$NM_SH' drift-check feature '$base' '$remote'"
assert_ok bash -c "cd '$wt' && bash '$NM_SH' push feature '$remote'"
assert_eq "$(git -C "$repo" rev-parse origin/feature)" "$(git -C "$wt" rev-parse HEAD)" "remote advanced to fix"

# Out-of-band fast-forward advance -> drift-check fails, push refuses.
read -r repo2 wt2 base2 remote2 <<<"$(setup)"
clone="$(mk_clone "$repo2")"
git -C "$clone" checkout -q feature
echo other > "$clone/o.txt"; git -C "$clone" add -A; git -C "$clone" commit -qm "feat: other"
git -C "$clone" push -q origin feature
assert_fail bash -c "cd '$wt2' && bash '$NM_SH' drift-check feature '$base2' '$remote2'"
assert_fail bash -c "cd '$wt2' && bash '$NM_SH' push feature '$remote2'"

# Divergent remote (force-pushed elsewhere) -> lease must refuse.
read -r repo3 wt3 base3 remote3 <<<"$(setup)"
clone3="$(mk_clone "$repo3")"
git -C "$clone3" checkout -q feature
git -C "$clone3" commit -q --amend -m "feat: a (rewritten)"
git -C "$clone3" push -q --force origin feature
assert_fail bash -c "cd '$wt3' && bash '$NM_SH' push feature '$remote3'"

# New branch: empty remote_sha -> plain push creates it.
repo4="$(mk_repo)"; mk_origin "$repo4"
git -C "$repo4" checkout -q -b brandnew
echo n > "$repo4/n.txt"; git -C "$repo4" add -A; git -C "$repo4" commit -qm "feat: n"
base4="$(git -C "$repo4" rev-parse HEAD)"
wt4="$(cd "$repo4" && bash "$NM_SH" worktree-add "$base4")"
assert_ok bash -c "cd '$wt4' && bash '$NM_SH' push brandnew ''"
assert_eq "$(git -C "$repo4" rev-parse origin/brandnew)" "$base4" "new branch pushed"
