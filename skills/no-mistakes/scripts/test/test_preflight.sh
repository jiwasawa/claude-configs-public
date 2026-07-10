#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

repo="$(mk_repo)"; mk_origin "$repo"
git -C "$repo" checkout -q -b feature
echo a > "$repo/a.txt"; git -C "$repo" add -A; git -C "$repo" commit -qm "feat: a"

# Happy path: feature branch, clean tree, gh present and authed.
( fake_bin gh 'case "$1 $2" in "auth status") exit 0 ;; *) exit 0 ;; esac'
  out="$(cd "$repo" && bash "$NM_SH" preflight feature 2>&1)"
  assert_contains "$out" "preflight: ok" "preflight ok on feature" )

# On default branch -> error (branch check precedes gh).
( fake_bin gh 'exit 0'
  out="$(cd "$repo" && git checkout -q main && bash "$NM_SH" preflight main 2>&1)"; rc=$?
  assert_eq "$rc" "1" "default branch fails"
  assert_contains "$out" "default branch" "explains default-branch error"
  git -C "$repo" checkout -q feature )

# Dirty tree -> error.
( fake_bin gh 'case "$1 $2" in "auth status") exit 0 ;; *) exit 0 ;; esac'
  echo dirty > "$repo/untracked.txt"
  out="$(cd "$repo" && bash "$NM_SH" preflight feature 2>&1)"; rc=$?
  assert_eq "$rc" "1" "dirty tree fails"
  assert_contains "$out" "uncommitted" "explains dirty error"
  rm -f "$repo/untracked.txt" )

# gh not authed -> error.
( fake_bin gh 'case "$1 $2" in "auth status") exit 1 ;; *) exit 0 ;; esac'
  out="$(cd "$repo" && bash "$NM_SH" preflight feature 2>&1)"; rc=$?
  assert_eq "$rc" "1" "unauthed gh fails"
  assert_contains "$out" "auth login" "explains auth error" )

# gh not installed -> error (PATH has git but no gh).
( gitbin="$(command -v git)"; bashbin="$(command -v bash)"
  pdir="$(nm_tmpd)"; ln -s "$gitbin" "$pdir/git"; ln -s "$bashbin" "$pdir/bash"
  PATH="$pdir"
  out="$(cd "$repo" && bash "$NM_SH" preflight feature 2>&1)"; rc=$?
  assert_eq "$rc" "1" "missing gh fails"
  assert_contains "$out" "not installed" "explains missing-gh error" )

# python3 not installed -> error (PATH has git, bash, gh but no python3).
( gitbin="$(command -v git)"; bashbin="$(command -v bash)"
  pdir="$(nm_tmpd)"; ln -s "$gitbin" "$pdir/git"; ln -s "$bashbin" "$pdir/bash"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$pdir/gh"; chmod +x "$pdir/gh"
  PATH="$pdir"
  out="$(cd "$repo" && bash "$NM_SH" preflight feature 2>&1)"; rc=$?
  assert_eq "$rc" "1" "missing python3 fails"
  assert_contains "$out" "python3" "explains missing-python3 error" )

# Auth is checked for the origin remote's host specifically, so a stray
# unauthenticated host (e.g. an enterprise instance) does not fail the gate.
( orig_url="$(git -C "$repo" remote get-url origin)"
  git -C "$repo" remote set-url origin "ssh://git@ghe.example.test:2222/g/r.git"
  # `auth status` succeeds ONLY when --hostname ghe.example.test is passed.
  fake_bin gh '
    if [ "$1 $2" = "auth status" ]; then
      h=""; shift 2
      while [ $# -gt 0 ]; do [ "$1" = "--hostname" ] && h="$2"; shift; done
      [ "$h" = "ghe.example.test" ] && exit 0 || exit 1
    fi
    exit 0'
  out="$(cd "$repo" && bash "$NM_SH" preflight feature 2>&1)"; rc=$?
  assert_eq "$rc" "0" "preflight ok when origin host is authed"
  assert_contains "$out" "preflight: ok" "reports ok for authed origin host"
  git -C "$repo" remote set-url origin "$orig_url" )

# ...and it fails, naming the host, when that specific host is not authed.
( orig_url="$(git -C "$repo" remote get-url origin)"
  git -C "$repo" remote set-url origin "ssh://git@ghe.example.test:2222/g/r.git"
  fake_bin gh 'case "$1 $2" in "auth status") exit 1 ;; *) exit 0 ;; esac'
  out="$(cd "$repo" && bash "$NM_SH" preflight feature 2>&1)"; rc=$?
  assert_eq "$rc" "1" "preflight fails when origin host unauthed"
  assert_contains "$out" "ghe.example.test" "names the origin host in the error"
  git -C "$repo" remote set-url origin "$orig_url" )

# Local-path remotes (incl. relative ones) have no host, so preflight must use
# the global check, never pass a bogus --hostname derived from the path.
( orig_url="$(git -C "$repo" remote get-url origin)"
  # `auth status` succeeds only when NO --hostname is passed (i.e. global check).
  fake_bin gh '
    if [ "$1 $2" = "auth status" ]; then
      shift 2
      while [ $# -gt 0 ]; do [ "$1" = "--hostname" ] && exit 1; shift; done
      exit 0
    fi
    exit 0'
  for url in "../peer.git" "./sub.git" "repo.git" "/abs/path/repo.git"; do
    git -C "$repo" remote set-url origin "$url"
    out="$(cd "$repo" && bash "$NM_SH" preflight feature 2>&1)"; rc=$?
    assert_eq "$rc" "0" "local-path origin '$url' uses global auth check"
  done
  git -C "$repo" remote set-url origin "$orig_url" )

# Bracketed IPv6 authority is extracted whole, not truncated at the first colon.
( orig_url="$(git -C "$repo" remote get-url origin)"
  git -C "$repo" remote set-url origin "ssh://git@[2001:db8::1]:2222/g/r.git"
  fake_bin gh '
    if [ "$1 $2" = "auth status" ]; then
      h=""; shift 2
      while [ $# -gt 0 ]; do [ "$1" = "--hostname" ] && h="$2"; shift; done
      [ "$h" = "2001:db8::1" ] && exit 0 || exit 1
    fi
    exit 0'
  out="$(cd "$repo" && bash "$NM_SH" preflight feature 2>&1)"; rc=$?
  assert_eq "$rc" "0" "bracketed IPv6 origin host parsed whole"
  git -C "$repo" remote set-url origin "$orig_url" )
