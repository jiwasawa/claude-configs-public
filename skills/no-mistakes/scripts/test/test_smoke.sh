#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

out="$(bash "$NM_SH" bogus 2>&1)"; rc=$?
assert_eq "$rc" "2" "unknown subcommand exits 2"
assert_contains "$out" "usage: nm.sh" "prints usage"
bash "$NM_SH" >/dev/null 2>&1; assert_eq "$?" "2" "no subcommand exits 2"
