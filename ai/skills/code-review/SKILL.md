---
name: code-review
description: Perform a code review on the git diff between the current branch and master. Use when reviewing code changes for correctness, security, performance, and maintainability.
disable-model-invocation: true
---

# Code Review

Task: Perform a code review on this `git diff` (current branch vs master).

Goals:
- Assess the code for correctness, security, performance, readability, and maintainability.
- Identify potential bugs, anti-patterns, or missing error handling.
- Point out unclear or overly complex logic.
- Suggest improvements in naming, structure, or documentation where helpful.
- Flag any security or performance concerns.
- Ignore formatting issues. That gets fixed as part of pre-commit hooks.

Instructions:
- Focus only on the code introduced or modified in this diff.
- Be concise but thorough — highlight meaningful issues, not trivial nits.
- For each issue found, provide:
  1. **Location** (file + function or snippet reference)
  2. **Problem** (short description)
  3. **Suggestion** (practical fix or improvement)

Output format:
- Use bullet points.
- If no issues are found, respond with: `No issues found.`
