---
name: deslop
description: Simplify and refine code or long documents for clarity, consistency, and maintainability, without changing what they do or say. Use when asked to clean up recent changes, at the review step of a task, or as a final pass over long documents to strip filler and AI-sounding phrasing.
---

# Deslop

Simplify recently changed code or a finished document without changing what it
does or says. For code, work on the recently modified sections (the diff against
the repository's default branch, for example `master` or `main`) unless told
otherwise.

## Code

1. Preserve functionality. Change how the code does something, never what it
   does. All features, outputs and behaviours stay intact.

2. Improve clarity:
   - reduce unnecessary complexity and nesting;
   - remove redundant code and abstractions;
   - use clear variable and function names;
   - consolidate related logic;
   - remove comments that describe obvious code;
   - avoid nested ternary operators; prefer switch statements or if/else chains
     for several conditions;
   - choose explicit code over compact code;
   - remove defensive checks or try/catch blocks that are unusual for that part
     of the codebase, but only where the surrounding code shows they cannot
     trigger (for example, input already validated by the caller). Keep the
     existing behaviour on failure.

3. Keep the balance. Do not:
   - reduce clarity or maintainability for the sake of brevity;
   - introduce clever solutions that are hard to follow;
   - merge too many concerns into one function or component;
   - remove abstractions that help the code's organisation;
   - trade readability for fewer lines (nested ternaries, dense one-liners);
   - make the code harder to debug or extend.

Process:

1. Identify the recently modified sections.
2. Look for changes that improve consistency and readability.
3. Apply the project's own conventions and coding standards.
4. Check that all functionality is unchanged.
5. Check that the result is simpler and easier to maintain.
6. Mention only the changes that affect how the code is understood.

## Documents

For a long document (report, README, plan, rule or skill file):

1. Keep every fact, number, path, command, link and code block.
2. Remove the patterns listed in `~/.claude/rules/writing.md`. For the full
   catalogue, load the `wikipedia-ai-writing` skill.
3. Cut sentences that restate a heading or the previous paragraph, and closing
   summaries.
4. Use plain verbs and concrete nouns, and split long sentences.
5. Leave the structure as it is unless two sections say the same thing.
