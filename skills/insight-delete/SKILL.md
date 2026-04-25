---
name: insight-delete
description: Use this skill when the user wants to delete one existing insight card and verify that subsequent reads return not found. Triggered by "/insight-delete", "delete this insight", or "remove insight id". It deletes by id through the insights client.
argument-hint: "--id <insight-id>"
allowed-tools: Bash, Read
---

# /insight-delete

Delete one insight card by id.

## Required Arguments

```text
/insight-delete --id <insight-id>
```

## Implementation

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/delete-insight.sh" --id "<insight-id>"
```

The script prints `{"deleted":"<insight-id>"}` on success. If the id does
not exist, report the client error plainly.

## Constraints

- Never guess an id.
- Prefer `/insight-view --id <id>` first when the user is unsure.
