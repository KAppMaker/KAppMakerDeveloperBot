#!/usr/bin/env python3
"""Save the recent conversation so a restarted Claude can recover context.

Registered as a Claude Code **Stop** hook (see setup-vps.sh). After each turn it
reads the session transcript and rewrites ~/.claude/session-history.md with the
last N user/assistant messages (trimmed). Because it writes to disk every turn,
the file survives an OOM kill / reboot — so when systemd restarts the always-on
Telegram bot as a fresh process, the new Claude can read what it was working on.

It is intentionally WRITE-ONLY here: Claude reads the file *on demand*, and only
when it lacks context (see ~/projects/CLAUDE.md). Nothing is auto-injected.

Best-effort and silent: any error exits 0 so it can never block or break a turn.
"""
import json
import os
import sys

MAX_TURNS = 15      # how many recent messages to keep
MAX_CHARS = 600     # cap each message so the file stays small / mobile-friendly
HISTORY = os.path.expanduser("~/.claude/session-history.md")


def text_from(content):
    """Extract plain text from a message's content (string or block list)."""
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text" and block.get("text"):
                parts.append(block["text"])
        return "\n".join(parts).strip()
    return ""


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    tpath = payload.get("transcript_path")
    if not tpath or not os.path.exists(tpath):
        return 0

    turns = []
    try:
        with open(tpath, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                role = obj.get("type") or (obj.get("message") or {}).get("role")
                if role not in ("user", "assistant"):
                    continue
                text = text_from((obj.get("message") or {}).get("content"))
                if not text:
                    continue  # skip tool-result-only / tool-call-only turns
                if len(text) > MAX_CHARS:
                    text = text[:MAX_CHARS].rstrip() + " […]"
                turns.append((role, text))
    except Exception:
        return 0

    turns = turns[-MAX_TURNS:]
    if not turns:
        return 0

    out = [
        "# Recent conversation (auto-saved, newest last)",
        "",
        "<!-- Written by claude-history.py after each turn; survives restarts.",
        "     Read this ONLY if you lack context for something the user references. -->",
        "",
    ]
    for role, text in turns:
        out.append(f"**{'User' if role == 'user' else 'Claude'}:** {text}")
        out.append("")

    try:
        os.makedirs(os.path.dirname(HISTORY), exist_ok=True)
        with open(HISTORY, "w", encoding="utf-8") as f:
            f.write("\n".join(out).rstrip() + "\n")
    except Exception:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
