# Git

- Never run `git clean` or `git reset --hard` without explicit confirmation,
  even to undo your own mistake. Both destroy work that cannot be recovered.
- Ask before switching the branch of a repository's main working directory, and
  offer a worktree instead.
- Create worktrees under `~/worktrees/<readable-name>/`, never inside the
  repository, where language servers and file watchers would index the code a
  second time. Name them after the task (for example
  `~/worktrees/fix-login-timeout`), not after an agent ID. Each new branch
  gets its own worktree; agents working on the same branch share one.
- To integrate one branch into another, use `git merge`, not `git rebase`. If it
  is unclear which the user wants, ask.
- To create a branch from an existing one, run `git checkout <base>` and then
  `git-new-branch <name>`. Do not use `git checkout -b`: the `git-new-branch`
  alias sets up remote tracking so that a plain `git push` works.
- Remote branches are deleted automatically when their pull request merges.
  Delete local branches with `git branch -d`, and never run
  `git push origin --delete`.
- Commit messages carry no AI attribution trailer.
