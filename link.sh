#!/usr/bin/env bash
# link.sh - link this repo's skills and commands into ~/.claude (and ~/.codex if present).
#
# Idempotent. Safe to re-run at any time (e.g. after `git pull` adds a new skill).
# Portable to macOS bash 3.2 and Linux.
#
# What it does:
#   1. Per-skill symlinks: every skills/<name> in the repo is linked to
#      ~/.claude/skills/<name>, and to ~/.codex/skills/user/<name> when
#      ~/.codex exists.
#   2. Per-command symlinks: every claude/commands/<name>.md is linked to
#      ~/.claude/commands/<name>.md.
#
# Links are made per entry, not per directory, so your own local skills and
# commands coexist with this repo's. A real (non-symlink) file or directory
# that collides with a repo entry is moved to a timestamped backup directory
# (mode 700, never deleted, never overwritten) and replaced by the symlink.
# Symlinks pointing outside this repo are left alone; dangling symlinks into
# this repo are pruned. Warnings go to stderr so they survive
# `link.sh > /dev/null` in cron logs.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"
BACKUP_ROOT="$HOME/.claude-configs-backup"
BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
BACKUP_READY=""

note() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

ensure_backup_dir() {
    # Create the per-run backup dir lazily; uniquify if two runs share a second.
    [ -n "$BACKUP_READY" ] && return
    mkdir -p "$BACKUP_ROOT"
    chmod 700 "$BACKUP_ROOT"
    local candidate="$BACKUP_DIR" i=1
    while ! mkdir "$candidate" 2>/dev/null; do
        candidate="$BACKUP_DIR.$i"
        i=$((i + 1))
    done
    BACKUP_DIR="$candidate"
    BACKUP_READY=1
}

backup() {
    # Move a real file/dir out of the way, preserving it. Never overwrites.
    local path="$1"
    ensure_backup_dir
    local dest="$BACKUP_DIR/$(printf '%s' "$path" | sed "s|^$HOME/||; s|/|__|g")"
    local i=1
    while [ -e "$dest" ]; do
        dest="$dest.$i"
        i=$((i + 1))
    done
    mv "$path" "$dest"
    note "  backed up: $path -> $dest"
}

points_into() {
    # points_into <symlink> <dir> : true if the symlink target is under <dir>.
    # Relative targets are resolved against the link's parent directory.
    # Targets containing ".." are conservatively treated as NOT managed
    # (foreign links are left alone, which is the safe direction).
    local target
    target="$(readlink "$1")"
    case "$target" in
        /*) : ;;
        *) target="$(dirname "$1")/$target" ;;
    esac
    case "$target" in
        *..*) return 1 ;;
    esac
    case "$target" in
        "$2"/*|"$2") return 0 ;;
        *) return 1 ;;
    esac
}

link_entry() {
    # link_entry <absolute source in repo> <absolute destination>
    local src="$1" dst="$2"
    if [ -L "$dst" ]; then
        if [ "$(readlink "$dst")" = "$src" ]; then
            return
        fi
        if points_into "$dst" "$REPO"; then
            rm "$dst"
        else
            note "  SKIP (foreign symlink, left alone): $dst -> $(readlink "$dst")"
            return
        fi
    elif [ -e "$dst" ]; then
        backup "$dst"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    note "  linked: $dst -> $src"
}

prune_dangling() {
    # Remove dangling symlinks in <dir> that point into this repo
    # (e.g. after a pulled commit deletes a skill).
    local dir="$1" entry
    [ -d "$dir" ] || return 0
    for entry in "$dir"/*; do
        [ -L "$entry" ] || continue
        if [ ! -e "$entry" ] && points_into "$entry" "$REPO"; then
            rm "$entry"
            note "  pruned dangling link: $entry"
        fi
    done
}

link_skills_into() {
    local app_skills_dir="$1" skill name
    for skill in "$REPO"/skills/*/; do
        [ -d "$skill" ] || continue
        name="$(basename "$skill")"
        link_entry "$REPO/skills/$name" "$app_skills_dir/$name"
    done
    prune_dangling "$app_skills_dir"
}

note "Repo: $REPO"

note "Claude Code:"
link_skills_into "$CLAUDE_DIR/skills"
for cmd in "$REPO"/claude/commands/*.md; do
    [ -e "$cmd" ] || continue
    link_entry "$cmd" "$CLAUDE_DIR/commands/$(basename "$cmd")"
done
prune_dangling "$CLAUDE_DIR/commands"

if [ -d "$CODEX_DIR" ]; then
    note "Codex:"
    link_skills_into "$CODEX_DIR/skills/user"
fi

if [ -n "$BACKUP_READY" ]; then
    note "Backups saved under: $BACKUP_DIR"
fi
note "Done."
