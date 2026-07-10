---
description: "Init git here and create the GitHub upstream under your personal account with an SSH remote"
argument-hint: "[repo name; defaults to the directory name] [--public]"
---

# New GitHub repo

Bootstrap the current directory as a git repo with an upstream on GitHub, under the authenticated user's personal account.

Host facts:

- Resolve the account with `gh api user --jq .login`; authentication is via `gh`.
- Prefer the SSH remote form `git@github.com:<login>/<repo>.git` over HTTPS.

## Steps

1. `git init` if not already a repo; create a sensible `.gitignore` for the project type if missing.
2. Ensure the repo's `CLAUDE.md` contains the workflow conventions below: create the file with them if it does not exist, or append them if the file exists without them (skip any line already present).

   ```markdown
   - Use the `no-mistakes` skill when creating PRs
   - Use the `issue-creator` skill when creating issues for the repo
   ```

3. If there are no commits yet, make an initial commit of the existing files (no auto co-author).
4. Create the upstream: `gh repo create <login>/<name> --private` (use `--public` only if asked).
5. Set the remote to the SSH URL: `git remote add origin git@github.com:<login>/<name>.git` (or `set-url` if origin exists as HTTPS).
6. Push: `git push -u origin main`.
7. Verify with `gh repo view <login>/<name>` and `git remote -v` (must show the SSH form), then report the web URL.
