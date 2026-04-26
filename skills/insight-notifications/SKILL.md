---
name: insight-notifications
description: Use this skill when the user asks for insight notifications, especially conflict resolution notifications. Triggered by "/insight-notifications" or "show insight notifications".
argument-hint: "(no arguments)"
allowed-tools: Bash, Read
---

# /insight-notifications

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/notifications.sh"
```

This is read-only and returns a JSON array.
