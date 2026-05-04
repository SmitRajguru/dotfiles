---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when the user wants to stress-test a plan, get grilled on their design, or says "grill me".
---

# grill-me

Stress-test the user's plan or design by interviewing them relentlessly until every branch of the decision tree is resolved.

## When to use

- User says "grill me", "stress-test this", "poke holes", "interview me on this".
- User has shared a plan or design and wants every assumption surfaced before they commit.
- A pre-implementation alignment pass would catch ambiguity that implementation would otherwise expose mid-work.

## Procedure

### 1. Classify the project

Decide whether this is a **coding project** (touches a codebase, file paths, build system, runtime behavior) or a **non-coding project** (process design, doc structure, planning, org work).

If unclear, ask once.

### 2. Run the matching protocol

#### Coding projects

> Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree resolving dependencies between decisions one by one.
>
> If a question can be answered by exploring the codebase, explore the codebase instead.
>
> For each question, provide your recommended answer.

#### Non-coding projects

> Interview me relentlessly about every aspect of this until we reach a shared understanding. Walk down each branch of the design tree resolving dependencies between decisions one by one.
>
> For each question, provide your recommended answer.

### 3. Question discipline

- **Walk the tree depth-first.** Resolve one branch fully before opening the next. Don't fan out 10 parallel open questions — that creates a swamp instead of a path.
- **Surface dependencies explicitly.** If decision B depends on decision A, say so and resolve A first.
- **Always include your recommended answer** with each question, plus the reasoning. The user should be reacting to a specific proposal, not a blank prompt.
- **Prefer `AskUserQuestion`** for crisp multi-choice decisions. Use freeform when the answer space is open.
- **For coding projects: explore before asking.** If the answer is in the code (existing pattern, current behavior, signature, test coverage), read the code instead of asking. Only ask the user for things only they know — intent, priorities, tradeoffs, constraints.
- **No softballs.** Push on assumptions, edge cases, failure modes, scope boundaries, and "what happens if X" scenarios. Polite is fine; deferential is not.

### 4. Stop conditions

End the grill when one of:
- Every open branch has a resolved decision and no new dependent questions surface.
- The user says "stop", "enough", "good", or otherwise signals they're done.
- The remaining questions are clearly out of scope for the current plan.

When stopping, write a tight summary of the resolved decisions so the user can copy it into a plan/PRD/commit.
