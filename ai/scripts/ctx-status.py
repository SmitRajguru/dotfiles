#!/usr/bin/env python3
"""Claude Code status-line widget: context fill + warning indicator.

Reads ccstatusline's session JSON from stdin, scans the tail of the
transcript JSONL for the last assistant turn's usage, computes context
fill against the model's max window, and prints a colored
``Ctx X.XK (Y%)`` string. When fill reaches ``CTX_WARN_THRESHOLD``
(default 25%) a red ``(!)`` is appended; halfway between the threshold
and full a bold red ``(!!)`` is appended (compact / handoff territory).
"""
import json
import os
import subprocess
import sys

THRESHOLD = int(os.environ.get("CTX_WARN_THRESHOLD", "25"))


def model_max_tokens(model_id: str) -> int:
    return 1_000_000 if "[1m]" in (model_id or "").lower() else 200_000


def last_assistant_tokens(transcript: str):
    if not transcript or not os.path.exists(transcript):
        return None
    try:
        result = subprocess.run(
            ["tail", "-n", "300", transcript],
            capture_output=True,
            text=True,
            timeout=1,
        )
    except Exception:
        return None
    for line in reversed(result.stdout.splitlines()):
        if not line:
            continue
        try:
            turn = json.loads(line)
        except Exception:
            continue
        msg = turn.get("message") or {}
        if msg.get("role") != "assistant":
            continue
        usage = msg.get("usage") or {}
        if not usage:
            continue
        return (
            usage.get("input_tokens", 0)
            + usage.get("cache_creation_input_tokens", 0)
            + usage.get("cache_read_input_tokens", 0)
        )
    return None


def colored(text: str, code: str) -> str:
    return f"\x1b[{code}m{text}\x1b[0m"


def main() -> None:
    try:
        session = json.load(sys.stdin)
    except Exception:
        return
    used = last_assistant_tokens(session.get("transcript_path"))
    if used is None:
        return
    max_tokens = model_max_tokens((session.get("model") or {}).get("id", ""))
    if max_tokens <= 0:
        return

    fill_pct = 100.0 * used / max_tokens
    used_k = used / 1000.0
    label = f"Ctx {used_k:.1f}K ({fill_pct:.0f}%)"
    danger_threshold = (THRESHOLD + 100) / 2

    if fill_pct >= danger_threshold:
        sys.stdout.write(colored(f"{label} (!!)", "1;31"))
    elif fill_pct >= THRESHOLD:
        sys.stdout.write(colored(f"{label} (!)", "31"))
    elif fill_pct >= THRESHOLD * 0.7:
        sys.stdout.write(colored(label, "33"))
    else:
        sys.stdout.write(colored(label, "32"))


if __name__ == "__main__":
    main()
