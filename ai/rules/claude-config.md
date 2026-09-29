# Claude Code configuration

- User configuration (agents, settings, commands, rules, `CLAUDE.md`, scheduled
  tasks) lives in `~/.claude/`. A repository's own `.claude/` directory belongs
  to that repository; do not put user configuration there unless that is the
  stated intent.
- `~/dotfiles` holds shell, tmux and prompt configuration and the general Claude
  and Cursor configuration. After changing any file it tracks, commit, push and
  run `~/dotfiles/sync.sh` straight away. Overlay repositories that add files to
  `~/.claude/` or `$ZDOTDIR/local/` follow their own sync rules.
- `~/dotfiles` is public. Keep employer-specific names, hosts and paths out of
  it; a pre-commit hook checks staged files for them.
- Create skills, rules and agents in their source repository, not in
  `~/.claude/`: `~/dotfiles/ai/` for general ones, the overlay repository for
  employer-specific ones. Then run that repository's `setup.sh` to link them.
- After creating or changing a skill, have a haiku subagent check it against the
  skill guidelines and its frontmatter format, then run `tokei ~/.claude/skills`.
  If a file is over 500 lines, ask the user whether to cut content or to move
  reference material into separate files.
- Rule files whose names start with `claude-` stay Claude-only. Setup mirrors
  the other rule files into `~/.cursor/rules/`.
