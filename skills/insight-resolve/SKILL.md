---
name: insight-resolve
description: Use this skill when the user asks to resolve an insight conflict by choosing a source or merge decision. Triggered by "/insight-resolve", "resolve conflict", or "pick Alice's insight".
argument-hint: "--conflict-id <id> --pick <source>"
allowed-tools: Bash, Read
---

# /insight-resolve

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-conflict.sh" $ARGUMENTS
```

The script marks the conflict resolved, appends a notification, and records
the event in the local audit log.
