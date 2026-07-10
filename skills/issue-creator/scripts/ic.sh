#!/usr/bin/env bash
# ic.sh - mechanical GitHub plumbing for the issue-creator skill.
# The skill decides *what* to file; this script does the parts that must be
# exact and repeatable: resolving the GitHub repo from the origin remote,
# searching for duplicates, ensuring a label exists, and creating the issue.
# Keeping them here means the outward-facing `gh` calls are written once and
# behave the same every run. Each subcommand is small and independently usable.
set -euo pipefail

ic_usage() {
  cat >&2 <<'EOF'
usage: ic.sh <subcommand> [args]
subcommands:
  preflight                         verify git repo + gh installed + origin is an authenticated GitHub remote; print "repo=<host/owner/repo>"
  repo                              print the GitHub repo ref "<host>/<owner>/<repo>" derived from origin
  search "<query>"                  print open issues matching <query> (JSON array of {number,title,url}) for duplicate detection
  ensure-label "<name>" ["<color>"] create the label if the repo lacks it (color defaults by name; #428BCA otherwise)
  create "<title>" <descfile> ["<label>"]   create the issue from title + description file (+ optional label); print its web URL
EOF
}

# Parse a git remote URL into IC_HOST and IC_PATH (owner/repo, no .git).
# Handles scheme://[user@]host[:port]/path, scp-like [user@]host:path, and
# bracketed IPv6 literals - the same forms nm.sh handles, kept in sync on purpose.
ic_parse_remote() {
  local url="$1" rest authority path before
  IC_HOST=""; IC_PATH=""
  case "$url" in
    *://*)
      rest="${url#*://}"
      authority="${rest%%/*}"
      path="${rest#*/}"
      [ "$path" = "$rest" ] && path=""
      authority="${authority#*@}"
      case "$authority" in
        \[*\]*) IC_HOST="${authority#\[}"; IC_HOST="${IC_HOST%%\]*}" ;;
        *)      IC_HOST="${authority%%:*}" ;;
      esac
      IC_PATH="$path"
      ;;
    *)
      before="${url%%:*}"
      if [ "$url" != "$before" ] && [ "${before#*/}" = "$before" ]; then
        IC_HOST="${before##*@}"
        IC_PATH="${url#*:}"
      fi
      ;;
  esac
  IC_PATH="${IC_PATH%.git}"
  IC_PATH="${IC_PATH#/}"
}

ic_repo() {
  local url
  url="$(git remote get-url origin 2>/dev/null || true)"
  [ -n "$url" ] || { echo "error: no 'origin' remote; issue-creator files issues on the origin's GitHub repo" >&2; return 1; }
  ic_parse_remote "$url"
  if [ -z "$IC_HOST" ] || [ -z "$IC_PATH" ]; then
    echo "error: could not parse a GitHub repo from origin ($url)" >&2; return 1
  fi
  echo "$IC_HOST/$IC_PATH"
}

ic_preflight() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "error: not a git repository" >&2; return 1; }
  command -v gh >/dev/null 2>&1 || {
    echo "error: gh not installed; see https://cli.github.com" >&2; return 1; }
  command -v python3 >/dev/null 2>&1 || {
    echo "error: python3 not installed; ic.sh uses it to parse gh JSON output for the duplicate search" >&2; return 1; }
  local repo host
  repo="$(ic_repo)" || return 1
  host="${repo%%/*}"
  # `gh auth status --hostname <host>` succeeding is our proof that origin is a
  # GitHub host we can actually post to. A non-GitHub origin (e.g. a GitLab
  # instance) or an unauthenticated host fails here, which is exactly when we
  # must not file.
  gh auth status --hostname "$host" >/dev/null 2>&1 || {
    echo "error: origin host '$host' is not an authenticated GitHub host; issue-creator only files on GitHub. If it is GitHub, run 'gh auth login --hostname $host'" >&2; return 1; }
  echo "repo=$repo"
}

ic_search() {
  local query="${1:-}" repo
  [ -n "$query" ] || { echo "error: search needs a query" >&2; return 1; }
  repo="$(ic_repo)" || return 1
  # Best-effort duplicate check over open issues (a duplicate we care about is
  # still actionable). --limit caps the scan at the 100 best matches; the
  # independent reviewer is the backstop for a duplicate that slips past a
  # broad query.
  gh issue list -R "$repo" --search "$query" --state open --limit 100 --json number,title,url \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps([{"number":i.get("number"),"title":i.get("title"),"url":i.get("url")} for i in d]))'
}

ic_ensure_label() {
  local name="${1:-}" color="${2:-}" repo
  [ -n "$name" ] || { echo "error: ensure-label needs a name" >&2; return 1; }
  repo="$(ic_repo)" || return 1
  if [ -z "$color" ]; then
    case "$name" in
      error)   color="D9534F" ;;
      warning) color="F0AD4E" ;;
      info)    color="5BC0DE" ;;
      *)       color="428BCA" ;;
    esac
  fi
  color="${color#\#}"
  # Create the label idempotently. GitHub rejects a duplicate name, which we
  # treat as success (the label already exists) rather than listing and
  # paginating every label to check first. Unlike GitLab, GitHub does NOT
  # auto-create a label referenced on issue create, so a genuine failure here
  # would make a labeled create fail; ic_create handles that by retrying
  # without the label, so this never blocks issue creation.
  gh label create "$name" -R "$repo" --color "$color" --description "issue-creator: $name severity" >/dev/null 2>&1 || true
}

ic_create() {
  local title="${1:-}" descfile="${2:-}" label="${3:-}" repo
  [ -n "$title" ] || { echo "error: create needs a title" >&2; return 1; }
  [ -f "$descfile" ] || { echo "error: description file not found: $descfile" >&2; return 1; }
  repo="$(ic_repo)" || return 1
  if [ -n "$label" ]; then
    ic_ensure_label "$label"
    if ! gh issue create -R "$repo" --title "$title" --body-file "$descfile" --label "$label"; then
      echo "note: labeled create failed; retrying without label '$label'" >&2
      gh issue create -R "$repo" --title "$title" --body-file "$descfile"
    fi
  else
    gh issue create -R "$repo" --title "$title" --body-file "$descfile"
  fi
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    preflight)    ic_preflight "$@" ;;
    repo)         ic_repo "$@" ;;
    search)       ic_search "$@" ;;
    ensure-label) ic_ensure_label "$@" ;;
    create)       ic_create "$@" ;;
    ""|-h|--help) ic_usage ;;
    *)            echo "error: unknown subcommand '$cmd'" >&2; ic_usage; return 1 ;;
  esac
}

main "$@"
