---
description: "Merge a reviewed GitHub PR, sync the default branch, and clean up branches and worktrees"
argument-hint: "[PR number or URL; defaults to the current branch's open PR] [post-merge step, e.g. re-run an installer]"
---

# Merge PR and close out

The user has reviewed a PR and said LGTM.
Finish the whole close-out in one shot: merge, sync, clean up, verify.

## 1. Resolve the PR

- If `$ARGUMENTS` names a PR (number or URL), use it.
- Otherwise find the open PR for the current branch: `gh pr list --head "$(git branch --show-current)"`.
- If ambiguous (several open PRs, no argument), list them and ask which one.

## 2. Pre-merge checks

Run `gh pr view <id>` and verify:

- The PR is open and mergeable (no conflicts, checks green or absent).
- If the PR fixes a GitHub issue, the description MUST contain a closing reference (`Closes #N`).
  If it is missing, add it with `gh pr edit <id> --body ...` before merging.
- Do NOT push new commits at this point; the user already reviewed. If something is broken, stop and report instead.

## 3. Merge

- `gh pr merge <id> --merge --delete-branch`
- Follow the repo's existing convention (plain merge commits by default; use `--squash` or `--rebase` only if the repo or the user says so).

## 4. Sync and clean up locally

- Check out the default branch and `git pull --ff-only`.
- Delete the merged local branch if `--delete-branch` did not already.
  If it is checked out in a worktree (including `.claude/worktrees/agent-*`), run `git worktree remove` first; unlock with `git worktree unlock` if it is locked and its agent is finished.
- `git remote prune origin` and `git worktree prune`.
- If other local branches or worktrees clearly belonged to already-merged PRs, list them and offer to clean them too.

## 5. Post-merge step

If `$ARGUMENTS` or the conversation mentions a follow-up (e.g. re-run an installer script, redeploy a unit), run it now and verify it.

## 6. Verify and report

- Confirm the linked issue(s) auto-closed; close via `gh issue close` if not.
- Report: merged SHA on the default branch, branches/worktrees removed, issues closed, post-merge step outcome.
