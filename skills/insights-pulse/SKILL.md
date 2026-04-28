---
name: insights-pulse
description: Inspect or control the insights-share statusline badge. Trigger when user says "show pulse", "insights status", "check pulse badge", "查看 pulse", "心得状态", "/insights-pulse status", or wants to enable/disable/reset the badge.
---

# Insights Pulse

Three-segment ANSI statusline badge that surfaces `insights-share` health in real time:

```
[is HIT │ VAULT │ PIPE]
   │       │       └── ingest pipeline (uncategorized %, staging backlog)
   │       └────────── LAN sync state (total / peers / since)
   └────────────────── this turn's hit count (recommendations injected)
```

## Subcommands

| Command | Action |
|---|---|
| `/insights-pulse status` (default) | Print current flag contents and rendered badge |
| `/insights-pulse on`               | Run `scripts/install-statusline.sh` (postfix mode) |
| `/insights-pulse solo`             | Run `scripts/install-statusline.sh --solo` (replace existing statusline) |
| `/insights-pulse off`              | Run `scripts/uninstall-statusline.sh` |
| `/insights-pulse reset`            | Delete the three flag files (next hook run rebuilds them) |
| `/insights-pulse render`           | Just invoke `scripts/statusline-pulse.sh` once and dump output |

## Color rules

| Segment | Green | Yellow | Red |
|---|---|---|---|
| HIT     | 0 hits | 1–4 hits ⚠ | ≥5 hits ☠ |
| VAULT   | OK & since<10m & peers≥3 | since 10m–1h or peers<3 or PART | FAIL or since>1h |
| PIPE    | uncat<30% & staging<5    | 30–60% or staging 5–20         | >60% or staging>20 |

The whole badge frame inherits the highest severity color of the three.

## Flag file locations

| File | Written by | Format |
|---|---|---|
| `~/.claude-team/.pulse-hit`  | `query-insights.sh` (UserPromptSubmit) | single integer 0–999 |
| `~/.claude-team/.pulse-sync` | `rsync-pull.sh` (SessionStart)         | `STATE\|TOTAL\|PEERS\|TS` |
| `~/.claude-team/.pulse-pipe` | `rsync-pull.sh`, `generate-index.sh`   | `UNCAT_PCT\|STAGING\|TS` |

All flag reads in `statusline-pulse.sh` enforce: refuse symlinks, 64-byte cap,
whitelist regex. Any anomaly → empty stdout (no terminal-injection vector).

## Process

1. Parse the user's argument (or default to `status`).
2. Pick the matching script under `${CLAUDE_PLUGIN_ROOT}/scripts/`.
3. Run it via Bash and report its output, plus a final-rendered badge for confirmation.
4. For `status`, also pretty-print the parsed flag values so the user can
   eyeball what each segment will show.
