---
name: review-observability
description: Reviews observability changes in CLI tools for telemetry usefulness and safety. Use when reviewing logs, metrics, traces, or events; verifying post-argparse initialization; ensuring telemetry failures cannot affect user-visible behavior or exit codes; and validating coverage of the tool's key operational questions.
disable-model-invocation: true
---

# Review Observability

Task: Review observability changes with priority on safety and operational usefulness.

## Scope

- Focus on changed files from the current git diff, plus directly related helper modules.
- Prioritize correctness and behavior risk over style issues.
- For one-shot scripts (for example migration scripts), require complete and reliable telemetry because reruns may be difficult.

## Required Checks

### 0) Reuse Existing Abstractions First

- Before proposing new wrappers or helper utilities, look for existing shared observability abstractions already used in the repository.
- Prefer reuse of established helpers when they match the tool/runtime boundary (language, framework, build system, and dependency constraints).
- Do not assume one subsystem's helper package is valid everywhere; respect project boundaries.
- If shared helper discovery is inconclusive, ask the user for the canonical helper location instead of inventing a new pattern.

### 1) Initialization Ordering

- Verify observability initialization happens only after successful argparse parsing.
- Ensure `--help`, missing arguments, and argument parsing failures do not initialize telemetry or emit usage logs.
- If the command has early `sys.exit(0)` paths, verify init is after those paths.

### 2) No Failure Side-Effects

- Observability failures must never change functional behavior, raise user-visible exceptions, or alter exit codes.
- Check for unguarded calls to:
  - setup/init (`setup_*_observability`, log handler setup, logger suppression)
  - events (`event_logger.emit`)
  - metrics (`create_counter`, `create_histogram`, `record`, `add`)
  - traces (`start_as_current_span`)
- In `except` and `finally` paths, telemetry must not mask the original exception.
- Verify exception policy is explicit and intentional:
  - runtime observability transport/runtime failures may be suppressed when required by tool reliability goals,
  - clear application misuse errors should not be silently swallowed.

### 2b) Wrapper Layering Consistency

- If a shared safe helper already enforces resilience policy, avoid adding redundant local try/except wrappers around the same operation.
- Flag duplicated protection layers unless there is a documented reason (for example, scope-specific fallback behavior).
- Prefer one canonical layer to own safety policy to avoid policy drift.

### 3) Goal-Oriented Coverage

Before scoring coverage, derive the key operator questions from the tool's purpose.
Then verify telemetry can answer those questions.

Use this baseline guidance:

- Actor/context: Who or what invoked the tool, when useful for accountability.
- Runtime context: Environment dimensions needed to interpret behavior (for example mode, target, source and destination when applicable).
- Duration/performance: Invocation and phase timing when runtime matters.
- Outcome/problem signals: Clear success/failure/interrupted states and actionable error context.

Do not require fields that are irrelevant to the tool. Require enough context to answer real operational questions for that specific workflow.

### 4) Data Correctness

- Confirm source and destination attributes are derived from the correct systems.
- Destination OS/version must come from destination context, not local values, unless intentionally documented.
- Step status values should be explicit and accurate (`ok`, `skipped`, `failed`).
- Skip paths should be represented in telemetry or intentionally documented as out of scope.

### 5) Failure Path Coverage

- Validate whether early failures (preflight checks, auth/connection/setup) are captured as intended.
- Check status mapping for `KeyboardInterrupt`, `SystemExit`, and generic exceptions.
- Confirm invocation finalization telemetry cannot replace or hide the root failure.

### 6) Payload Hygiene

- Flag potential sensitive data leakage in logs/events/spans.
- Ensure command line logging does not include secrets.
- Flag high-cardinality metric labels that can degrade observability systems.
- If a shared emitter/helper auto-adds standard metadata, avoid manual duplication at call sites unless override behavior is intentional and documented.

### 7) Operational Semantics and Maintainability

- Verify one-shot initialization semantics where intended (for example initialize-once helpers), and ensure degradation is visible enough for operators.
- Flag stale comments that no longer match control flow after observability refactors.
- Flag function-local imports unless they are required (for example to avoid cyclic dependencies or heavy optional imports).

## Severity Rubric

- `CRITICAL`: Can break tool behavior, alter exit status, or violate mandatory requirements.
- `HIGH`: Misleading or materially incorrect telemetry that harms incident/debug decisions.
- `MEDIUM`: Diagnosability gaps that do not break behavior.
- `LOW`: Minor consistency or maintainability issues.

## Output Format

Provide findings first, ordered by severity:

- `[SEVERITY] path::symbol`
  - Problem:
  - Risk:
  - Recommended fix:

Then include:

1. Requirement coverage checklist:
   - shared helper reuse assessment (PASS, FAIL, or ASK USER)
   - post-argparse initialization
   - no telemetry failure side-effects
   - exception policy consistency (suppression vs re-raise boundaries)
   - wrapper layering consistency (no redundant safety wrappers)
   - key tool-specific question coverage (list each question with PASS or FAIL)
   - duration/performance coverage (if applicable)
   - outcome/problem coverage
   - payload metadata consistency (no accidental duplication)
   - maintainability checks (stale comments and import hygiene)
2. Final recommendation: `APPROVE` or `REQUEST CHANGES`.

## Fast Workflow

1. Read staged or target diff for observability-related files.
2. Search for existing shared observability helpers used by nearby tools in the same subsystem.
3. Inspect surrounding code for init order, exception handling, and finally blocks.
4. Trace each emitted field to its source.
5. Validate wrapper layering, exception boundaries, and metadata injection consistency.
6. Validate requirement coverage, data correctness, and maintainability checks.
7. Return severity-ranked findings and final recommendation.
