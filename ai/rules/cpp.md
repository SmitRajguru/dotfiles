---
paths:
  - "**/*.h"
  - "**/*.hpp"
  - "**/*.cc"
  - "**/*.cpp"
  - "**/BUILD"
  - "**/BUILD.bazel"
---

# C++ includes and BUILD dependencies

When an `#include` is removed, remove the matching dependency from the BUILD
target too. When one is added, add the dependency. For includes added to a
`.cc` or `.cpp` file, the dependency can go in `implementation_deps`.
