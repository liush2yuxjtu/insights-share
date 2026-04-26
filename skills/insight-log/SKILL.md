---
name: insight-log
description: Use this skill when the user wants lineage or audit details for an insight, especially a promoted team memory. Triggered by "/insight-log", "show the source projects", "where did this team memory come from", or "audit this insight id". It fetches one card and prints source_projects, promoted_from, authors, timestamps, scope, and status.
argument-hint: "--id <insight-id> [--json]"
allowed-tools: Bash, Read
---

# /insight-log

Show lineage and audit fields for one insight card.

## Required Arguments

```text
/insight-log --id <insight-id>
```

For machine-readable output:

```text
/insight-log --id <insight-id> --json
```

## Implementation

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/insight-log.sh" --id "<insight-id>"
```

The output must include:

- `scope`
- `status`
- `source_projects`
- `promoted_from`
- `source_authors`
- `created_at`
- `updated_at`

## Constraints

- This skill is read-only.
- If the card does not exist, report the client error plainly.
- Do not infer missing lineage. If `source_projects` is empty, say it is not
  recorded on that card.
