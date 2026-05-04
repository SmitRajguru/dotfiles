---
name: pnpm-rebase
description: Rebase current branch onto origin/master, resolving pnpm-lock.yaml conflicts by regenerating via pnpm install. Loops until the rebase is complete.
disable-model-invocation: true
---

Rebase the current branch onto `origin/master`, automatically resolving `pnpm-lock.yaml` conflicts by regenerating the lockfile. Loops until the rebase is fully complete.

## Step 1 — Check current state

```bash
git status
```

Determine:
- Is a rebase already in progress? (output contains "rebase in progress")
- Are there already conflicted files? (`git diff --name-only --diff-filter=U`)

## Step 2 — Start the rebase (skip if already in progress)

If no rebase is in progress:

```bash
git pull origin master --rebase
```

If the rebase completes cleanly with no conflicts, skip to Step 4.

If conflicts appear, continue to Step 3.

## Step 3 — Resolve conflicts and continue (loop)

Check which files are conflicted:

```bash
git diff --name-only --diff-filter=U
```

**For `pnpm-lock.yaml`:** take one side as a base and regenerate:

```bash
git checkout --ours pnpm-lock.yaml
pnpm install
git add pnpm-lock.yaml
```

**For any other conflicted file:** stop and report to the user — do not attempt to resolve non-lockfile conflicts automatically.

Once all conflicts are resolved and staged, continue the rebase without opening an editor:

```bash
git -c core.editor=true rebase --continue
```

If new conflicts appear (next commit in the rebase chain), return to the top of Step 3 and repeat. Continue this loop until `git rebase --continue` reports the rebase is complete.

## Step 4 — Report outcome

Summarize concisely:

1. **Rebase result:** clean / conflicts resolved
2. **Commits replayed:** how many commits were in the rebase
3. **Lockfile:** whether `pnpm-lock.yaml` was regenerated and how many times
