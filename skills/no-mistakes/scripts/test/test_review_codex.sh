#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

repo="$(mk_repo)"; mk_origin "$repo"
git -C "$repo" checkout -q -b feature
echo a > "$repo/a.txt"; git -C "$repo" add -A; git -C "$repo" commit -qm "feat: a"
intent="$(mktemp)"; echo "add a" > "$intent"

( cd "$repo"
  fake_bin codex 'echo "[info] running"; echo "[{\"id\":\"r1\",\"severity\":\"info\",\"file\":null,\"line\":null,\"action\":\"no-op\",\"description\":\"ok\"}]"'
  out="$(bash "$NM_SH" review-codex "$(bash "$NM_SH" diff-range)" "$intent")"
  assert_eq "${out:0:1}" "[" "extracted JSON starts with ["
  assert_contains "$out" '"id":"r1"' "contains the finding (compact)"
  echo "$out" | python3 -c "import json,sys; json.load(sys.stdin)" && ok=yes || ok=no
  assert_eq "$ok" "yes" "extracted output is valid JSON" )

( cd "$repo"
  PATH="/usr/bin:/bin"
  bash "$NM_SH" review-codex "HEAD~1..HEAD" "$intent" >/dev/null 2>&1
  assert_eq "$?" "3" "missing codex exits 3" )

# Regression: codex exec must redirect stdin from /dev/null, else it reads
# additional input from stdin and hangs when invoked with an open stdin.
assert_ok grep -qF 'codex exec -s read-only "$prompt" </dev/null' "$NM_SH"

# Functional guard: a codex that reads all of stdin must still complete, i.e.
# it must see EOF immediately. Feed review-codex an open stdin (a pipe) and a
# fake codex that drains stdin before printing; if stdin were inherited it
# would block forever, so a bounded background wait catches a regression.
( cd "$repo"
  set -m  # own process group per background job, so a hang can be reaped whole
  fake_bin codex 'cat >/dev/null; echo "[{\"id\":\"r1\",\"severity\":\"info\",\"file\":null,\"line\":null,\"action\":\"no-op\",\"description\":\"ok\"}]"'
  fifo="$(mktemp -u)"; mkfifo "$fifo"; exec 9<>"$fifo"
  out=""; done_ok=no
  bash "$NM_SH" review-codex "HEAD~1..HEAD" "$intent" <&9 > "$fifo.out" 2>/dev/null &
  pid=$!
  for _ in 1 2 3 4 5; do
    sleep 1
    kill -0 "$pid" 2>/dev/null || { done_ok=yes; break; }
  done
  if [ "$done_ok" = yes ]; then
    wait "$pid"; out="$(cat "$fifo.out")"
  else
    # Regression path: kill the whole process group (reviewer + fake codex + its
    # blocked `cat`, which all hold the FIFO's read/write fd) and reap it, so a
    # hang leaves no orphaned processes behind.
    kill -- -"$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  fi
  exec 9>&-; rm -f "$fifo" "$fifo.out"
  assert_eq "$done_ok" "yes" "review-codex does not hang on an open stdin"
  assert_contains "$out" '"id":"r1"' "review-codex returns findings with open stdin" )
