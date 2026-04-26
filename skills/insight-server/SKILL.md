---
name: insight-server
description: Use this skill when a Claude instance needs to start, stop, ping, or run the nightly automation cycle of the self-host insights server. Trigger phrases include "start insights server", "ping the insights server", "run nightly insights sync", "/insight-server start|stop|ping|nightly", "is the team insights backend up". The skill is a thin operator over the self-host server stub documented in references/self-host.md; the production backend is intentionally deferred.
argument-hint: "start | stop | ping | nightly | status"
allowed-tools: Bash, Read
---

# insight-server

You are the operator side of the self-host insights server. The production backend is intentionally **out of scope** for this plugin version. What you manage today is a stub server (`examples/server-stub.py`) sufficient for end-to-end smoke testing of the client + hooks + statusline.

## When to invoke yourself

- The user says "start the insights server" / "ping insights" / `/insight-server <verb>`.
- The statusline shows `🛰 offline` or `○` and the user wants to bring the backend up.
- The user wants to manually run the nightly sync that a future production server will run automatically.

## Verbs

| Verb | Effect |
|------|--------|
| `start`   | Background-launch the stub server on `INSIGHTS_SERVER_URL` (default `http://localhost:7777`). Re-uses an existing PID if the health probe passes. |
| `stop`    | Send SIGTERM to the stub server PID file (`~/.claude/insights/server.pid`). |
| `ping`    | Hit `/healthz` via the client. Print "ok" + latency or non-zero exit. |
| `status`  | Show server URL, PID file, last sync, total card count from `/stats`. |
| `nightly` | Invoke the placeholder nightly job: rotates the server log, dedups cache, runs `/stats` and prints a one-line summary. Real automation lands in v0.4. |

## How to run

1. Parse `$ARGUMENTS` as the verb. Default to `status` if empty.
2. For `start`:
   ```bash
   nohup python3 "${CLAUDE_PLUGIN_ROOT}/examples/server-stub.py" \
       > ~/.claude/insights/server.log 2>&1 &
   echo $! > ~/.claude/insights/server.pid
   sleep 1
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/insights-client.sh" ping && echo "started"
   ```
3. For `stop`:
   ```bash
   pid=$(cat ~/.claude/insights/server.pid 2>/dev/null || true)
   [[ -n "$pid" ]] && kill "$pid" && rm -f ~/.claude/insights/server.pid
   ```
4. For `ping`:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/insights-client.sh" ping \
     && echo "ok" || echo "offline"
   ```
5. For `status`:
   ```bash
   echo "url=${INSIGHTS_SERVER_URL:-http://localhost:7777}"
   echo "pid_file=$HOME/.claude/insights/server.pid"
   [[ -f $HOME/.claude/insights/server.pid ]] \
       && echo "pid=$(cat $HOME/.claude/insights/server.pid)"
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/insights-client.sh" stats
   ```
6. For `nightly` (v0.1 stub — be honest about the no-op):
   ```bash
   logfile=$HOME/.claude/insights/server.log
   [[ -f $logfile ]] && mv "$logfile" "${logfile}.$(date +%Y%m%d)"
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/insights-client.sh" stats
   echo "(v0.1 stub: no real automation; rotation + stats only)"
   ```

## Constraints

- Never overwrite an existing production endpoint when `INSIGHTS_SERVER_URL` points to a non-localhost host. Print a warning and stop.
- Treat the stub as **insecure**: no TLS, no auth. Refuse to bind to anything but `127.0.0.1` unless the user passes `--allow-public` explicitly in `$ARGUMENTS`.
- The `nightly` verb in v0.1 is a no-op-ish stub. Be honest about that in the output.
