# Multi-bot reference artifacts (NOT yet installed by bootstrap.sh)

Working files lifted verbatim off a real box on 2026-08-05, where two
always-on Claude+Telegram sessions (two separate bots) ran side by side and
were verified end to end.

These are the **starting point for productizing N bots per box** (Pro plan:
"several apps at once"). They are deliberately NOT wired into `bootstrap.sh`
yet — a provisioned box still gets exactly one bot.

| File | What it is |
|---|---|
| `claude-telegram-appN-run.sh.example` | Runner for an extra bot. Own `TELEGRAM_STATE_DIR` (own token + pairing), own boot dir, supervises its tmux session. Paths are hardcoded to `app2` — parameterize by instance name when templating. |
| `claude-telegram-appN.service.example` | systemd unit for that runner. Mirrors `claude-telegram.service`. Convert to a template unit (`claude-telegram@.service`, `%i` = `appN`) for the product. |

Read `docs/MULTI_BOT.md` in the KAppMaker-AI repo first — it documents the
five non-obvious findings (channel-server-per-cwd singleton, the silent
`mcp-needs-auth-cache.json` trap, bun on PATH, the tmux env gotcha,
`TELEGRAM_STATE_DIR`) that these files encode.
