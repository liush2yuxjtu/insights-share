---
name: insight-conflict
description: Use this skill when the user asks to detect or inspect conflicts among insights with the same tag across projects. Triggered by "/insight-conflict", "show conflicts", or "detect tag conflict".
argument-hint: "--tag <tag> | --id <conflict-id>"
allowed-tools: Bash, Read
---

# /insight-conflict

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/conflict-insights.sh" $ARGUMENTS
```

`--tag <tag>` detects cross-project conflicts and stores a conflict record.
`--id <conflict-id>` prints the stored conflict detail.
