---
name: insight-promote
description: Use this skill when the user wants to promote repeated cross-project insights into a team-scoped memory. Triggered by "/insight-promote", "promote these insights", "make this a team memory", or "cross-project hotspot". It requires at least two matching insights from at least two projects, then creates a promoted team card with source lineage.
argument-hint: "--tags tag1,tag2 [--scope team]"
allowed-tools: Bash, Read
---

# /insight-promote

Promote a repeated cross-project pattern into a team-scoped memory.

## Required Arguments

```text
/insight-promote --tags architecture,rsc --scope team
```

The backing script only promotes when both thresholds are met:

- at least two existing insight cards match all requested tags,
- those cards come from at least two distinct project sources.

Project source is read from `project_slug`, `repo_slug`, `project`, `cwd`,
or `source_project`.

## Implementation

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/promote-insights.sh" --tags "<tags>" --scope team
```

On success, report the created card id, `source_projects`, `promoted_from`,
and `priority`. On threshold failure, report the JSON reason without
inventing a team memory.

## Constraints

- Do not promote a single-project pattern.
- Do not remove or mutate the original insights.
- Keep `scope` as `team` unless the user explicitly asks for another scope.
