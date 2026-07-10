---
name: no-mistakes
description: Gate your committed changes through an intent-aware review, local checks, and a clean GitHub PR before they reach the remote. Use when the user asks to run no-mistakes, gate or ship or validate changes, push safely, asks you to do a task and then validate it, or invokes /no-mistakes.
user-invocable: true
---

# no-mistakes

`no-mistakes` gates your committed work before it reaches the GitHub remote.
It reviews the change against your intent, applies safe fixes, escalates anything that touches your intent, runs your local checks, then opens a clean Pull Request.
It stops once the PR is open; you review and merge it.

The mechanical and safety-critical steps live in `scripts/nm.sh` (relative to this skill).
Call them as `bash <skill-dir>/scripts/nm.sh <subcommand>`; below, `$NM` means exactly that.
Never re-derive the git or push commands by hand; the helper exists so the safety invariants hold every run.

## Two modes

- Validate-only: bare `/no-mistakes`. The work is already committed on a feature branch. Gate it.
- Task-first: `/no-mistakes <task>`. Do the task first, then gate it.

For task-first, before editing anything:

1. Require a clean working tree (`git status --porcelain` is empty). If it is not, stop and ask the user to commit or stash; never touch their pending work.
2. If the user is on the default branch (`$NM default-branch`), create and switch to a new feature branch.
3. Do the work and commit only the changes that belong to the task, on the feature branch.

The task text is the intent. Enrich it with the decisions and tradeoffs you made.

## Preconditions

Run `cd "$(git rev-parse --show-toplevel)" && $NM preflight "<branch>"` where `<branch>` is the current branch.
It checks that you are in a git repo, on a feature branch (not the default), with a clean tree, and that `gh` is installed and authenticated.
On failure it prints `error: <message>` with the exact fix; relay it and stop.

## Intent

Validate-only: ask the user one line, "what was this change meant to accomplish?", or propose a candidate from the conversation and confirm.
Write the final intent to a temp file; you pass it to the reviewer.
Err on the side of completeness so the reviewer can tell a deliberate choice from a mistake.

## Run the pipeline

Let `<branch>` be the current branch.

1. Load config: `$NM config "$(git rev-parse --show-toplevel)"`.
   Use `test`/`lint`/`format`/`reviewer` if present.
   If a check command is absent, look in `AGENTS.md` or `CLAUDE.md`; if still unknown, ask the user once.
   Reviewer defaults to `both`, which runs Claude and Codex as two independent reviewers; set `reviewer` to `claude` or `codex` in config, or let the user ask for one, to run a single reviewer.

   Trust note: this is a single-developer tool, so config is read from the working tree and trusted. Do not use it to gate untrusted contributors' branches.

2. Record state and isolate:
   - `$NM observe "<branch>"` gives `BASE_SHA` and `REMOTE_SHA`. Keep both.
   - `range="$($NM diff-range)"`.
   - `wt="$($NM worktree-add "$BASE_SHA")"`. Do all work in `$wt`; prefix worktree-scoped helper calls with `cd "$wt" &&`.
   - `run_id="<branch>-${BASE_SHA:0:8}"`.

3. Review: get findings as a strict JSON array.
   Two reviewer engines are available; which run depends on `reviewer` (default `both`).
   - Claude engine: dispatch a fresh subagent (the Agent tool) that did not write the code.
     Give it `$wt`, `range`, the intent, and this schema.
     Like the Codex engine, it must read the change from the worktree: its diff is `git -C "$wt" diff <range>`, never a bare `git diff` from the main checkout, whose branch stays at `BASE_SHA` and shows stale pre-fix code during re-review.
     It must output ONLY the JSON array, each element with exactly these fields:
     `{"id":"<unique>","severity":"error|warning|info","file":"<path or null>","line":<int or null>,"action":"auto-fix|ask-user|no-op","description":"<one or two sentences>"}`.
     `action`: `auto-fix` = mechanical and low-risk; `ask-user` = challenges intent or changes product behavior; `no-op` = informational.
   - Codex engine: `cd "$wt" && $NM review-codex "$range" "$intent_file"`.
     It returns the same JSON schema.
   - Which engines run:
     - `both` (default): run the Claude engine and the Codex engine over the same `range` and intent, independently.
       Two reviewers catch more than one; run them for defense in depth.
     - `claude`: run only the Claude engine.
     - `codex`: run only the Codex engine.
   - Validate each engine's array on its own, once per engine: `printf '%s' "$findings" | python3 <skill-dir>/scripts/validate_findings.py`.
     If one fails, retry that engine once with a short repair prompt restating the schema.
   - Degrade, do not stall.
     If any engine is unavailable (Codex prints `error: codex not found` or exits non-zero) or still fails to produce valid findings after its one retry, drop just that engine and continue with the other engine's findings; tell the user which engine was skipped and why.
     Known degradations to expect and report:
     - Inside a forked subagent the Claude engine cannot dispatch a fresh reviewer, so the run degrades to Codex-only; say so rather than silently claiming a dual review.
     - The Codex engine fails with `Argument list too long` on very large diffs (over ~128KB, typically notebooks); fall back to the Claude engine for that range.
     In `codex` mode, fall back to the Claude engine if Codex fails.
     Only when no engine that ran produced valid findings, fail closed: do not invent findings, ask the user how to proceed.
   - Merge into one finding set for triage.
     Prefix each finding's `id` with its engine (`claude:` or `codex:`) so ids stay unique and every finding is attributable.
     Where both engines raise substantially the same issue (same file and line, equivalent meaning), collapse it to one finding, keep the stricter `action` (`ask-user` over `auto-fix` over `no-op`), and note that both reviewers agreed.

4. Triage each finding (in `$wt`):
   - `auto-fix`: apply the fix yourself, on your own judgment.
   - `ask-user`: stop. Relay the finding verbatim (`id`, `file`, full `description`). Wait for the user to choose: approve (accept the risk, change nothing), fix (apply a fix, with their optional guidance, else the reviewer's suggestion), or skip (leave it, record it in the PR body as a known accepted finding). Never resolve an `ask-user` finding yourself.
   - `no-op`: note it, do nothing.

5. Local checks, in `$wt`, in this order: `format`, then `lint`, then `test`.
   - If any auto-fix or the formatter changed files, re-run the full `format`/`lint`/`test` set.
   - On a failure, fix and re-run, at most 2 fix attempts per check. If it still fails, stop and escalate with the failing output (your fix commits are safe and will be rescued; see On failure).

6. Commit the fixes in `$wt` (Conventional Commits, no co-author line).
   At this point all triage and local-check changes are committed; `git -C "$wt" diff <range>` now reflects the full updated state.

7. Re-review once if anything changed in steps 4 or 5: repeat step 3 over the updated `range` (which now includes the fix commit from step 6), flow new findings through triage once.
   Every engine must again diff the worktree (`git -C "$wt" diff <range>`); a reviewer that diffs the main checkout sees none of the fixes from steps 4-6 and will re-flag already-fixed findings.
   Tag the re-review's findings so they do not collide with the first pass in the PR body (e.g. an `r2:` prefix on top of the engine prefix, giving `r2:claude:...`).
   If the re-review's bounded triage applies further fixes, commit those too before pushing.
   Do not loop a third time; surface any further new findings to the user.

8. Push and open the PR:
   - `cd "$wt" && $NM drift-check "<branch>" "$BASE_SHA" "$REMOTE_SHA"`. If it fails, stop and report the drift; do not push.
   - `cd "$wt" && $NM push "<branch>" "$REMOTE_SHA"`. If push is rejected, stop and report; do not force.
   - `existing="$($NM pr-existing "<branch>")"`.
   - Identify related tracker issues; this is mandatory, not best-effort.
     Collect issue numbers from the task text and intent, verify each explicitly referenced number with `gh issue view <N>`, then search the tracker for further matches (`gh issue list --search "<keywords>"`); the search alone matches issue text and can miss an issue referenced only by number.
     For every issue the change fully resolves, the PR body MUST contain a `Closes #N` line (GitHub auto-closes it when the PR merges into the default branch); for an issue it only advances, use `Related to #N` so it links without closing.
     Note the numbering: on GitHub, issues and PRs share one `#N` space; confirm with `gh issue view <N>` that the number is an issue, since a `#N` that is actually a PR closes nothing.
     If no issue applies, say so in the Related issues section rather than omitting the check.
   - Write the PR body (template below) to a temp file `<descfile>`.
   - If `existing` is non-empty, the push already updated that open PR's branch. Refresh it: `$NM pr-update "$existing" "<title>" "<descfile>"`, then report that PR.
   - Otherwise: `$NM pr-create "<branch>" "$($NM default-branch)" "<title>" "<descfile>"`. If `pr-create` fails after the push already succeeded, the branch is on the remote but no PR exists: report the pushed branch and the exact `gh pr create` command to retry, so the result is recoverable.
   - Title is Conventional Commits style.

9. Done: report the PR link and a concise summary of what was validated, found, and fixed. If fixes were applied, the local branch is now behind; give the user the fast-forward command: `git fetch && git switch <branch> && git merge --ff-only origin/<branch>`.
   When the user later approves the PR ("LGTM", "merge it"), run `/merge-pr` instead of merging by hand; it also syncs the default branch and cleans up branches and worktrees.

## PR body template

Fill and write this to `<descfile>`:

```
## Intent
<the intent, in the user's terms>

## Related issues
<one line per related issue: `Closes #N` if this PR fully resolves it, `Related to #N` if it only advances it; write "None." if no tracker issue applies>

## Changed files
<bulleted summary of the files changed and why>

## Review findings
<which reviewers ran (claude, codex, or both); then each finding: id (its `claude:`/`codex:` prefix shows which reviewer raised it), severity, action, description; note any skipped ask-user findings as accepted>

## Fixes applied
<each fix the pipeline made that the original change missed>

## Checks
format: <command> -> <result>
lint: <command> -> <result>
test: <command> -> <result>
```

## On failure

If any step fails after fix commits exist, before removing the worktree run `cd "$wt" && $NM rescue "$run_id"` and tell the user the rescue ref `refs/no-mistakes/$run_id` holds their fix commits.
Only remove the worktree (`$NM worktree-remove "$wt"`) after the PR is open, or after rescuing on failure.

## Cleanup

After the PR is open: `$NM worktree-remove "$wt"`.
