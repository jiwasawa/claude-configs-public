---
description: "Take a GitHub issue end to end: clarify, fix on a branch, gate with no-mistakes, open a PR with Closes #N"
argument-hint: "<issue number or URL> [extra context, e.g. 'decide design yourself, I am OOO']"
---

# Work a GitHub issue

Drive one issue from URL to reviewed-ready PR.
Stop after the PR is open; the user reviews and then runs `/merge-pr`.

## 1. Understand the issue

- `gh issue view <n>` for the description, labels, and discussion (`--comments` for the full thread).
- Read the relevant code before forming an opinion.

## 2. Clarify before coding

- Ask clarifying questions FIRST, prioritizing questions where the user's answer would change the approach, not just the details.
- If an AskUserQuestion comes back empty (the ~60s auto-dismiss), re-ask in plain text and end the turn; never proceed on assumed answers.
- Exception: if the user said to decide yourself (OOO, "I leave the design decisions to you"), skip the questions, pick the simplest robust design, and record the decision in the PR description.

## 3. Branch

- Name it `<type>/issue-<n>-<slug>` where `<type>` is `fix`, `feat`, `docs`, or `refactor` (e.g. `fix/issue-20-state-reporting`).
- Use a dedicated worktree when the main working tree is dirty or when several issues are being worked in parallel.

## 4. Implement

- Fix the real problem, with tests. For bug fixes, reproduce first, in a setting as close to how an end user hits the bug as possible.

## 5. Gate and open the PR

- Run `/no-mistakes` to review, validate, and open the PR.
- The PR description MUST contain `Closes #<n>` so the merge auto-closes the issue.
- Comment on the issue with the PR link if no-mistakes did not already.

## 6. Report

State what the fix does, the design decisions taken, test results, and the PR URL.

## Parallel fan-out

When the user asks to work several issues at once (e.g. "all issues with the warning label"):
list the issues, then dispatch one agent per issue, each following this procedure in its own worktree with its own branch, each ending at an open PR.
Summarize all PRs at the end so the user can review and `/merge-pr` them one by one, re-checking conflicts after each merge.
