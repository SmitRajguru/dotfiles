# Asking Questions

**ALWAYS use AskUserQuestion liberally.** Do not hesitate to ask questions. If you have ANY uncertainty, ambiguity, or need to make a design decision, ASK. I strongly prefer more questions over fewer. Specifically:

- Ask when requirements are unclear or could be interpreted multiple ways
- Ask when there are design tradeoffs to consider
- Ask when choosing between multiple valid approaches
- Ask when you're unsure about scope (should you also do X?)
- Ask when you're about to make assumptions
- Ask when something seems off or contradictory

Do NOT try to guess my intent or make assumptions to avoid bothering me. I want to be bothered. Asking questions is not a sign of weakness—it's the right thing to do. When in doubt, ask.

# Code Review Standard

All non-trivial code I write is reviewed by **two** parties:

1. **The user**, as a peer reviewer.
2. **An independent codex agent** (GPT-5.x via the `cursor-agent` CLI). Codex has different training, different priors, and no shared session context with me — it exists specifically to break the same-family echo chamber that creates false confidence in my own designs.

Write code that passes both. Practical implications:

- **Self-contained code.** Codex sees the diff, not the conversation. If a design choice only makes sense given earlier discussion, either pick a pattern that doesn't need the context, or inline a short *why* comment. Don't rely on "I had a reason" — that defense doesn't survive outside review.
- **Idiomatic over clever.** Independent reviewers flag novelty that doesn't pull its weight. If a simpler approach is 95% as good, ship the simpler one.
- **No speculative abstractions, no dead code, no half-finished stubs.** These are the easiest targets for an outside reviewer and signal poor discipline.
- **Honest tests.** If something can't be verified end-to-end, say so in the response. Don't write a test that exercises plumbing instead of behavior just to have something green.
- **Don't argue with codex output via context.** When codex flags something in an audit loop, treat it as a real signal. Cross-check the finding against the code; if codex is factually wrong, say so. Otherwise, fix it.

When the user asks for a review or audit (directly or as the audit step in an autonomous code→audit→code loop), delegate to a codex agent rather than reviewing my own work. The mechanism (skill or shell-out pattern) is provided per-project. If no codex-review mechanism is loaded in the current project, surface that gap rather than silently self-reviewing.

# Context Management

Keep Claude Code context utilization small. The status line shows `Ctx X.XK (Y%)` colored by fill, with a red `(!)` once fill reaches `CTX_WARN_THRESHOLD` (default 25%) and a bold `(!!)` at the midpoint between threshold and full (62.5%). Both are **real signals** — act on them.

When the warning appears (or fill is approaching it):

- **Suggest a session handoff** for long tasks — compact + write a brief handoff doc + start a fresh session — rather than letting context grow.
- **Delegate to subagents** (Explore, general-purpose) for research / large-file scans so their results return as compressed summaries instead of bloating the main session.
- Avoid reading entire large files when targeted grep + section reads work.
- Don't dump verbose tool outputs into the conversation when a summary suffices.
- Split independent work units into separate fresh sessions when natural.

# Creating Claude Code Skills

Whenever you create a new Claude Code skill, use a Haiku subagent (via the Task tool with `model: haiku`) to validate that the skill follows best practices and has correct frontmatter format.

After modifying or adding skills, always run `tokei ~/.claude/skills` to check skill file sizes. If any skill exceeds 500 lines (the best practices limit), use AskUserQuestion to ask what to do. Options include:
- Reduce content by removing less important sections
- Move reference material to separate files in the skill directory (e.g., `reference.md`, `examples.sql`)

# Global vs Project .claude Directory

**Always use `~/.claude/` (global) for user configuration** — agents, settings, commands, CLAUDE.md, scheduled tasks, etc. Never read or write these to the project-level `<repo>/.claude/` directory unless that's the explicit intent (e.g., per-repo personal symlinks). The project `.claude/` is repo-owned (hooks, rules, skills checked into the repo) and should not be confused with user-level config.

When referencing agent definitions, always use `~/.claude/agents/`, not a relative path that might resolve to the project `.claude/`.

# Repo Sync

User-level config lives in `~/dotfiles` (shell, tmux, p10k via XDG, general Claude/Cursor artifacts). Whenever you modify a file tracked by `~/dotfiles`, **immediately commit, push, and sync**. SessionStart and Stop hooks warn if the repo is behind / has untracked changes.

Other private/work-specific overlays (skills, agents, aliases) may exist in separate repos that drop files into `$ZDOTDIR/local/` (sourced by `.zshrc`) and `~/.claude/` (per-item symlinks). Those repos own their own sync rules.

# Git Safety

**NEVER run `git clean` or `git reset --hard` without first getting explicit confirmation from the user.** These commands destroy untracked files and uncommitted work that cannot be recovered. Always ask before running them, even when trying to undo your own mistakes.

# Worktree Management

**ALWAYS ask before changing the main working directory's branch.** Default to using a worktree instead. Rules:

1. **Ask first** — before checking out a different branch in the main repo, ask the user if they'd prefer the work done in a worktree.
2. **Share worktrees** — agents that need the same branch can work in the same worktree.
3. **Separate worktrees for new branches** — each new branch should get its own worktree.
4. **Readable names** — worktree directories must have human-readable names describing the task, not agent IDs. Example: `~/worktrees/cat1-srm-ctgg-creation` instead of `agent-a42fdf85`.
5. **Location** — always create worktrees under `~/worktrees/`, NEVER inside the repo. Worktrees inside the repo cause clangd, file watchers, and language servers to index the codebase multiple times, wasting RAM.

# Git Merge Strategy

When asked to "pull a branch", "merge a branch", or integrate one branch into another, **always use `git merge`**, never `git rebase`. This preserves commit history. If genuinely ambiguous whether the user wants merge or rebase, ask before proceeding.

# Git Branch Creation

When creating a new branch from an existing branch, always:
1. `git checkout <existing-branch>`
2. `git-new-branch <new-branch-name>`

**Do NOT use `git checkout -b`.** `git-new-branch` is a local alias that correctly sets up remote tracking so `git push` works without specifying the origin.

# Git Branch Cleanup

Remote branches are automatically deleted after PRs are merged. Never use `git push origin --delete` - just delete local branches with `git branch -d`.

# Timezone

All timestamps and time references (logs, activity entries, comm files, etc.) must use **America/Los_Angeles** — PDT in summer, PST in winter.

# Ad-hoc Python with Third-Party Packages

**NEVER use `pip install`.** For one-off Python commands that need third-party packages, use `uv run --with`:

```bash
uv run --with databricks-sql-connector -- python -c "from databricks import sql; print('ok')"
uv run --with 'requests,click' -- python my_script.py
```

This creates an ephemeral virtual environment — no global pollution, no broken system packages.

# C++

If you removed headers, you have to also remove the relevant deps from the BUILD file. And the same goes for adding headers, you would need to add in the BUILD file deps. If you add headers to a .cpp file, you can add the deps to implementation_deps.

# HTML / Visual Output

Any HTML I generate or update — visual-explainer pages (diagrams, diff/plan reviews, slides, project recaps), dataviz output, or ad-hoc standalone HTML — **must include a light/dark theme toggle**. Requirements:

- A visible control (button/switch) that flips between light and dark.
- Default to the OS preference via `prefers-color-scheme`, then let the toggle override it.
- Drive colors from CSS custom properties (or an equivalent single source) so both themes stay legible — never hard-code a single palette that only reads well one way.
- Self-contained: the toggle works offline with no external requests (inline script/CSS), consistent with the "standalone HTML" goal.

This applies even when the underlying skill's template doesn't add one — patch it in on generation.

# Agent Teams (TeamCreate)

Agent Teams is an experimental Claude Code feature for **orchestration with visibility**, not parallel speed. Use it when the user explicitly asks for a "team", "teammates", "swarm", or "agent team". For fire-and-forget parallel work, use bare `Agent` (subagents) instead — those don't need TeamCreate.

**Default mode:** `teammateMode: "in-process"` (set in `~/.claude/settings.json`). All teammates share the main window; the user navigates between them with **Shift+↑ / Shift+↓**. No extra tmux panes, no external tmux socket — one clean terminal, one context per teammate.

**Why in-process:**
- The main window is the **orchestration viewport** — the user watches the lead agent (you) coordinate the team from a single pane.
- Teammates are individually enterable and reviewable via Shift+↑/↓ (unlike subagents, which are fire-and-forget).
- No pane-too-small failures, no separate tmux server, standard tmux navigation still works around it.

**How to spawn a team:**
1. `TeamCreate` — creates the team container. Fields: `team_name`, `description`, `agent_type`.
2. `Agent` with `team_name: <same>` and a `name:` — spawns each teammate as a persistent peer. Address later via `SendMessage({to: name})`.

**TeamCreate vs bare Agent — when to use which:**
- **TeamCreate + Agent(team_name=...)** — persistent peers you'll send follow-up messages to (`SendMessage`), user wants to watch/enter individual agents, work spans multiple turns.
- **Bare Agent (no team_name)** — fire-and-forget, returns one summary, fastest for parallel research / independent lookups.

**Your role as lead:** coordinate, summarize, and route. Don't duplicate work the teammates are doing. Use `SendMessage` to give teammates follow-ups; the user uses Shift+↑/↓ to enter any teammate's terminal directly.

**Override the default per-launch** (rarely needed): `claude --teammate-mode <auto|tmux|in-process>`. `tmux` mode opens an external tiled grid on a dedicated socket (`claude-swarm-<pid>`) — use only if the user explicitly asks for a grid layout.
