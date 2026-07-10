#!/usr/bin/env python3
"""Claude Code status-line widget: context fill + warning indicator.

Reads ccstatusline's session JSON from stdin and prints a colored
``Ctx X.XK (Y%)`` string. Primary source is the ``context_window`` block
Claude Code ships in the payload (>= 2.1.x): exact used tokens + percent,
no transcript parsing. Falls back to scanning the tail of the transcript
JSONL for the last assistant turn's usage on older versions that don't
provide it.

When fill reaches ``CTX_WARN_THRESHOLD`` (default 25%) a red ``(!)`` is
appended; halfway between the threshold and full a bold red ``(!!)`` is
appended (compact / handoff territory).
"""
import json
import os
import subprocess
import sys

THRESHOLD = int(os.environ.get("CTX_WARN_THRESHOLD", "25"))


def model_max_tokens(model_id: str) -> int:
    return 1_000_000 if "[1m]" in (model_id or "").lower() else 200_000


def native_usage(session: dict):
    """Used-token count + fill percent straight from the payload.

    Returns (used_tokens, fill_pct) or None if the block is absent. The
    context_window block is authoritative and always current, so this
    avoids the transcript-tail scan entirely (that scan blanks whenever
    the last assistant-usage line falls outside the tail window — e.g.
    right after a burst of tool output).
    """
    cw = session.get("context_window") or {}
    if not cw:
        return None
    used = cw.get("total_input_tokens")
    if used is None:
        cur = cw.get("current_usage") or {}
        if cur:
            # `or 0` (not get-default): coerce present-but-null fields, which
            # would otherwise TypeError on the sum and crash the widget.
            used = (
                (cur.get("input_tokens") or 0)
                + (cur.get("cache_creation_input_tokens") or 0)
                + (cur.get("cache_read_input_tokens") or 0)
            )
    size = cw.get("context_window_size") or 0
    if used is None:
        return None
    pct = cw.get("used_percentage")
    if pct is None:
        if size <= 0:
            return None
        pct = 100.0 * used / size
    return used, float(pct)


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

    resolved = native_usage(session)
    if resolved is None:
        # Fallback for older Claude Code without the context_window block.
        used = last_assistant_tokens(session.get("transcript_path"))
        if used is None:
            return
        max_tokens = model_max_tokens((session.get("model") or {}).get("id", ""))
        if max_tokens <= 0:
            return
        resolved = (used, 100.0 * used / max_tokens)

    used, fill_pct = resolved
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
