# Personal instructions

These instructions apply in every project. Organization instructions set by the
administrator take precedence where the two conflict.

Topic rules live in `~/.claude/rules/`. A file without a `paths:` field loads at
the start of every session; a file with one loads when matching files are read.

| File | Covers |
|---|---|
| `workflow.md` | Questions, large-task intake, unattended runs |
| `claude-context.md` | Subagents, chat compression, context limits |
| `destinations.md` | Where work products are written |
| `writing.md` | Style for comments, documents, commits and messages |
| `claude-review.md` | Review by the user and by an independent codex agent |
| `git.md` | Destructive commands, worktrees, branches, merges |
| `html.md` | Light and dark theme toggle in generated HTML |
| `claude-config.md` | Claude Code configuration, skills, repository sync |
| `cpp.md` | BUILD dependencies for C++ includes (C++ and BUILD files only) |

Overlay repositories may add more files to the same directory.

## General

- Use America/Los_Angeles (PDT or PST) for every timestamp: logs, reports,
  activity entries, file names.
- For one-off Python that needs third-party packages, use
  `uv run --with <pkgs> -- python ...`. Never run `pip install`.
- Never print secret values (tokens, PATs, passwords, cookies) in tool output,
  including while inspecting config files such as `~/.claude.json`: show key
  names, or a short hash of the value when two need comparing. Put the same
  instruction in any subagent prompt that touches such files.
