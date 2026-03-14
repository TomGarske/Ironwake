# CLAUDE.md

Repository policy for Claude agents in this project.

## Required Gitflow Behavior

1. Treat `main` as protected and stable.
2. Never commit directly to `main`.
3. Never push directly to `main`.
4. Before making code changes, create a short-lived branch from `main`.
5. Use branch names like:
   - `feature/<slug>`
   - `fix/<slug>`
   - `hotfix/<slug>`
6. Commit work on that branch, push it to `origin`, then create a pull request to `main`.
7. If currently on `main`, branch immediately before editing.

## Pull Request Requirement

- Every non-trivial change must go through a PR.
- Return the real PR URL after creating it.
