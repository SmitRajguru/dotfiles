# Context and delegation

Keep the main conversation small, so that a long task is not auto-compacted
several times on the way.

## Delegation

Delegate to a subagent by default for:

- searches that span more than about three files;
- reading large files, logs, or test and CI output;
- reviews and audits;
- independent units of work that can run in parallel.

The main thread keeps the decisions, the edits it already has context for, and
short summaries. A subagent that produces bulky output writes it to the task
directory and returns about 15 lines plus the file path.

A subagent cannot see this conversation, so its prompt has to stand on its own.
When several subagents share instructions, write the instructions to a file once
and point each prompt at that file.

Agent choice:

- `cavecrew-investigator` to locate code, `cavecrew-builder` for edits to one or
  two files, `cavecrew-reviewer` for a quick check of a subagent's diff. Their
  output is compressed. Reviews and audits of finished work go to codex (see
  `claude-review.md`).
- `Explore` for broad read-only sweeps, `general-purpose` for multi-step work.

Model choice: `haiku` for mechanical lookups and validation, `sonnet` for
routine edits and research, the inherited model for design, debugging and
review.

## Chat compression

The caveman plugin runs at level `full` for chat replies and subagent summaries.
If the SessionStart hook has not switched it on, write chat replies in the same
terse style anyway: no articles, filler or pleasantries, fragments allowed,
technical terms exact.

Use normal English in anything written to a file, code comments, commits, pull
requests, Slack and Jira drafts, AskUserQuestion text, and warnings about
security or irreversible actions.

## Context limits

The status line shows context use as `Ctx X.XK (Y%)`. It turns red with `(!)` at
`CTX_WARN_THRESHOLD` (25% by default) and adds `(!!)` at 62.5%. At `(!)`,
delegate more and read files in sections rather than whole. At `(!!)`, or when a
long task is only partly done, suggest a handoff with the `session-handoff`
skill.
