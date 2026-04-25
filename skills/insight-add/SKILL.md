---
name: insight-add
description: Use this skill when a Claude instance has just hit, fixed, or learned about a non-obvious trap that another teammate (or another Claude instance) would benefit from knowing. Trigger phrases include "save this as a team insight", "add insight", "log a lesson", "/insight-add", "we should record this so others don't repeat it". The skill captures one structured insight card and POSTs it to the team insights server.
argument-hint: "[optional one-line title]"
allowed-tools: Bash, Read, Write
---

# insight-add

You are the writer side of the team insights system. Your job is to capture **one** sharp, reusable lesson that another Claude instance on this team should not have to re-learn.

## When to invoke yourself

Run this skill when ANY of the following just happened in the conversation:

- The user said "save this as an insight" / "add insight" / "log a lesson" / `/insight-add`.
- You (or a teammate) hit a non-obvious trap, debugged it, and now know the fix.
- A code reviewer or test caught something that contradicts an assumption a future Claude would make.
- A workflow tool (build, deploy, migration) silently misbehaves in a way that is hard to discover.

Do **not** invoke for trivia, taste preferences, or anything already obvious from reading the code.

## What you must produce

Exactly one JSON card matching this shape:

```json
{
  "title": "short imperative summary (≤ 80 chars)",
  "trap": "what surface looks correct but is actually wrong",
  "fix":  "what to do instead, concretely",
  "evidence": "file:line, error text, or PR link that proves this",
  "tags": ["build", "auth", "migration", ...],
  "scope": "project | global",
  "author": "claude-instance@<project-name>"
}
```

Constraints:

- `trap` and `fix` together must be readable in under 15 seconds.
- `evidence` is required — no anecdotes without a pointer.
- `tags` should include both a domain tag (e.g. `auth`) and a surface tag (e.g. `hook`, `migration`, `cli`).
- `scope`: use `project` unless the lesson is genuinely cross-repo.

## How to run

1. If `$ARGUMENTS` is set, treat it as the proposed title; otherwise infer one from recent context.
2. Draft the card. Show it to the user in a fenced JSON block.
3. Ask the user to confirm or edit. **Do not skip this step**, even if you are highly confident — the human knows the team taxonomy.
4. On confirmation, write the card to a temp file then call the add script.
   It applies Layer-1 PII redaction and the 10/minute local rate limit before
   POSTing. Substitute the literal confirmed JSON in place of the `{...}`
   placeholder below — do not emit the placeholder verbatim:
   ```bash
   tmp=$(mktemp)
   cat > "$tmp" <<'JSON'
   {"title":"...","trap":"...","fix":"...","evidence":"...","tags":[...],"scope":"project","author":"..."}
   JSON
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/add-insight.sh" "$tmp"
   ```
5. Report the server response (id, url) back to the user. If the server is
   offline, the script saves the card to `~/.claude/insights/outbox/`. If the
   script returns `rate_limited:true`, tell the user to retry after the window.

## Anti-patterns

- Writing multiple insights in one card. Split them.
- Writing an insight whose `fix` is "be careful". That is not a fix.
- Writing an insight that duplicates one already returned by `/insight-search` — instead, propose an edit to the existing card and tell the user.
