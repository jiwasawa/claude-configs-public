#!/usr/bin/env bash
# Test helpers. Source from each test_*.sh. Counters are file-based so that
# assertions inside ( ... ) subshells still register in the totals.
set -uo pipefail

: "${NM_RUN_LOG:=/dev/null}"
: "${NM_FAIL_LOG:=/dev/null}"

_tick() { printf '.' >> "$NM_RUN_LOG"; }
_fail() { printf '%s\n' "$1" >> "$NM_FAIL_LOG"; echo "  FAIL: $1" >&2; }

assert_eq() { _tick; [ "$1" = "$2" ] || _fail "$3 (got '$1' want '$2')"; }
assert_contains() { _tick; case "$1" in *"$2"*) : ;; *) _fail "$3 ('$1' lacks '$2')" ;; esac; }
assert_ok() { _tick; if ! "$@" >/dev/null 2>&1; then _fail "expected success: $*"; fi; }
assert_fail() { _tick; if "$@" >/dev/null 2>&1; then _fail "expected failure: $*"; fi; }

NM_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/nm.sh"

_git_id() { git -C "$1" config user.email t@t.t; git -C "$1" config user.name t; }

# Fail closed when mktemp cannot provide a directory. Tests run without set -e,
# so a bare mktemp failure would hand callers an empty path and git -C "" /
# cd "" would then operate on the caller's real repo. Instead, record the
# failure and return a path that does not exist, so every downstream git/cd
# call errors out harmlessly.
nm_tmpd() {
  local d
  if d="$(mktemp -d 2>/dev/null)" && [ -n "$d" ]; then
    printf '%s\n' "$d"
  else
    _fail "mktemp -d failed (TMPDIR misconfigured?); test cannot run"
    printf '/nm-no-tmpdir-%s\n' "$$"
    return 1
  fi
}

mk_repo() {
  local d; d="$(nm_tmpd)"
  git -C "$d" init -q -b main
  _git_id "$d"
  echo seed > "$d/seed.txt"
  git -C "$d" add -A
  git -C "$d" commit -qm "chore: seed"
  echo "$d"
}

mk_origin() {
  local repo="$1" bare
  bare="$(nm_tmpd)/origin.git"
  git init -q --bare "$bare"
  git -C "$repo" remote add origin "$bare"
  git -C "$repo" push -q origin main
  git -C "$bare" symbolic-ref HEAD refs/heads/main
  git -C "$repo" remote set-head origin main
}

mk_clone() {
  local repo="$1" url dir
  url="$(git -C "$repo" remote get-url origin)"
  dir="$(nm_tmpd)/clone"
  git clone -q "$url" "$dir"
  _git_id "$dir"
  echo "$dir"
}

fake_bin() {
  local name="$1" body="$2" dir
  dir="$(nm_tmpd)"
  printf '#!/usr/bin/env bash\n%s\n' "$body" > "$dir/$name"
  chmod +x "$dir/$name"
  PATH="$dir:$PATH"
}
