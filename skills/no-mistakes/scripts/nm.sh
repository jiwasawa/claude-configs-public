#!/usr/bin/env bash
# nm.sh - safety-critical mechanics for the no-mistakes skill.
# Each subcommand is independently testable; see scripts/test/.
set -euo pipefail

NM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

nm_usage() {
  cat >&2 <<'EOF'
usage: nm.sh <subcommand> [args]
subcommands:
  preflight <branch>                         check repo/branch/clean-tree/gh/python3/auth
  config <repo_root>                         print resolved test/lint/format/reviewer
  default-branch                             print the default branch name (origin/HEAD)
  diff-range                                 print "<merge-base>..HEAD"
  observe <branch>                           print "BASE_SHA <sha>" and "REMOTE_SHA <sha-or-empty>"
  worktree-add <base_sha>                    create detached worktree, print its path
  worktree-remove <path>                     remove a worktree
  rescue <run_id>                            create refs/no-mistakes/<run_id> at HEAD
  drift-check <branch> <base_sha> <remote_sha>   exit non-zero if branch or remote drifted
  push <branch> <remote_sha>                 lease-guarded push of HEAD to refs/heads/<branch>
  pr-existing <branch>                       print existing open PR number for head branch, or empty
  pr-create <branch> <default> <title> <descfile>   create the PR
  pr-update <number> <title> <descfile>      refresh an existing PR's title/description
  review-codex <range> <intent_file>         run codex read-only review, print findings JSON
EOF
}

nm_config() {
  local root="$1" file=""
  if [ -f "$root/.no-mistakes.yaml" ]; then
    file="$root/.no-mistakes.yaml"
    [ -f "$root/.no-mistakes.yml" ] && echo "note=duplicate-config" >&2
  elif [ -f "$root/.no-mistakes.yml" ]; then
    file="$root/.no-mistakes.yml"
  fi
  [ -n "$file" ] || return 0
  python3 "$NM_DIR/read_config.py" "$file"
}

nm_default_branch() {
  local d=""
  if d="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"; then
    d="${d#origin/}"
  else
    d=""
  fi
  if [ -z "$d" ]; then
    if git show-ref --verify --quiet refs/remotes/origin/main; then d=main
    elif git show-ref --verify --quiet refs/remotes/origin/master; then d=master
    else d=main; fi
  fi
  echo "$d"
}

nm_preflight() {
  local branch="$1" def origin_url host rest before
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "error: not a git repository" >&2; return 1; }
  def="$(nm_default_branch)"
  if [ "$branch" = "$def" ]; then
    echo "error: on default branch '$def'; create a feature branch (git switch -c <name>)" >&2; return 1
  fi
  if [ -n "$(git status --porcelain)" ]; then
    echo "error: uncommitted changes; commit or stash them before gating" >&2; return 1
  fi
  command -v gh >/dev/null 2>&1 || {
    echo "error: gh not installed; see https://cli.github.com" >&2; return 1; }
  command -v python3 >/dev/null 2>&1 || {
    echo "error: python3 not installed; nm.sh uses it to read config, validate findings, and parse gh JSON output" >&2; return 1; }
  # Check auth for the origin remote's host specifically, not every configured
  # host. A stray unauthenticated entry (e.g. an enterprise host) makes a bare
  # `gh auth status` exit non-zero, which must not fail the gate for a repo
  # hosted elsewhere. Fall back to the global check when origin has no host
  # (e.g. a local-path remote, as in the tests).
  origin_url="$(git remote get-url origin 2>/dev/null || true)"
  host=""
  case "$origin_url" in
    *://*)  # scheme://[user@]host[:port]/path
      rest="${origin_url#*://}"; rest="${rest%%/*}"   # authority only
      rest="${rest#*@}"                               # strip optional user@
      case "$rest" in
        \[*\]*) host="${rest#\[}"; host="${host%%\]*}" ;;  # bracketed IPv6 literal
        *)      host="${rest%%:*}" ;;                       # strip optional :port
      esac ;;
    *)      # scp-like [user@]host:path: a colon with no slash before it
      before="${origin_url%%:*}"
      if [ "$origin_url" != "$before" ] && [ "${before#*/}" = "$before" ]; then
        host="${before##*@}"
      fi ;;
  esac
  if [ -n "$host" ]; then
    gh auth status --hostname "$host" >/dev/null 2>&1 || {
      echo "error: gh not authenticated for $host; run 'gh auth login --hostname $host'" >&2; return 1; }
  else
    gh auth status >/dev/null 2>&1 || {
      echo "error: gh not authenticated; run 'gh auth login'" >&2; return 1; }
  fi
  echo "preflight: ok"
}

nm_diff_range() {
  local def base
  def="$(nm_default_branch)"
  base="$(git merge-base "origin/$def" HEAD 2>/dev/null)" || {
    echo "no merge base with origin/$def" >&2; return 1; }
  echo "$base..HEAD"
}

nm_observe() {
  local branch="$1" base remote
  base="$(git rev-parse "refs/heads/$branch")"
  remote="$(git rev-parse --verify --quiet "refs/remotes/origin/$branch" || true)"
  printf 'BASE_SHA %s\n' "$base"
  printf 'REMOTE_SHA %s\n' "$remote"
}

nm_worktree_add() {
  local base="$1" path
  path="$(mktemp -d)/nm-wt"
  git worktree add -q --detach "$path" "$base"
  echo "$path"
}

nm_worktree_remove() { git worktree remove --force "$1"; rmdir "$(dirname "$1")" 2>/dev/null || true; }
nm_rescue() { git update-ref "refs/no-mistakes/$1" HEAD; }

nm_drift_check() {
  local branch="$1" base="$2" remote="$3" now_local now_remote
  git fetch -q origin || { echo "drift: fetch failed" >&2; return 1; }
  now_local="$(git rev-parse "refs/heads/$branch")"
  if [ "$now_local" != "$base" ]; then
    echo "drift: local $branch moved ($base -> $now_local)" >&2; return 1
  fi
  now_remote="$(git rev-parse --verify --quiet "refs/remotes/origin/$branch" || true)"
  if [ "$now_remote" != "$remote" ]; then
    echo "drift: origin/$branch moved ('$remote' -> '$now_remote')" >&2; return 1
  fi
  return 0
}

nm_push() {
  local branch="$1" remote="${2:-}"
  # Always lease-guarded: an empty expectation means the remote ref must not
  # exist yet, so even first-time branch creation is protected against a ref
  # that appeared between drift-check and this push.
  git push --force-with-lease="refs/heads/$branch:$remote" origin "HEAD:refs/heads/$branch"
}

nm_pr_existing() {
  local branch="$1"
  # Parse the JSON here rather than with gh's --jq, so the extraction is
  # exercised by the tests (which stub gh with a plain script).
  gh pr list --head "$branch" --state open --json number 2>/dev/null \
    | python3 -c '
import json, sys
try:
    prs = json.load(sys.stdin)
except Exception:
    prs = []
if isinstance(prs, list) and prs and isinstance(prs[0], dict) and prs[0].get("number"):
    print(prs[0]["number"])
' || true
}

nm_pr_create() {
  local branch="$1" default="$2" title="$3" descfile="$4"
  gh pr create \
    --head "$branch" \
    --base "$default" \
    --title "$title" \
    --body-file "$descfile"
}

nm_pr_update() {
  local number="$1" title="$2" descfile="$3"
  gh pr edit "$number" --title "$title" --body-file "$descfile"
}

nm_review_codex() {
  local range="$1" intent_file="$2" diff intent prompt raw
  command -v codex >/dev/null 2>&1 || { echo "error: codex not found" >&2; return 3; }
  diff="$(git diff "$range")"
  intent="$(cat "$intent_file")"
  prompt="$(cat <<EOF
You are an independent code reviewer. You did not write this code.
Review the diff below against the stated intent so deliberate choices are not flagged as mistakes.

Output ONLY a JSON array, no prose. Each element has exactly these fields:
{"id":"<unique string>","severity":"error|warning|info","file":"<path or null>","line":<int or null>,"action":"auto-fix|ask-user|no-op","description":"<one or two sentences>"}
action: auto-fix = mechanical and low-risk; ask-user = challenges intent or changes product behavior; no-op = informational.

INTENT:
$intent

DIFF ($range):
$diff
EOF
)"
  # Redirect stdin from /dev/null: `codex exec` otherwise reads additional
  # input from stdin and hangs ("Reading additional input from stdin...")
  # when invoked with an open stdin (e.g. a terminal or pipe).
  raw="$(codex exec -s read-only "$prompt" </dev/null)"
  printf '%s' "$raw" | python3 -c '
import sys, json
s = sys.stdin.read()
dec = json.JSONDecoder()
i = 0
while True:
    k = s.find("[", i)
    if k == -1:
        break
    try:
        val, _ = dec.raw_decode(s[k:])
        if isinstance(val, list):
            sys.stdout.write(json.dumps(val, separators=(",", ":")))
            break
    except Exception:
        pass
    i = k + 1
'
}

main() {
  local cmd="${1:-}"
  [ -n "$cmd" ] || { nm_usage; exit 2; }
  shift
  case "$cmd" in
    config) nm_config "$@" ;;
    default-branch) nm_default_branch ;;
    diff-range) nm_diff_range ;;
    preflight) nm_preflight "$@" ;;
    observe) nm_observe "$@" ;;
    worktree-add) nm_worktree_add "$@" ;;
    worktree-remove) nm_worktree_remove "$@" ;;
    rescue) nm_rescue "$@" ;;
    drift-check) nm_drift_check "$@" ;;
    push) nm_push "$@" ;;
    pr-existing) nm_pr_existing "$@" ;;
    pr-create) nm_pr_create "$@" ;;
    pr-update) nm_pr_update "$@" ;;
    review-codex) nm_review_codex "$@" ;;
    *) nm_usage; exit 2 ;;
  esac
}

main "$@"
