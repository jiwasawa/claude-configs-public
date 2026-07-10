---
description: "Have Codex independently review an artifact (spec, plan, diff, doc); Codex comments only, you apply the fixes. Use whenever the user asks to review something with codex/codex exec, says Codex must not edit, or wants a review loop repeated until Codex approves"
argument-hint: "<file path, 'diff', or a description of what to review> [--loop to iterate until approved]"
---

# Codex second-opinion review

Get an independent review from Codex via `codex exec`, then apply the fixes yourself.
Use this for specs, plans, docs, and ad-hoc artifacts.
For gating committed code into a PR, `/no-mistakes` already runs a dual Claude+Codex review; prefer it there.

## Invariants (never deviate)

- Codex is a REVIEWER only. It must not modify the artifact, the code, or anything else. Instruct it explicitly: return review comments only.
- YOU triage the comments and apply the fixes. Push back on findings that are wrong; do not blindly apply.
- Tell Codex to use its subagents to review from multiple lenses relevant to the artifact (e.g. correctness, security, domain fit, clarity; for UI code: security, CSS, Python).

## Invocation

- Non-interactive: `codex exec "<review prompt>"` from the repo root, with sandbox disabled on the Bash call.
- Put the artifact reference in the prompt: file paths for specs/plans/docs, or the commit range for code.
- Known pitfall: `--uncommitted` cannot be combined with a `[PROMPT]` argument (seen in codex-cli 0.142.0). Do not use the flag; instead say in the prompt to run `git diff` / `git diff --cached` itself, or paste the diff.

## Review prompt template

> Review <artifact> using subagents, each taking a different lens: <lenses>.
> Do NOT modify anything. Return a numbered list of review comments with severity (blocker / should-fix / nit) and the exact location each applies to.
> End with an overall verdict: APPROVED or CHANGES REQUESTED.

## Loop mode (`--loop` or the user says "until approved")

1. Run the review.
2. Apply the justified fixes; note the findings you rejected and why.
3. Re-run the review on the updated artifact, telling Codex what changed since the last round.
4. Repeat until Codex says APPROVED, or only non-actionable nits remain, or you judge the artifact good enough (say so explicitly).
5. Report per round: findings, what you applied, what you rejected.

## Output

Summarize the final state: rounds run, blockers fixed, findings rejected (with reasons), and Codex's final verdict.
