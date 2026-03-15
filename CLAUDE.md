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

## Merge Conflict Safety Protocol

When resolving merge conflicts, agents must preserve behavior from both sides unless explicitly told to drop one side.

1. **Integrate on a dedicated branch**
   - Never resolve conflicts on `main`.
   - Create `integration/<slug>` from up-to-date `main`.

2. **Inspect before editing**
   - List all conflicted files first.
   - Categorize each conflict as:
     - text conflict (`AA`, `UU`, etc.),
     - binary conflict,
     - modify/delete conflict,
     - semantic conflict (auto-merged but behavior duplicated or regressed).

3. **Set per-file resolution intent**
   - For each conflicted file, explicitly choose one:
     - keep ours,
     - keep theirs,
     - manual merge.
   - For binary conflicts, document which asset wins and why.

4. **Prefer semantic preservation over mechanical merge**
   - Remove duplicate methods/nodes introduced by auto-merge.
   - Keep naming/path refactors already adopted in `main` unless user asks otherwise.
   - Avoid resurrecting deleted files unless still referenced and required.

5. **Run post-merge validation**
   - Ensure no conflict markers remain.
   - Run lint/parse checks on edited files.
   - Verify key flows touched by the merge (scene paths, autoloads, entry screens, mode routing).

6. **Commit with traceability**
   - Use a merge commit message that states what was preserved from each side.
   - In PR summary, include a short “Conflict Resolution Notes” section listing major file decisions.

## Merge Conflict Safety Protocol

When resolving merge conflicts, agents must preserve behavior from both sides unless explicitly told to drop one side.

1. **Integrate on a dedicated branch**
   - Never resolve conflicts on `main`.
   - Create `integration/<slug>` from up-to-date `main`.

2. **Inspect before editing**
   - List all conflicted files first.
   - Categorize each conflict as:
     - text conflict (`AA`, `UU`, etc.),
     - binary conflict,
     - modify/delete conflict,
     - semantic conflict (auto-merged but behavior duplicated or regressed).

3. **Set per-file resolution intent**
   - For each conflicted file, explicitly choose one:
     - keep ours,
     - keep theirs,
     - manual merge.
   - For binary conflicts, document which asset wins and why.

4. **Prefer semantic preservation over mechanical merge**
   - Remove duplicate methods/nodes introduced by auto-merge.
   - Keep naming/path refactors already adopted in `main` unless user asks otherwise.
   - Avoid resurrecting deleted files unless still referenced and required.

5. **Run post-merge validation**
   - Ensure no conflict markers remain.
   - Run lint/parse checks on edited files.
   - Verify key flows touched by the merge (scene paths, autoloads, entry screens, mode routing).

6. **Commit with traceability**
   - Use a merge commit message that states what was preserved from each side.
   - In PR summary, include a short “Conflict Resolution Notes” section listing major file decisions.
