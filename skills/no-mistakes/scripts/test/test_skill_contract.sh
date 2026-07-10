#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SKILL="$(cd "$(dirname "$NM_SH")/.." && pwd)/SKILL.md"
body="$(cat "$SKILL" 2>/dev/null || true)"

assert_ok test -f "$SKILL"
assert_eq "$(head -n1 "$SKILL")" "---" "starts with frontmatter fence"
assert_contains "$body" "name: no-mistakes" "has name"
assert_contains "$body" "user-invocable: true" "is user-invocable"
# Wired to the helper subcommands the prose depends on.
for token in "nm.sh" "validate_findings.py" "preflight" "default-branch" \
             "drift-check" "pr-existing" "pr-update" "rescue"; do
  assert_contains "$body" "$token" "references $token"
done
# Claude reviewer engine reads the diff from the worktree, not the main checkout.
assert_contains "$body" 'read the change from the worktree: its diff is `git -C "$wt" diff' "claude engine diffs the worktree"
# Codex fallback to Claude.
assert_contains "$body" "fall back" "documents codex fallback"
# Default runs both Claude and Codex as two independent reviewers.
assert_contains "$body" "defaults to \`both\`" "documents both-reviewer default"
assert_contains "$body" "two independent reviewers" "documents dual review"
# PR body required sections.
for h in "## Intent" "## Related issues" "## Changed files" "## Review findings" "## Fixes applied" "## Checks"; do
  assert_contains "$body" "$h" "PR body template has $h"
done
# Style: no em dash.
if grep -q "$(printf '\xe2\x80\x94')" "$SKILL"; then _fail "SKILL.md contains an em dash"; else _tick; fi
