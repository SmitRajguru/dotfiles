---
name: ask-async
description: Ask the user a question during an unattended run and wait a limited time for the answer, both in chat and in a Slack thread that is polled for a reply; the recommended default applies if nobody answers. Use when an unattended run reaches a question its plan does not answer (see the unattended-runs section of ~/.claude/rules/workflow.md).
---

# Ask while the user is away

Only the main session runs this. A subagent with an open question returns it to
the main session instead.

## Rules for Slack messages

- Post only the question, the options, the default, short status lines
  ("answer received", "default applied") and a copy of an answer given in chat.
  Never paste code, file contents, logs, data or secrets; if a chat answer
  contains any, post a one-line summary of it instead.
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
   `status: pending`, `slack_done: no`, the time the poll job is created, and an
   empty list of handled replies.
6. Schedule the poll with CronCreate, recurring every 2 minutes
   (`*/2 * * * *`). The prompt must stand on its own and start with the token
   `ask-async poll <question-id>`, by which the job is found later, for example:

   > ask-async poll <question-id>. Follow ~/.claude/skills/ask-async/SKILL.md.
   > Read <question file>. If its status is answered or defaulted: if
   > slack_done is no, post the pending thread reply and reaction for that
   > outcome, and set slack_done to yes if both succeed; once slack_done is
   > yes, find this job with CronList by the token above, CronDelete it and
   > stop. If the status is pending, read Slack thread <channel>/<ts> with
   > slack_read_thread (detailed format, which gives each reply's author and
   > ts). If the read fails, do nothing this round. Consider only replies by
   > the user (<user id>) that do not start with "Claude ->" and are not in the
   > handled list. A `wait` reply or a clarification: handle it as the Answers
   > section below says and keep polling. An answer: record it, set the status
   > to answered, then reply in the thread "`Claude ->` Answer received.
   > Continuing." and add the answered reaction (AGENT_SLACK_DONE_EMOJI, or
   > white_check_mark), set slack_done to yes if both succeed, CronDelete this
   > job if so, and resume <step> with the answer. No answer and past the
   > deadline in the question file: set the status to defaulted, reply
   > "`Claude ->` No reply; applied the default: <option letter>." and add the
   > timed-out reaction (AGENT_SLACK_TIMEOUT_EMOJI, or x), set slack_done as
   > above, CronDelete this job if so, and resume <step> with the default.
   > Otherwise do nothing.

7. Ask the same question in the chat reply, in the same layout, with the Slack
   link and the deadline; in chat, say "reply here or in the Slack thread"
   instead of "reply in this thread". Then end the turn. The poll only runs while the
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
- A reply of `wait` moves the current deadline 30 minutes later; `wait <minutes>`
  moves it that many minutes later. The deadline never moves earlier. Record
  the reply as handled (its ts, or "chat <HH:MM>" for one typed in chat),
  update the deadline in the question file, and post
  "`Claude ->` Waiting until **<HH:MM> PT**." in the thread. If the new
  deadline is more than 6 days after the poll job was created, recreate the
  job first, as described under destructive steps, because recurring jobs
  expire after 7 days. A question with no deadline (a destructive step) has
  nothing to extend: reply "`Claude ->` This question has no deadline; the
  run waits for your answer."
- An answer typed in chat wins if it arrives while the status is pending:
  record it and set the status to answered, then post
  "`Claude ->` Answer given in the session: **<answer>**" in the thread (a
  summary instead if the answer holds code or data) and add the answered
  reaction. If both succeed, set slack_done to yes and CronDelete the job;
  otherwise leave the job to retry them. The thread then shows every answer,
  wherever it was given.
- Reactions on the question message (the thread's parent), added with
  `slack_add_reaction`, show each question's outcome at a glance:
  - answered, from Slack or from chat: the emoji named in
    `AGENT_SLACK_DONE_EMOJI`, or `white_check_mark` if that is unset;
  - timed out, with the run continuing on the default: the emoji named in
    `AGENT_SLACK_TIMEOUT_EMOJI`, or `x` if that is unset.
- Every path checks the question file first. The answer or default is applied
  only on the change from pending, so it happens once; only the Slack
  acknowledgement and reaction are retried until slack_done is yes. Turns in
  one session never overlap, so this check is enough to stop a question being
  resolved twice.
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
