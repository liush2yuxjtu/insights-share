---
name: insight-rate
description: Use this skill when the user (or another Claude instance) wants to rate a previously injected insight as good / bad / irrelevant for the current task. Triggered by "/insight-rate", "rate this insight", "this lesson saved me time", "this lesson was wrong", "thumbs up the insight", or similar phrasings. Writes a single rating record to the per-repo ratings.jsonl. Used at Gate 1 to compute "≥1 cross-engineer relevant retrieval / week" and detect drift in topic-tag inference.
argument-hint: "<lesson-id> <good|bad|irrelevant> [reason]"
allowed-tools: Bash, Read
---

# /insight-rate

Tag an injected lesson as `good`, `bad`, or `irrelevant`.

The rating is the only Gate-1 metric that requires explicit user action — keep
it lightweight. The rating is appended to the local `ratings.jsonl` and
synced to the team mirror on the next push, so all collaborators see the
verdict.

## Required arguments

```
/insight-rate <lesson-id> <good|bad|irrelevant> [reason]
```

- `lesson-id`: the id printed in the `<insights-share>` injection block.
- verdict: one of `good` / `bad` / `irrelevant`.
- `reason` (optional): a short free-text note (saved verbatim, untouched by
  the Layer-2 PII filter — keep it generic).

## Implementation

The skill is implemented by `scripts/rate-lesson.sh`. The script:

1. Resolves the canonical repo slug via `canonical-remote.sh`.
2. Appends `{lesson_id, verdict, reason, rated_by, rated_at, repo_slug}` to
   `~/.gstack/insights/<repo-slug>/ratings.jsonl`.
3. Schedules a background `sync-mirror.sh push` so the rating reaches the
   mirror without blocking.

## Why we keep it manual

The design doc explicitly suppresses an inline thumb prompt in v1 — the
plugin must stay user-unaware during normal use. `/insight-rate` is invoked
only when the receiving engineer chooses to rate; routing logic does not
depend on it. (Gate 1 metrics depend on it.)

## Examples

```text
User: /insight-rate lesson-1714044020-abc12345 good
> wrote rating to ~/.gstack/insights/<slug>/ratings.jsonl

User: /insight-rate lesson-... bad — wrong stack
> wrote rating + reason
```
