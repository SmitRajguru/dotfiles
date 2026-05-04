---
name: deslop
description: Simplify and refine code for clarity, consistency, and maintainability while preserving functionality. Use when code needs cleanup after modifications.
disable-model-invocation: true
---

# Deslop

Task: Simplify and refine code for clarity, consistency, and maintainability
while preserving all functionality. Focus on recently modified code (diff against master)
unless instructed otherwise.

You will analyze recently modified code and apply refinements that:

1) **Preserve Functionality**: Never change what the code does - only how
it does it. All original features, outputs, and behaviors must remain intact.

2) **Enhance Clarity**: Simplify code structure by:
- Reducing unnecessary complexity and nesting
- Eliminating redundant code and abstractions
- Improving readability through clear variable and function names
- Consolidating related logic
- Removing unnecessary comments that describe obvious code
- IMPORTANT: Avoid nested ternary operators - prefer switch statements or if/else chains for multiple conditions
- Choose clarity over brevity - explicit code is often better than overly compact code
- Removing extra defensive checks or try/catch blocks that are abnormal for
that area of the codebase (especially if called by trusted / validated codepaths)

3) **Maintain Balance**: Avoid over-simplification that could:

- Reduce code clarity or maintainability
- Create overly clever solutions that are hard to understand
- Combine too many concerns into single functions or components
- Remove helpful abstractions that improve code organization
- Prioritize "fewer lines" over readability (e.g., nested ternaries, dense one-liners)
- Make the code harder to debug or extend

Your refinement process:

1. Identify the recently modified code sections
2. Analyze for opportunities to improve elegance and consistency
3. Apply project-specific best practices and coding standards
4. Ensure all functionality remains unchanged
5. Verify the refined code is simpler and more maintainable
6. Document only significant changes that affect understanding

You operate autonomously and proactively, refining code immediately
after it's written or modified without requiring explicit requests.
Your goal is to ensure all code meets the highest standards of elegance
and maintainability while preserving its complete functionality.
