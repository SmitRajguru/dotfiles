---
name: session-handoff
description: Curate a session handoff bundle so a fresh Claude session can pick up where this one left off. Writes context, knowledge, files-of-interest, plan, and open questions as .md files under `${LLM_CONTEXT_DIR:-$HOME/.local/share/llm_context}/<slug>/`, then prints AND saves a resume prompt for the next agent. Use when the user asks to hand off, save context, prepare a handoff, fork a session, or compact + continue elsewhere. Also good to suggest proactively when context fill is high (status-line `(!)` / `(!!)`) and the task is mid-flight.
---

# session-handoff

Curated handoff bundle for the next Claude session. The goal is not a transcript dump — it's a tight, hand-picked set of `.md` files plus a ready-to-paste resume prompt.

## When to use

Trigger when:

- User says "hand off", "save context", "fork this session", "compact and continue", "write up where we are", or similar.
- Context fill is high (status line `(!)` / `(!!)`) AND the task is non-trivial AND will continue in a new session — proactively suggest this skill, don't just silently compact.
- A long task is wrapping up the active phase but more work remains and the user wants a fresh window.

Skip when:

- Task is trivially summarizable in a few lines — just summarize inline.
- Task is already done and no follow-up is expected.

## Procedure

### 1. Pick a slug

Propose a slug derived from the task (lowercase, hyphenated, no date — e.g. `unify-accel-shaper`, `latency-blame-investigation`). Ask the user via `AskUserQuestion` to confirm or override.

The base directory is `${LLM_CONTEXT_DIR:-$HOME/.local/share/llm_context}` — set `LLM_CONTEXT_DIR` in your Claude Code env (e.g. `~/.claude/settings.local.json` `env` block) to point at a shared / synced location. If `<base>/<slug>/` already exists, surface that to the user and ask whether to overwrite, append (e.g. `<slug>-2`), or pick a different name. Do not silently overwrite.

### 2. Create the directory

```bash
base="${LLM_CONTEXT_DIR:-$HOME/.local/share/llm_context}"
mkdir -p "$base/<slug>"
```

### 3. Write the bundle

Write each file with `Write`. Keep entries dense and signal-heavy — avoid filler, don't restate obvious things from the codebase. The next agent will read all five, so don't repeat content across files; cross-reference instead.

#### `context.md` — what we're doing & why

- **Goal:** one or two sentences.
- **Why now:** triggering ticket, incident, deadline, user ask. Include JIRA / PR links if relevant.
- **Current state:** where in the task we actually are (e.g. "draft PR open, CI failing on X", "design agreed, no code yet").
- **Constraints:** non-negotiables surfaced during the session (compliance, perf budgets, freeze windows).

#### `knowledge.md` — findings & gotchas

Non-obvious things discovered during the session that the next agent would otherwise have to rediscover. One bullet per finding, with file:line refs where applicable.

- Behaviors of code / systems that surprised us.
- Dead ends ruled out (and *why* they were dead ends — so the next agent doesn't retry them).
- Tribal knowledge from the user that isn't in any doc.

#### `files.md` — relevant file paths

Markdown table or bulleted list:

- Path → one-line role in this task.
- Group by purpose (e.g. "core", "tests", "tooling", "reference reads") if it helps.
- Include worktree path if relevant.

Skip files that are only incidentally touched — only list ones the next agent should actually open.

#### `plan.md` — next steps

Ordered list of concrete TODOs. Each item should be actionable on its own:

1. What to do.
2. Where (file / area).
3. Acceptance signal (test passes, build green, user confirms).

If the user already approved a plan in this session, paste / paraphrase it here verbatim — don't reinvent.

#### `open_questions.md` — unresolved items

Things the user hasn't decided yet, or that need investigation before continuing. For each: the question, options considered (if any), and what blocks resolution.

If there are no open questions, write the file with a single line: `_No open questions at handoff time._` — its presence confirms you considered it.

### 4. Write and print the resume prompt

Save `resume_prompt.md` in the same directory and print its contents to chat. The prompt must be self-contained — the next agent has no memory of this session.

Template (fill in the absolute path — resolve `${LLM_CONTEXT_DIR:-$HOME/.local/share/llm_context}/<slug>/` to a real path before printing, since the next agent will read it cold):

```markdown
You are resuming a task from a prior Claude Code session. The full handoff lives at:

`<absolute-path-to-handoff-dir>`

Read these files in order before doing anything else:

1. `context.md` — what we're doing and why
2. `plan.md` — the ordered next steps
3. `knowledge.md` — findings and gotchas from the prior session
4. `files.md` — relevant file paths and their roles
5. `open_questions.md` — anything unresolved

After reading all five, briefly summarize back to the user: the goal, the next step you'd take, and any open question that needs an answer first. Then wait for their go-ahead before acting (unless `plan.md` step 1 is unambiguous and low-risk).
```

If the work is in a worktree, mention the worktree path explicitly in the printed prompt so the user can `cd` there before pasting.

### 5. Tell the user

Show:

- The handoff directory path.
- Confirmation that `resume_prompt.md` was saved.
- The printed resume prompt (so they can copy-paste immediately).

## Notes

- Slug-only naming (no date) matches existing entries under `$LLM_CONTEXT_DIR`. If a slug collides, ask — don't auto-suffix.
- Don't include secrets, full diffs, or large code blobs. Reference paths and line ranges instead.
- If the user is mid-debug with a hypothesis tree, capture the *current* hypothesis and what would falsify it under `knowledge.md`, not just the conclusions.
- After writing the bundle, the user typically ends the session — don't kick off new work in this session unless asked.
