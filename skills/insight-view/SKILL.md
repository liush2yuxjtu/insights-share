---
name: insight-view
description: Use this skill when the user wants to view one insight by id, including an insight from another project. Triggered by "/insight-view" or "view insight id".
argument-hint: "--id <insight-id>"
allowed-tools: Bash, Read
---

# /insight-view

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/view-insight.sh" $ARGUMENTS
```

This is read-only and returns the card JSON.
