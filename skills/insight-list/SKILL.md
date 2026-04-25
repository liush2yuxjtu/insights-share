---
name: insight-list
description: Use this skill when the user asks to list insights by status or tag, especially buffered offline insights. Triggered by "/insight-list", "show buffered insights", or "list insights by tag".
argument-hint: "[--status buffered] [--tag <tag>]"
allowed-tools: Bash, Read
---

# /insight-list

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/list-insights.sh" $ARGUMENTS
```

Use `--status buffered` to show offline outbox cards with
`pending_sync=true`.
