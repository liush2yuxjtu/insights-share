# insights-share — self-host guide (v0.1)

This plugin's **client** is fully implemented. The **server** is intentionally deferred. To run end-to-end smoke tests today, use the stub at `examples/server-stub.py`.

## Quickstart

```bash
# 1. start the stub (binds 127.0.0.1:7777)
python3 ${CLAUDE_PLUGIN_ROOT}/examples/server-stub.py &

# 2. point the client at it (already the default)
export INSIGHTS_SERVER_URL=http://localhost:7777

# 3. smoke test
bash ${CLAUDE_PLUGIN_ROOT}/scripts/insights-client.sh ping     # -> exit 0
bash ${CLAUDE_PLUGIN_ROOT}/scripts/insights-client.sh stats    # -> JSON
bash ${CLAUDE_PLUGIN_ROOT}/scripts/insights-client.sh list     # -> []
```

The plugin's `/insight-server` skill wraps these steps.

## Storage

The stub keeps cards in `~/.claude/insights/server-stub.json`. Delete that file to reset.

## Production server (out of scope, v0.2)

A production-grade server should:

- persist to Postgres or similar (cards are small but write-heavy when teams grow),
- authenticate via per-user bearer tokens,
- expose a tiny admin UI for moderating duplicates,
- support a nightly job that:
  - dedups near-identical cards by cosine similarity over the `trap+fix` text,
  - tags stale cards (no hits in 60 days) for review,
  - re-emits a per-team digest.

None of this is shipped in v0.1. The protocol in [`server-protocol.md`](server-protocol.md) is stable enough that the client + hooks + statusline can ship now and be retargeted at the production server later without a client release.
