#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

for sub in preflight config default-branch diff-range observe worktree-add \
           worktree-remove rescue drift-check push pr-existing pr-create \
           pr-update review-codex; do
  out="$(bash "$NM_SH" "$sub" 2>&1 || true)"
  case "$out" in
    *"usage: nm.sh"*) _fail "subcommand '$sub' falls through to usage" ;;
    *) _tick ;;
  esac
done
