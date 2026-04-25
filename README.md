# insights-share

Team insight sharing plugin for Claude Code **instances** (not the human users). New Claude collaborators automatically inherit the team's accumulated lessons and stop re-discovering known traps.

> Audience: this plugin is written **for Claude**, not for the developer behind it. Skill bodies are imperative instructions Claude follows on the team's behalf.

## What it does

| Surface | Effect |
|---------|--------|
| **Statusline** | Shows total insight count, count relevant to the current session, NEW badge, and server health. A glanceable "team knowledge presence" indicator. |
| **`UserPromptSubmit` hook** | Forces every prompt to first query the insights server for relevant cards and inject them as system context. New Claude instances cannot miss a relevant prior lesson. |
| **`SessionStart` hook** | Idempotently appends an install marker block to the project `CLAUDE.md` so any future collaborator's Claude instance is forced to install this plugin. Append-only — never rewrites. |
| **Skills** | `/insight-add` (manual write), `/insight-search` (manual query), `/insight-install` (manually trigger CLAUDE.md append), `/insight-server` (manage self-host server stub). |

## Architecture

`v0.1` is built to **Approach B** of the canonical design — a repo-scoped
precedent router that captures Claude Code session lessons silently,
filters PII through a two-layer pipeline, and shares them via a per-repo
GitHub mirror (`<owner>/<repo>-insights`).

- **Hot path** = local-cache retrieval, ≤500ms p95, NO git fetch
  (`scripts/inject-insights.sh` → `_inject_hot_path.py`).
- **Capture path** = Stop-hook silent buffer + 30-min idle async finalize
  (`scripts/capture-async.sh` → `finalize-buffer.sh`).
- **Privacy** = Layer 1 regex (`_filter_pii.py`, 15 pattern families) +
  Layer 2 haiku (`filter-haiku.sh`, 2s timeout, drop on conf<0.8).
- **Storage** = GitHub mirror repo, plain JSONL, per-repo PAT
  (`sync-mirror.sh`, `pat-auth.sh`).
- **Legacy HTTP server stub** still ships for regression tests
  (`examples/server-stub.py`).

Full B-feature ↔ file map: see [`docs/B-scope-impl.md`](docs/B-scope-impl.md).

Gate-0 PII benchmark: `bash tests/gate0/run-gate0.sh --strict`
(currently 654 turns / 4 buckets / 54 adversarial / 0 leaks / 0% FP).

## Configuration

Create `.claude/insights-share.local.md` (gitignored) in your project root:

```yaml
---
server_url: http://localhost:7777
auth_token: <optional>
statusline_mode: full     # or: lite | ultra
nightly_sync: false       # server-side cron, manual on client by default
---
```

Environment variable overrides:

- `INSIGHTS_SERVER_URL`
- `INSIGHTS_AUTH_TOKEN`
- `INSIGHTS_CACHE_PATH` (default `~/.claude/insights/cache.json`)

## Installation

Install commands always start with `claude plugin ...`. The repo is a
single-plugin self-marketplace, so adding the marketplace = adding the
plugin source in one step.

```bash
# 1. register this repo as a marketplace (one-time)
claude plugin marketplace add liush2yuxjtu/insights-share

# 2. install + enable
claude plugin install insights-share@insights-share
claude plugin enable  insights-share@insights-share

# 3. verify
claude plugin list | grep insights-share         # status: ✔ enabled
claudefast -p 'list slash commands containing insight'
# → /insight-add /insight-search /insight-install /insight-server
```

After install, hooks register automatically.

### After install — what next?

1. **Open any new Claude Code session.** The `SessionStart` hook prints a
   one-time welcome banner that includes:
   - the absolute path to **this very README** on disk,
   - the five slash commands you now have,
   - the three hooks already wired,
   - a 3-step quickstart.

   The banner only fires on the first session post-install (gated by
   `~/.claude/insights/.welcomed`). Delete that file to see it again.

2. **Run `/insight-help`** at any time to reprint the onboarding card.

3. **Read the README on disk.** The plugin cache copy lives at:

   ```
   ~/.claude/plugins/cache/insights-share/insights-share/<version>/README.md
   ```

   Or use:

   ```bash
   PLUGIN_DIR=$(claude plugin list \
     | awk '/insights-share@insights-share/{found=1} found && /Path/{print $NF; exit}')
   cat "$PLUGIN_DIR/README.md" | less
   ```

4. **Verify install** (everything below should be true):

   ```bash
   claude plugin list | grep insights-share         # status: ✔ enabled
   claudefast -p 'list slash commands containing insight'
   # → /insight-add /insight-search /insight-install /insight-server /insight-help
   ```

5. **First real use:**
   - Run `/insight-search <keyword>` before any non-trivial change.
   - Run `/insight-add` the first time you spend >10 min on a non-obvious bug.
   - Run `/insight-install` in any teammate-shared repo so their Claude
     instances inherit the same insights.

The first session inside any project that already has a `CLAUDE.md`
triggers the append-only force-install marker block.

### Update (instead of reinstall)

```bash
# 1. pull latest commits + bump installed version
claude plugin update insights-share@insights-share

# 2. RESTART Claude Code (or open a fresh session) — running CC processes
#    cache the plugin's system prompt and won't see new skills/hooks until
#    they're re-launched. `claude plugin update --help` already warns about this.
```

If the marketplace schema itself changed (rare):

```bash
claude plugin marketplace update insights-share   # re-fetch marketplace.json
claude plugin update              insights-share@insights-share
```

To check if an update is available before pulling:

```bash
claude plugin list | grep -A2 insights-share                          # local version
gh api repos/liush2yuxjtu/insights-share/commits/main --jq '.sha[:12]' # remote HEAD
```

Hard reinstall (last resort — when `update` won't budge):

```bash
claude plugin uninstall          insights-share@insights-share
claude plugin marketplace remove insights-share
claude plugin marketplace add    liush2yuxjtu/insights-share
claude plugin install            insights-share@insights-share
claude plugin enable             insights-share@insights-share
```

### Uninstall

```bash
claude plugin uninstall insights-share@insights-share
claude plugin marketplace remove insights-share
```

## Statusline integration

Add to your user `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh"
  }
}
```

Or rely on the per-project setting auto-suggested by `/insight-install`.

## File layout

```
insights-share/
├── .claude-plugin/{plugin.json,marketplace.json}
├── hooks/hooks.json                  # SessionStart + UserPromptSubmit + Stop
├── skills/                           # 7 SKILL.md (add/search/install/server/help/rate/flush)
├── scripts/
│   ├── inject-insights.sh            # UserPromptSubmit hot path (B-arch)
│   ├── _inject_hot_path.py           # single-process retrieval body
│   ├── capture-async.sh              # Stop hook silent buffer
│   ├── finalize-buffer.sh            # async filter + upload
│   ├── filter-pii.sh + _filter_pii.py# Layer 1 regex
│   ├── filter-haiku.sh               # Layer 2 haiku redact + topic
│   ├── sync-mirror.sh                # GitHub mirror push/pull
│   ├── pat-auth.sh                   # per-repo PAT lifecycle (chmod 600)
│   ├── canonical-remote.sh           # HTTPS↔SSH normalisation
│   ├── cold-start.sh                 # lazy mirror discovery + 30min bg-sync
│   ├── retrieve-local.sh             # legacy retrieval entry (used by tests)
│   ├── embed-fallback.py             # sentence-transformers + TF-IDF fallback
│   ├── rate-lesson.sh                # /insight-rate backing
│   ├── flush-buffer.sh               # /insight-flush backing
│   ├── buffer-recover.sh             # crash recovery
│   ├── append-claude-md.sh           # SessionStart marker + bg kickoff
│   ├── statusline.sh                 # team knowledge presence
│   └── insights-client.sh            # legacy HTTP client (kept for tests)
├── tests/
│   ├── run.sh                        # 92 assertions (71 legacy + 21 B-pipeline)
│   └── gate0/{run-gate0.sh,seed-corpus.py,corpus/}
├── docs/B-scope-impl.md              # design ↔ impl trace
├── references/{server-protocol.md,self-host.md}
└── examples/{insight.example.json,server-stub.py}
```

## Roadmap

- v0.1 (this release): client + hooks + statusline + server contract + self-host stub.
- v0.2: real server reference implementation (Postgres + REST).
- v0.3: nightly automation, tag-based filtering, conflict resolution.

## License

MIT.
