---
name: insight-install
description: Use this skill when a Claude instance is bootstrapping a new repository or onboarding a project that is not yet wired into the team insights system. Trigger phrases include "install insights into this repo", "wire insights-share here", "/insight-install", "wire this repo so teammates inherit insights". The skill idempotently appends a force-install block to the project CLAUDE.md (append-only) and verifies hook registration so any future Claude instance entering this repo is guided to install the plugin.
argument-hint: "[optional path to project root, defaults to cwd]"
allowed-tools: Bash, Read
---

# insight-install

You are the onboarding side of the team insights system. Your job is to make a fresh repo enforce that every future Claude collaborator picks up this plugin.

## When to invoke yourself

- The user says "install insights here" / "wire this repo so teammates inherit insights" / `/insight-install`.
- You enter a repo whose `CLAUDE.md` does **not** contain the marker `<!-- insights-share@v0.1 -->`.
- A teammate asks you to standardize a new project for the team's knowledge flow.

## What you must do

1. Resolve target root: `$ARGUMENTS` if set, else current working directory.
2. Verify a `CLAUDE.md` already exists at that root. **Do not create one** — that is the team's decision, not yours. If missing, tell the user and stop.
3. Run the append script directly (same code the SessionStart hook uses):
   ```bash
   echo "{\"cwd\":\"<absolute-project-root>\"}" \
     | bash "${CLAUDE_PLUGIN_ROOT}/scripts/append-claude-md.sh"
   ```
4. Re-read `CLAUDE.md` and confirm the marker line `<!-- insights-share@v0.1 -->` is present exactly once.
5. Report:
   - what was appended (in a fenced block),
   - the marker line number,
   - that future Claude instances entering this repo will now see the install hint on their `SessionStart`.

## Guarantees

- **Append-only.** Never delete, rewrite, or reorder existing content in `CLAUDE.md`.
- **Idempotent.** If the marker is already present, do nothing and say so.
- **No silent surprise.** Always show the user the diff before saying "done".
