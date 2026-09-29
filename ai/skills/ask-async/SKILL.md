---
name: ask-async
description: Ask the user a question during an unattended run and wait a limited time for the answer, both in chat and in a Slack thread that is polled for a reply; the recommended default applies if nobody answers. Use when an unattended run reaches a question its plan does not answer (see the unattended-runs section of ~/.claude/rules/workflow.md).
---

# Ask while the user is away

Only the main session runs this. A subagent with an open question returns it to
the main session instead.

## Rules for Slack messages

- Post only the question, the options, the default and short status lines
  ("answer received", "default applied"). Never paste code, file contents,
  logs, data, secrets, or the text of an answer given in chat.
- Start every message the agent posts with the prefix `` `Claude ->` ``,
  written as inline code so that Slack renders it differently. Messages sent
  through the Slack tools appear under the user's own name; the prefix tells
  both the user and the agent which messages came from the agent. When
  reading, a message that starts with `Claude ->`, with or without backticks,
  is the agent's.

## Asking

Steps 2 to 7 take seconds; do them back to back, with nothing in between, so
that the chat question and the Slack question appear at the same time and the
full waiting time is left.

1. Decide the recommended default and phrase the question so that someone
   reading it on a phone, with no other context, can answer in one line. Pick
   a question ID: `<task-slug>-q<n>`.
2. Set the deadline to 10 minutes from now.
3. Post the question as a new message in `$AGENT_SLACK_CHANNEL` with
   `slack_send_message`, and keep the returned `ts` and `message_link`:

   ```
   `Claude ->` **<title: the work and its goal, e.g. "Instructions overhaul: pick the review model">**

   **Question:** <one plain sentence>
   - **A)** <option> _(default)_
   - **B)** <option>

   **Note:** <the context needed to answer: what is being decided and what each option leads to, in one or two sentences>
   **Deadline:** reply in this thread by **<HH:MM> PT**. Without a reply, **<default option>** is used. Reply `wait` for 30 more minutes, or `wait <minutes>`. `<question-id>`
   ```

   Use Slack markdown as shown: a bold title that names the work rather than
   "question from an unattended run", the options as an indented list, a blank
   line, then the note and the deadline. Write for a reader who has not seen
   the session; no internal jargon, file names or IDs except the question ID
   at the end.

   If `AGENT_SLACK_CHANNEL` is unset or the post fails, follow "Without Slack"
   below instead of steps 3 to 6.
4. Send a PushNotification with the question and the default.
5. Write the question file `<task dir>/<question-id>.md` with: the question,
   the options, the default, the channel, the `ts`, the link, the deadline,
   `status: pending`, and an empty list of handled reply `ts` values.
6. Schedule the poll with CronCreate, recurring every 2 minutes
   (`*/2 * * * *`). The prompt must stand on its own and start with the token
   `ask-async poll <question-id>`, by which the job is found later, for example:

   > ask-async poll <question-id>. Read <question file>; if its status is not
   > pending, find this job with CronList by the token above, CronDelete it and
   > stop. Otherwise read Slack thread <channel>/<ts> with slack_read_thread
   > (detailed format, which gives each reply's author and ts). If the read
   > fails, do nothing this round. Consider only replies written by the user
   > that do not start with "Claude ->" and whose ts is not in the handled list.
   > If such a reply is `wait` or `wait <minutes>`, or asks for clarification,
   > handle it as the skill describes and keep polling. If it is an answer:
   > set the status to answered and record the reply, CronDelete this job,
   > reply in the thread "`Claude ->` Answer received. Continuing.", add the
   > check-mark reaction to the question message, and resume <step> with that
   > answer. Otherwise, if it is past the deadline in the question file: set
   > the status to defaulted, CronDelete this job, reply "`Claude ->` No
   > reply; applied the default: <option letter>.", and resume <step> with the
   > default. Otherwise do nothing.

7. Ask the same question in the chat reply, in the same layout, with the Slack
   link and the deadline, and end the turn. The poll only runs while the
   session is idle. Subagents launched before the turn ends may keep working;
   when one finishes, check the question file before doing anything that
   depends on the answer.

## Answers

- The answer is the first unhandled, non-clarifying reply written by the user
  (not by someone else in the channel, and without the prefix) that the poll
  sees while the status is pending. A reply that matches none of the options
  is taken as given.
- A reply that asks for clarification is not an answer. Answer it in the
  thread, where the user asked, and in chat. In Slack, the answer may only
  restate or explain the question and its options, under the same rules as the
  question itself. Record the reply's ts as handled, move the deadline to at
  least 5 minutes after the clarification was posted, update the question file,
  say the new deadline in the thread, and keep polling.
- A reply of `wait` extends the deadline by 30 minutes from the time of the
  reply; `wait <minutes>` by that many minutes. Record the reply's ts as
  handled, update the deadline in the question file, and post
  "`Claude ->` Waiting until **<HH:MM> PT**." in the thread. The same words typed
  in chat do the same.
- An answer typed in chat wins if it arrives while the status is pending: set
  the status to answered, CronDelete the job, post
  "`Claude ->` Answered in the session." in the thread without the answer text,
  and add the check-mark reaction to the question message.
- The check mark: once a question is answered, from Slack or from chat, add a
  reaction to the question message (the thread's parent) with
  `slack_add_reaction`, using the emoji named in `AGENT_SLACK_DONE_EMOJI`, or
  `white_check_mark` if that is unset. A question that ends with the default
  gets no check mark, so the channel shows at a glance which questions the user
  answered.
- Every path checks the question file first and does nothing if the status is
  no longer pending. Turns in one session never overlap, so this check is
  enough to stop a question being resolved twice.
- The default is applied only after a successful thread read shows no reply.
  The deadline is met at the first poll at or after it, so up to about two
  minutes late.
- If the agent regains control after the deadline and the question is still
  pending, run the poll steps once by hand.
- Once the status is answered or defaulted, later replies are not read.

## Without Slack

Say in the chat that Slack is not available and why, and send the
PushNotification. Write the question file without the Slack fields. Schedule a
recurring CronCreate job every 2 minutes with the prompt:

> ask-async poll <question-id>. Read <question file>; if its status is not
> pending, find this job with CronList by the token above, CronDelete it and
> stop. Otherwise, if it is past the deadline in the question file: set the
> status to defaulted, CronDelete this job, and resume <step> with the default
> <X>. Otherwise do nothing.

Then ask in chat and end the turn as in step 7. An answer in chat follows the
chat rule above, without the Slack note. A one-shot job pinned to the deadline
is not enough: it never fires if the session is busy at that minute.

## Destructive or irreversible steps

There is no deadline and no default; the agent waits for an answer however long
it takes.

- Write the question file with `deadline: none` and `default: none`, and say in
  the question that the run is waiting.
- Use the poll prompt above without the deadline branch. Without Slack, no poll
  is needed; the question stays in chat until the user answers.
- Record `created` and `last_reminder` dates in the question file. On the first
  poll of each day, post "`Claude ->` Still waiting on this question." in the
  thread and update `last_reminder`.
- Recurring CronCreate jobs expire after 7 days. On the first poll six days or
  more after `created`, create a new poll job with the same prompt, CronDelete
  the old one, and update `created`.

## Afterwards

List each question with its answer or the applied default at the top of the
final report.
