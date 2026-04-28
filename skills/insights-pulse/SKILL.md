---
name: insights-pulse
description: |
  Inspect or control the insights-share three-segment statusline badge.
  Trigger on ANY of these phrasings (English / 中文 / duck-style):
  - "show pulse", "insights status", "check pulse badge"
  - "/insights-pulse" with any arg (status / check / on / solo / off / reset / render)
  - "查看 pulse", "心得状态", "看徽章", "看一下徽章"
  - "装徽章" / "把徽章装上" / "open the badge" / "wire the badge" / "enable badge"
  - "关徽章" / "卸徽章" / "把徽章关掉" / "disable badge" / "remove badge"
  - "我在哪" / "我在沙盒还是生产" / "self check" / "鸭鸭自检" / "where am I"
  - "重置 flag" / "清掉 flag" / "reset pulse"
  - Any duck-style phrasing like "鸭鸭想…徽章" / "鸭鸭想知道我在哪"
  Map duck phrases to subcommands by intent: 装→on, 关→off, 看/render→render,
  自检/我在哪→check, 总览/状态→status, 重置→reset.
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
| `/insights-pulse status` (default) | 三段总览：横幅 + flag + 徽章 |
| `/insights-pulse check`            | 只打沙盒/生产横幅，不写任何文件（鸭鸭自检专用） |
| `/insights-pulse on`               | 安装徽章（postfix 模式，保留原 statusline） |
| `/insights-pulse solo`             | 安装徽章（独占模式，替换原 statusline） |
| `/insights-pulse off`              | 卸载徽章 |
| `/insights-pulse reset`            | 清掉三个 flag 文件，下次 hook 触发重建 |
| `/insights-pulse render`           | 只渲染一次徽章 |

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

1. **Detect the intent** from the user's phrasing (use the trigger map in
   `description` above). If the user typed a slash command directly, use its arg.
2. **Always invoke the slash command** `/insights-pulse <subcommand>`; do NOT
   call the underlying scripts yourself — the slash command already prints
   sandbox/production banners, friendly chinese explanations, and the badge.
3. **For ambiguous phrases** (e.g. "鸭鸭想看一下"), default to `status` —
   it's the safest read-only summary.
4. **For destructive intents** (`on`, `solo`, `off`, `reset`), the underlying
   scripts will refuse production unless the duck explicitly says
   "我知道在生产" / "force production" / "--allow-production". Only then pass
   `--allow-production` along.
5. **After running**, restate the result in plain Chinese so the duck
   understands what happened and what to do next.
