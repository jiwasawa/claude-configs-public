---
description: "Survey a GitHub issue backlog, decide which are workable now, and optionally drive them through /work-issue to open PRs. Use when the user asks which issues to work on, to plan or triage the backlog, points at the issues list asking what's actionable, or names an issue range like '24 to 32'"
argument-hint: "[issue numbers/range/label, e.g. '24 to 32' or 'backlog'] [extra context, e.g. '#1 is blocked, I am OOO']"
---

# Triage and work a GitHub issue backlog

The user wants the open issues reviewed and the actionable ones worked, not just one known issue.
Single named issue with no triage needed: use `/work-issue` directly instead.

## 1. Collect the backlog

- `gh issue list` for open issues; narrow to the numbers, range, or label in `$ARGUMENTS` if given.
- For each candidate, `gh issue view <n> --comments` including the discussion.
  Recent comments often say an issue is deferred, superseded, or already being handled.

## 2. Classify each issue

Sort every candidate into exactly one bucket:

- **Workable now**: clear scope, no blocker, not being handled elsewhere.
- **Held by another agent or PR**: an open PR references it, or the user said another agent has it.
  Never double-work these; check the open PRs (`gh pr list`, then `gh pr view <id>` for the body) for `Closes #<n>` references.
- **Blocked**: needs external input, hardware, or a decision recorded in the discussion.
- **Not worth doing / stale**: say why, and propose closing with a comment rather than silently skipping.

## 3. Confirm the plan

- Present the buckets with a one-line rationale per issue and a proposed order (quick wins and unblockers first, then by impact).
- Ask which to proceed with, unless the user already scoped it ("work on all of these", OOO instructions), in which case proceed.

## 4. Execute

- Work each selected issue following the `/work-issue` procedure: clarify (or decide, if OOO), branch, implement with tests, gate with `/no-mistakes`, open a PR with `Closes #<n>`.
- Independent issues: dispatch one agent per issue, each in its own worktree with its own branch, so PRs stay atomic.
- Issues that touch the same files: work them sequentially on stacked or separate branches and say so in the PR descriptions.

## 5. Report

One summary at the end: per issue, the bucket it landed in, and for worked issues the PR URL and test results.
List the skipped/blocked ones with the reason, so nothing silently disappears.
The user reviews and then runs `/merge-pr` per PR, re-checking conflicts after each merge.
