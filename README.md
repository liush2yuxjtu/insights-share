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

## Architecture (current scope)

- **Client**: this plugin. Speaks HTTP to an insights server. Caches results locally at `~/.claude/insights/cache.json`.
- **Server**: contract documented in [`references/server-protocol.md`](references/server-protocol.md). Self-host stub script provided in [`examples/server-stub.py`](examples/server-stub.py). Production server implementation **deferred** per project decision.

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

```bash
/plugin install insights-share@<your-marketplace>
```

After install, hooks register automatically. The first session in any project triggers the `CLAUDE.md` append.

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
├── .claude-plugin/plugin.json
├── hooks/hooks.json
├── skills/{insight-add,insight-search,insight-install,insight-server}/SKILL.md
├── scripts/{statusline.sh,fetch-insights.sh,append-claude-md.sh,insights-client.sh}
├── references/{server-protocol.md,self-host.md}
└── examples/{insight.example.json,server-stub.py}
```

## Roadmap

- v0.1 (this release): client + hooks + statusline + server contract + self-host stub.
- v0.2: real server reference implementation (Postgres + REST).
- v0.3: nightly automation, tag-based filtering, conflict resolution.

## License

MIT.
