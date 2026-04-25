---
name: insight-edit
description: Use this skill when the user wants to edit one field on an existing insight card, especially to reproduce concurrent edits to the same insight. Triggered by "/insight-edit", "edit this insight", "set status", or "update tags". It sends a partial PATCH so different-field concurrent edits can merge instead of overwriting the whole card.
argument-hint: "--id <insight-id> --field <field> --value <value>"
allowed-tools: Bash, Read
---

# /insight-edit

Edit one field on an existing insight card.

## Required Arguments

```text
/insight-edit --id <insight-id> --field status --value archived
```

For JSON-valued fields, quote the JSON:

```text
/insight-edit --id <insight-id> --field tags --value '["archived","kernel-fix"]'
```

## Implementation

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/edit-insight.sh" --id "<insight-id>" --field "<field>" --value "<value>"
```

The script sends a partial PATCH through `insights-client.sh update` and
prints the updated card JSON.

## Constraints

- Do not edit `id` or `created_at`.
- Prefer one field per invocation so concurrent different-field edits can
  merge naturally on the server.
- Report any 404 or client error plainly.
