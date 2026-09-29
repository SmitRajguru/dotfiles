# Work-product destinations

Two directories hold work that should outlast the session:

- `$LLM_WORKSPACE_DIR` holds material that both the user and agents read:
  plans, status files, reports, analysis, static pages.
- `$LLM_CONTEXT_DIR` holds material that mainly agents read: handoff bundles,
  context snapshots, notes for later sessions.

Each task gets its own directory, `<root>/<task-slug>/`, with the same slug in
both roots when a task uses both. The layout inside a task directory is up to
the task.

Ask for a destination, with a suggestion, when a large task is planned (see
`workflow.md`) and whenever the output is a report or an analysis. Small edits
and quick answers need none; the git history records them. Once the destination
is chosen, tell the user the path.

If `LLM_WORKSPACE_DIR` is unset, ask the user where to write. If
`LLM_CONTEXT_DIR` is unset, the `session-handoff` skill falls back to
`~/.local/share/llm_context`; for anything else, ask.
