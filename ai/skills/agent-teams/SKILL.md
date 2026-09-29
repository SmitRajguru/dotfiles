---
name: agent-teams
description: How to run Claude Code agent teams (TeamCreate with persistent, addressable teammates) and when to use them instead of plain subagents. Invoke manually with /agent-teams when the user asks for a team, teammates, a swarm or an agent team.
disable-model-invocation: true
---

# Agent teams

Agent teams are an experimental Claude Code feature for orchestration that the
user can watch. They do not make parallel work faster; plain subagents are the
better choice for that.

The feature needs `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. A managed settings
layer can force it off, in which case TeamCreate is not available and the
request should fall back to plain subagents. Say so to the user.

## Mode

`teammateMode` is `in-process` in `~/.claude/settings.json`. All teammates share
the main terminal window, and the user moves between them with Shift+Up and
Shift+Down. No extra tmux panes or tmux server are created.

The main window stays the lead agent's view, where the user watches the
coordination. Each teammate can be entered and reviewed on its own, which
plain subagents do not allow.

To override the mode for one launch, run
`claude --teammate-mode <auto|tmux|in-process>`. `tmux` mode opens a tiled grid
on a dedicated socket (`claude-swarm-<pid>`); use it only when the user asks for
a grid.

## Starting a team

1. `TeamCreate` creates the team. Fields: `team_name`, `description`,
   `agent_type`.
2. `Agent` with `team_name` set to the same value and a `name` spawns each
   teammate as a persistent peer. Address it later with
   `SendMessage({to: name})`.

## Team or plain subagents

Use a team when the teammates need follow-up messages, the user wants to watch
or enter individual agents, or the work spans several turns. Use plain `Agent`
calls without `team_name` for one-shot parallel research or lookups that return
a single summary.

## Role of the lead

The lead coordinates, summarises and routes work. It does not repeat work that
a teammate is doing. It sends follow-ups with `SendMessage`; the user can also
enter any teammate directly.
