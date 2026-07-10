#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

d="$(nm_tmpd)"
cat > "$d/.no-mistakes.yaml" <<'YAML'
# project config
commands:
  test: "go test ./..."   # race not needed here
  lint: 'make lint'
  format: gofmt -w .
reviewer: codex
other:
  test: "SHOULD NOT BE READ"
YAML
out="$(bash "$NM_SH" config "$d")"
assert_contains "$out" "test=go test ./..." "reads quoted test, strips comment"
assert_contains "$out" "lint=make lint" "reads single-quoted lint"
assert_contains "$out" "format=gofmt -w ." "reads bare format"
assert_contains "$out" "reviewer=codex" "reads reviewer"
case "$out" in *"SHOULD NOT BE READ"*) _fail "leaked a non-commands key" ;; *) _tick ;; esac

e="$(nm_tmpd)"
printf 'commands:\n  test: "pytest"\n' > "$e/.no-mistakes.yml"
assert_contains "$(bash "$NM_SH" config "$e")" "test=pytest" "reads .yml fallback"

b="$(nm_tmpd)"
printf 'reviewer: both\n' > "$b/.no-mistakes.yaml"
assert_contains "$(bash "$NM_SH" config "$b")" "reviewer=both" "reads reviewer: both"

f="$(nm_tmpd)"
out3="$(bash "$NM_SH" config "$f")"; rc=$?
assert_eq "$rc" "0" "no config exits 0"
assert_eq "$out3" "" "no config prints nothing"

g="$(nm_tmpd)"
printf 'commands:\n  test: "from-yaml"\n' > "$g/.no-mistakes.yaml"
printf 'commands:\n  test: "from-yml"\n' > "$g/.no-mistakes.yml"
out_dup="$(bash "$NM_SH" config "$g" 2>/dev/null)"
err_dup="$(bash "$NM_SH" config "$g" 2>&1 1>/dev/null)"
assert_contains "$out_dup" "test=from-yaml" "duplicate config: .yaml wins"
assert_contains "$err_dup" "note=duplicate-config" "duplicate config: warns on stderr"
