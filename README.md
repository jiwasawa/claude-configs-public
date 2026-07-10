# claude-configs-public

The public subset of my Claude Code configuration: skills and slash commands that are useful outside my day job.
The centerpiece is a GitHub-based shipping workflow (`no-mistakes` and friends) that gates every change through an independent review, local checks, and a clean PR before it reaches the remote.

## What's here

### Skills (`skills/`)

| Skill | What it does |
|-------|--------------|
| `no-mistakes` | Gate committed changes through an intent-aware dual review (Claude + Codex), safe auto-fixes, local format/lint/test checks, and a lease-guarded push into a clean GitHub PR. Invocable as `/no-mistakes [task]`. |
| `issue-creator` | After a review, file the findings that are too big for the current change as GitHub issues ("fix small, file big"), each draft gated by an independent reviewer. Invocable as `/issue-creator`. |
| `learn-quiz` | Teach the user a session, change set, or concept incrementally and quiz them until mastery is demonstrated. |

### Commands (`claude/commands/`)

| Command | What it does |
|---------|--------------|
| `/work-issue` | Take a GitHub issue end to end: clarify, fix on a branch, gate with no-mistakes, open a PR with `Closes #N`. |
| `/triage-issues` | Triage a GitHub issue backlog, pick the workable ones, and drive each through `/work-issue`. |
| `/merge-pr` | Merge a reviewed PR, sync the default branch, and clean up branches and worktrees. |
| `/new-github-repo` | Init git in the current directory and create the GitHub upstream under your account with an SSH remote. |
| `/codex-review` | Have Codex independently review an artifact (spec, plan, diff, doc); Codex comments only, you apply the fixes. |
| `/check-tmux` | Diagnose a long-running background job in tmux: progressing or stalled, why, and what to do. |

The workflow commands are designed to chain: `/triage-issues` fans out into `/work-issue`, which gates with `no-mistakes`, which hands off to `/merge-pr`; leftovers from any review go through `issue-creator`.

## Requirements

- `git`, `python3`, and an authenticated [GitHub CLI](https://cli.github.com) (`gh auth login`).
- Optional: the [Codex CLI](https://github.com/openai/codex) as the second review engine.
  `no-mistakes` and `issue-creator` default to running Claude and Codex as two independent reviewers; without `codex` installed they degrade gracefully to Claude-only and say so.

## Install

```sh
git clone https://github.com/jiwasawa/claude-configs-public.git
cd claude-configs-public
./link.sh
```

`link.sh` symlinks every skill into `~/.claude/skills/<name>` (and `~/.codex/skills/user/<name>` when `~/.codex` exists) and every command into `~/.claude/commands/<name>.md`.
Links are per entry, so your own local skills and commands coexist with the repo's.
Anything real it replaces is moved to `~/.claude-configs-backup/<timestamp>/`, never deleted.
It is idempotent; re-run it after a `git pull` that adds or removes skills.

Prefer picking cherries?
Every skill and command is self-contained: copy `skills/<name>/` or `claude/commands/<name>.md` into your own `~/.claude` and it works.

## Per-repo configuration

`no-mistakes` reads an optional `.no-mistakes.yaml` at the repo root:

```yaml
commands:
  format: gofmt -w .
  lint: make lint
  test: go test ./...
reviewer: both   # both | claude | codex
```

Absent keys are resolved from `AGENTS.md`/`CLAUDE.md` or by asking once.

## Testing

The safety-critical shell helpers ship with their own test suite:

```sh
bash skills/no-mistakes/scripts/test/run_tests.sh
```
