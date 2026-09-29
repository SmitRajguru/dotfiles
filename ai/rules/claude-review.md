# Code review

Non-trivial code is reviewed twice: by the user, and by an independent codex
agent (a GPT model through the `cursor-agent` CLI). The codex reviewer comes
from a different model family and has none of this session's context, which is
the reason for using it. The model is picked when the review runs, as the
strongest one Cursor offers at that time; never pin a model name in a rule,
skill or prompt.

Write code that holds up under both:

- Make it self-contained. The reviewer sees the diff, not the conversation. If
  a choice only makes sense given earlier discussion, pick a pattern that does
  not depend on it, or add a short comment that gives the reason.
- Prefer the idiomatic approach. If a simpler version is nearly as good, use it.
- Leave out speculative abstractions, dead code and unfinished stubs.
- Test behaviour, not plumbing. If something cannot be verified end to end, say
  so in the reply.

When the user asks for a review or an audit, or an unattended loop reaches its
review step, delegate to codex with the `codex-review` skill rather than
reviewing your own work. If that skill is not available, say so; do not fall
back to a self-review without mentioning it.

Treat codex findings as real. Check each one against the code. If a finding is
wrong, say why; otherwise fix it.
