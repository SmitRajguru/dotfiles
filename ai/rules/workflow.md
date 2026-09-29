# Workflow

## Questions

Ask with AskUserQuestion whenever requirements are unclear, a design choice has
real tradeoffs, the scope is uncertain, or an assumption would otherwise be made
silently. The user prefers more questions to fewer. Put the recommended option
first and label it "(Recommended)".

Ask early. Questions belong in planning, before the work starts, so that the
rest of the task can run while the user is away.

## Large tasks

A task is large when any of the following holds:

- it touches more than about three files, or more than one repository;
- it needs research or analysis across many sources;
- the goal is ambiguous or open-ended;
- it is likely to take more than about 30 minutes of agent work;
- the user says AFK, autonomous, overnight or similar.

For a large task, name the signal that applies and offer to run the `grill-me`
skill before doing anything else. The user may decline. The grill continues
until the goal, the scope, the constraints, the destination for work products
(see `destinations.md`) and the limits on unattended work are settled. Write the
resulting decisions to the task directory as the plan, then start.

## Unattended runs

A run is unattended once the plan is settled and the user has agreed during
intake to let it run without them. Without that agreement, keep asking as
usual.

Allowed without asking: editing files, running builds and tests, spawning
subagents, committing to a feature branch in a worktree under `~/worktrees/`,
writing to the task directory, and sending PushNotifications.

Not allowed without asking: pushing (except `~/dotfiles`, which
`claude-config.md` requires to be pushed after every change), opening or
updating pull requests, posting to Slack (except the `ask-async` question
thread), changing Jira or Confluence, or any other action visible outside this
machine. The plan may grant more, for example pushing a private repository once
review is done.

When a question comes up that the plan does not answer, use the `ask-async`
skill. It asks in the chat and in a Slack thread in `$AGENT_SLACK_CHANNEL`,
sends a PushNotification, polls the thread every 2 minutes, and applies the
recommended default when 10 minutes pass without an answer. Posting that
question and its short status lines is the one Slack action allowed without
asking.

Record each question and the answer or default that was used in the task
directory, and list the defaults at the top of the final report. Destructive or
irreversible steps are the exception: for those, wait for an answer however
long it takes.

Subagents cannot run this protocol. A subagent that hits an open question
returns it to the main thread instead of guessing.

At the end of the run, write the final report to the task directory, reply with
a short summary and the report path, and send a PushNotification.
