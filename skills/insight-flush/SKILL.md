---
name: insight-flush
description: Use this skill when the user wants to force-finalize the in-flight session buffer immediately, instead of waiting for the 30-min idle threshold. Triggered by "/insight-flush", "flush insights", "push my insight buffer now", "publish lessons now", "force-sync the mirror". Reads the local buffer, runs the two-layer PII filter, and pushes any surviving lessons to the mirror repo.
argument-hint: "(no arguments)"
allowed-tools: Bash, Read
---

# /insight-flush

Force a manual session-boundary flush of the insights buffer.

By default the plugin waits for one of:

- `claude --resume` boundary (next session start)
- 30-minute idle on the buffer file
- this `/insight-flush` skill

…before running the filter pipeline + mirror push.

When you want the lesson available to your teammates immediately, run this
skill. It is also useful right before tearing down a sandbox or shutting
down a long-running session.

## What it does

1. Resolves the canonical repo slug via `canonical-remote.sh`.
2. Iterates each `*.jsonl` file in the per-repo `.buffer/` directory.
3. For each session, runs `finalize-buffer.sh` synchronously with
   `idle_threshold=0` so the filter pipeline executes immediately.
4. Reports how many sessions were finalized and how many were dropped by
   Layer 1 / Layer 2 filters.

## Implementation

Backing script: `scripts/flush-buffer.sh`.

## Examples

```text
User: /insight-flush
> finalized 1 session(s), dropped 0
> mirror push queued in background
```
