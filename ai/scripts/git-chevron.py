#!/usr/bin/env python3
"""ccstatusline custom widget: chevron separator that only appears in a git work tree.

Reads the session JSON from stdin, checks whether ``cwd`` is inside a git
working tree, and emits ``" ❯ "`` (with a dim color) when it is. Outside a
git repo it emits nothing — ccstatusline's separator-collapse logic then
naturally closes the gap between the surrounding widgets.
"""
import json
import subprocess
import sys


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0

    cwd = data.get("cwd") or data.get("workspace", {}).get("current_dir")
    if not cwd:
        return 0

    try:
        result = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--is-inside-work-tree"],
            capture_output=True,
            text=True,
            timeout=1,
        )
    except Exception:
        return 0

    if result.returncode == 0 and result.stdout.strip() == "true":
        # Wrap the surrounding spaces inside the ANSI sequence so ccstatusline's
        # .trim() on the custom-command output doesn't eat them — the first and
        # last chars must be non-whitespace.
        sys.stdout.write("\033[90m ❯ \033[0m")
    return 0


if __name__ == "__main__":
    sys.exit(main())
