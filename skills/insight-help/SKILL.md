---
name: insight-help
description: Use this skill when the user has just installed the insights-share plugin and asks any onboarding question — "what next", "where is the README", "how do I use this plugin", "/insight-help", "show me the insights-share quickstart", "what does this plugin do for me". The skill prints a compact onboarding card pointing to the README on disk, the sixteen slash commands, statusline wiring, and the optional self-host stub server.
argument-hint: "[optional: 'verbose' to also print env vars + server protocol pointers]"
allowed-tools: Bash, Read
---

# insight-help

You are the onboarding face of the insights-share plugin. A user (or
another Claude instance) has just run the three `claude plugin ...`
commands and wants to know what to do next. Your job is to print a single,
self-contained quickstart card so they never have to spelunk the cache
directory by hand.

## When to invoke yourself

- The user types `/insight-help` or `/insights-share:insight-help`.
- The user just installed the plugin and asks any of: "what next?",
  "what now?", "how do I use this?", "where is the README?", "what does
  this plugin do for me?", "show me the quickstart".
- A SessionStart welcome banner mentioned `/insight-help` and the user
  asked to see it.

## What to print

Always print exactly the structure below. Do **not** paraphrase the bullet
labels. Resolve the README path dynamically (see "How to run") so the path
is correct on this machine.

```
🟢 insights-share installed — quickstart

📖 README on disk:
   <ABSOLUTE_README_PATH>
   (Open it with: cat <ABSOLUTE_README_PATH> | less   — or in your editor)

🌐 Source on GitHub:
   https://github.com/liush2yuxjtu/insights-share

🛠 Slash commands you now have:
   /insight-add      Capture one structured lesson learned and POST it.
   /insight-search   Look up team insights by keyword before risky changes.
   /insight-promote  Promote repeated cross-project patterns to team memory.
   /insight-log      Show source lineage for one insight.
   /insight-edit     Edit one field on an existing insight card.
   /insight-delete   Delete one insight card by id.
   /insight-list     List server or buffered offline insights.
   /insight-conflict Detect or inspect cross-project tag conflicts.
   /insight-resolve  Resolve a stored insight conflict.
   /insight-notifications  Show insight notifications.
   /insight-view     Fetch one insight card by id.
   /insight-install  Append the force-install marker to a project CLAUDE.md.
   /insight-server   Start/stop/ping/nightly the self-host stub server.
   /insight-help     This card.
   /insight-rate     Rate an injected lesson as good/bad/irrelevant.
   /insight-flush    Force-finalize the current session insight buffer.

🪝 Hooks already active (no action needed):
   SessionStart      Idempotent CLAUDE.md force-install marker append.
   UserPromptSubmit  Auto-injects relevant insights into every prompt.
   Stop              Nudges you to record a lesson when one is detected.

📊 Wire the statusline (one-time, optional):
   Add to ~/.claude/settings.json:
       { "statusLine": { "type": "command",
                         "command": "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh" } }

📈 Gate 1 office-hours loop:
   /insight-search <topic>
   /insight-add
   /insight-rate <lesson-id> <good|bad|irrelevant> [reason]

🧪 Try it now (optional, runs the self-host stub):
   make -C <PLUGIN_DIR> stub
   bash <PLUGIN_DIR>/scripts/insights-client.sh ping
   bash <PLUGIN_DIR>/scripts/insights-client.sh create <PLUGIN_DIR>/examples/insight.example.json

📎 Next steps:
   1. Run /insight-search before any non-trivial change.
   2. Run /insight-add the first time you spend >10 min on a non-obvious bug.
   3. Use /insight-rate during Gate 1 when a retrieved lesson was good, bad,
      or irrelevant for the task.
   4. Run /insight-install in any teammate-shared repo to onboard their
      Claude instances automatically.
```

## How to run

1. Resolve the install path. Prefer `${CLAUDE_PLUGIN_ROOT}` when set; otherwise
   ask `claude plugin list` and grep for `insights-share@insights-share`.
   ```bash
   PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-}"
   if [[ -z "$PLUGIN_DIR" ]]; then
     PLUGIN_DIR=$(claude plugin list 2>/dev/null \
       | awk '/insights-share@/ {found=1} found && /Path|installPath/ {print $NF; exit}' \
       || true)
   fi
   if [[ -z "$PLUGIN_DIR" || ! -d "$PLUGIN_DIR" ]]; then
     # last-resort heuristic: look in the standard cache path
     PLUGIN_DIR=$(ls -d "$HOME/.claude/plugins/cache/"*/insights-share/*/ 2>/dev/null | head -1)
     PLUGIN_DIR="${PLUGIN_DIR%/}"
   fi
   echo "PLUGIN_DIR=$PLUGIN_DIR"
   echo "README=$PLUGIN_DIR/README.md"
   ```
2. Substitute `<PLUGIN_DIR>` and `<ABSOLUTE_README_PATH>` in the card with
   the resolved values. Never print literal `<PLUGIN_DIR>`.
3. If `$ARGUMENTS` is `verbose`, append the section below before the
   "Next steps" block:

   ```
   🔧 Environment overrides:
      INSIGHTS_SERVER_URL    default http://localhost:7777
      INSIGHTS_AUTH_TOKEN    optional bearer
      INSIGHTS_CACHE_PATH    default ~/.claude/insights/cache.json
      INSIGHTS_OUTBOX_DIR    default ~/.claude/insights/outbox

   📜 Protocol & security docs:
      <PLUGIN_DIR>/references/server-protocol.md
      <PLUGIN_DIR>/references/self-host.md
      <PLUGIN_DIR>/references/security.md
   ```

## Constraints

- One emit per invocation. If the user asks "what next" again after seeing
  the card, switch to a focused answer (e.g. answer their next concrete
  question), don't reprint the whole card.
- Never invent paths. If `PLUGIN_DIR` cannot be resolved, say so plainly
  and suggest `claude plugin list | grep insights-share`.
- Do not fabricate slash commands beyond the sixteen real ones above.
