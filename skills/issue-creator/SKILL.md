---
name: issue-creator
description: Raise code-review findings that are too big for the current change as GitHub issues, so the PR stays focused and nothing gets lost. Use whenever a review (no-mistakes, /code-review, or manual) surfaces an out-of-scope bug, refactor, or improvement, or the user asks to file/defer issues from findings. Requires a GitHub origin remote and an authenticated gh.
user-invocable: true
---

# issue-creator

When a code review turns up more than the current change can absorb, `issue-creator` files the leftovers as GitHub issues so the PR stays focused and the findings are not lost.
It runs in two situations:

- Standalone: the user invokes `/issue-creator` (or asks to file issues) after a review.
  The findings come from the review that just happened in this conversation.
- As a follow-up step at the end of a `no-mistakes` run, capturing findings that were too large to fold into the PR.

The mechanical GitHub calls live in `scripts/ic.sh` (relative to this skill).
Call them as `bash <skill-dir>/scripts/ic.sh <subcommand>`; below, `$IC` means exactly that.
Let the script own every outward-facing `gh` call so the repo is resolved and issues are created the same way every run.

## The core judgement: fix small, file big

The whole point of this skill is restraint.
Most review findings should be fixed in the review itself, not turned into issues; a backlog full of trivia is worse than no backlog.
File an issue only when acting on the finding now would bloat or derail the current change.

File it when the finding is:

- Out of scope: it concerns code or behavior the current PR was not about, so fixing it here would mix unrelated work.
- Large: a multi-file refactor, an architectural change, or anything that would balloon the diff and delay shipping the intended change.
- Genuinely contested: it needs a design or product decision that is real and consequential, where reasonable people would disagree and the choice deserves discussion before anyone acts.
- Pre-existing: a real problem the current change did not introduce and is not responsible for.

Fix it now, do not file, when the finding is a small, in-scope, low-risk change: a typo, a local rename, a missing null check, a one- or two-line correction that belongs to the code you are already touching.
When in doubt, fix it; the current review is the cheapest place to resolve it, and restraint is the whole point.

Be especially wary of enhancement-shaped findings ("make X configurable", "add an option for Y", "consider extracting Z"): almost any change "needs a small design decision" (a flag name, a default, where a value lives), and that alone is not enough to file.
A trivial or obvious decision does not qualify as "genuinely contested"; if the enhancement is small and the choice is easy, fix it in the review or drop it.
Only file an enhancement when it is substantial in its own right or the decision behind it is genuinely open.

You decide this per finding by these criteria; there is no per-item approval step.
The independent review below is the safety check that keeps you honest.

## Preconditions

Run `$IC preflight`.
It verifies you are in a git repo, `gh` is installed, and the `origin` remote is a GitHub host you are authenticated to; on success it prints `repo=<host>/<owner>/<repo>`.
On `error: <message>`, relay it and stop.

The authentication check is also the GitHub check: if `origin` points somewhere that is not an authenticated GitHub host (for example a GitLab remote), preflight fails and this skill does not apply.
Say so plainly and stop; do not try to file issues anywhere else.

## Flow

Work through the candidate findings one at a time.

1. Collect the findings.
   Standalone: use the findings from the review in this conversation.
   After no-mistakes: use its finding set, focusing on the ones its triage left unresolved because they were too big for the PR.

2. Select candidates by the "fix small, file big" criteria above.
   Set aside everything that should be fixed in the review; those are not this skill's job.

3. Check for duplicates before drafting: `$IC search "<keywords>"`.
   It returns open issues matching the query as a JSON array of `{number, title, url}`.
   Pick keywords from the finding (the symbol, file, or a distinctive phrase).
   If a clear match already exists, do not create a second one: record it as a skipped duplicate and link its `url` in your report.

4. Draft a minimal issue: a clear title and a short description.
   Keep the description to a few sentences: what the problem is, where it is (file and line when known), and why it matters.
   Add one trailing line, `Source: <PR link or branch@commit>`, for traceability; it is cheap and lets a reader trace the issue back to the review that raised it.
   Do not pad it into a template; minimal and specific beats long and vague.

5. Have an independent agent review the draft before it is created (see Reviewer below).
   The reviewer judges: is this genuinely too big for the current change (not a quick fix), a real and actionable problem, well-scoped and clearly written, and not a duplicate of an existing open issue?
   The reviewer's default is restraint: reject drafts that could reasonably be fixed in the current review, and be skeptical of enhancement-shaped issues whose only justification is a small or obvious design decision.
   Approve only when filing separately is clearly the right call.

6. Act on the verdict:
   - Approved: create it (step 7).
   - Revise: apply the feedback and re-review, at most two revision rounds.
     If the draft is still not approved once the cap is reached, drop it and record why, the same as a rejection; do not file an unapproved draft.
   - Rejected (not actually big enough, vague, or a duplicate): do not create it.
     Record why in your report.

7. Create the issue: `$IC create "<title>" <descfile> "<severity>"`.
   Write the description to a temp file and pass its path.
   Pass the finding's severity (`error` or `warning`) as the label; the script creates that label in the repo if it is missing.
   The command prints the new issue's URL.

8. Report (template below): what was created, what was skipped as a duplicate (with links), and what was rejected (with reasons).

## Issue format

Keep it minimal.

```
Title: <concise, specific, imperative>

<one to four sentences: the problem, where it is (file:line), why it matters>

Source: <PR link, or branch@commit>
```

**Example**
Title: `Extract duplicated retry logic in the HTTP clients into one helper`
Body:
```
Each of the three clients in internal/http/ (rest.go, graphql.go, upload.go) reimplements the same backoff-and-retry loop, and they have already drifted (upload.go retries on 5xx only, the others also retry timeouts). This should be one shared helper, but unifying it touches all three call sites and their tests, which is well beyond the current change.

Source: #142 (feat/upload-retries @ a2ff085)
```

## Reviewer

Choose the reviewing engine the same way `no-mistakes` does: read `reviewer` from `.no-mistakes.yaml` / `.no-mistakes.yml` at the repo root if present, otherwise default to `both`.
Two independent reviewers catch more bad drafts than one, so `both` is the default for a reason.

- Claude engine: dispatch a fresh subagent (the Agent tool) that did not draft the issue.
  Give it the current change's intent and the relevant code context (the finding's file and lines, or the diff), the finding, the drafted title and body, and the duplicate-search results.
  Without that context the reviewer cannot tell whether the finding is genuinely out of scope or too large for the current change; with it, it can judge scope and size, not just wording.
  Ask for a verdict: `approve`, `revise` (with specific feedback), or `reject` (with a reason).
- Codex engine: run `codex exec -s read-only "<prompt>" </dev/null` with the same inputs and the same verdict format.
  Redirect stdin from `/dev/null` so `codex` does not hang waiting on stdin.

Degrade, do not stall.
If an engine is unavailable (`codex` not installed, or it errors), drop just that engine and proceed with the other; note which one you skipped.
Under `both`, treat the strictest verdict as binding: a `reject` from either engine drops the issue, and a `revise` from either triggers a revision round.
If no engine is available at all, tell the user you cannot run the independent review and ask whether to file the issues without it rather than filing them silently.

## Report template

```
## Issues filed
- <url> - <title> (<severity>)

## Skipped as duplicate
- <finding> -> existing <url>

## Not filed
- <finding> - <reason: fixed in review / rejected by reviewer / not big enough>
```

If nothing met the bar, say so: report that the review turned up nothing worth a separate issue, which is a good outcome, not a failure.
