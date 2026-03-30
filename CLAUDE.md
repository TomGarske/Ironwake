# CLAUDE.md

Repository policy for Claude agents in this project.

## Merge Conflict Safety Protocol

When resolving merge conflicts, agents must preserve behavior from both sides unless explicitly told to drop one side.

1. **Inspect before editing**
   - List all conflicted files first.
   - Categorize each conflict as:
     - text conflict (`AA`, `UU`, etc.),
     - binary conflict,
     - modify/delete conflict,
     - semantic conflict (auto-merged but behavior duplicated or regressed).

2. **Set per-file resolution intent**
   - For each conflicted file, explicitly choose one:
     - keep ours,
     - keep theirs,
     - manual merge.
   - For binary conflicts, document which asset wins and why.

3. **Prefer semantic preservation over mechanical merge**
   - Remove duplicate methods/nodes introduced by auto-merge.
   - Keep naming/path refactors already adopted in `main` unless user asks otherwise.
   - Avoid resurrecting deleted files unless still referenced and required.

4. **Run post-merge validation**
   - Ensure no conflict markers remain.
   - Run lint/parse checks on edited files.
   - Verify key flows touched by the merge (scene paths, autoloads, entry screens, mode routing).

5. **Commit with traceability**
   - Use a merge commit message that states what was preserved from each side.
