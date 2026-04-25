---
name: insight-search
description: Use this skill when a Claude instance wants to manually look up team insights before acting on a non-trivial task — e.g. before changing build configuration, touching auth, writing a migration, or wiring a hook. Trigger phrases include "search insights", "any team lesson on X", "/insight-search", "have we hit this before". The skill performs a keyword search against the team insights server and renders the top hits as a compact briefing.
argument-hint: "<query keywords>"
allowed-tools: Bash, Read
---

# insight-search

You are the reader side of the team insights system. The forced `UserPromptSubmit` hook already injects relevant insights automatically; this skill exists for the cases where Claude needs to **explicitly** pull more context (e.g. while planning, code-reviewing, or debugging).

## When to invoke yourself

- The user says "search insights" / "what do we know about X" / `/insight-search ...`.
- You are about to make a change in an area you have not seen yet (build config, auth, deploy, schema migration) and want to check for prior traps before touching it.
- The auto-injected insight block was empty but the task feels suspiciously like one a teammate would have hit before.

## How to run

1. Read `$ARGUMENTS` as the query string. If empty, ask the user for one short query.
2. Call:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/insights-client.sh" search "<query>"
   ```
3. Parse the JSON response. If empty, say so plainly and suggest the user write one with `/insight-add`.
4. If non-empty, render up to 5 cards in this format:
   ```
   [N] <title>          —  by <author>  [<tags>]
       trap: <one-liner>
       fix:  <one-liner>
       evidence: <pointer>
   ```
5. Close with one synthesis sentence: how the top hits change what the user is about to do.

## Constraints

- Never paraphrase the cards' `trap` or `fix` — quote them verbatim. They were authored deliberately.
- If the server is offline (the client falls back to local cache), prefix the output with `(offline cache, last sync: <timestamp>)`.
- Do not auto-apply any insight. This skill is read-only.

## Anti-patterns

- **Never fabricate a card.** If the search returns `[]`, say so and recommend `/insight-add` to the user. Do not invent a `trap`/`fix` to fill the silence — the whole value of this system depends on cards being authored evidence, not LLM speculation.
- Do not silently widen the query (e.g. dropping it to a vague stem) just to produce hits. If the original query has no results, that is the answer.
- Do not summarize across cards into a single "team consensus" sentence — render each card individually so the user can audit which one applies.
