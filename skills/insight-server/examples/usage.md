# Example: /insight-server lifecycle

## Start

User: "start the insights server"

Claude:

```
$ nohup python3 $CLAUDE_PLUGIN_ROOT/examples/server-stub.py \
    > ~/.claude/insights/server.log 2>&1 &
$ echo $! > ~/.claude/insights/server.pid
$ sleep 1
$ bash $CLAUDE_PLUGIN_ROOT/scripts/insights-client.sh ping && echo started
started
```

Reports: started, PID=44321, listening on http://127.0.0.1:7777.

## Status

User: "is the team insights backend up"

```
$ bash $CLAUDE_PLUGIN_ROOT/scripts/insights-client.sh ping
$ echo "url=$INSIGHTS_SERVER_URL"
$ cat ~/.claude/insights/server.pid
$ bash $CLAUDE_PLUGIN_ROOT/scripts/insights-client.sh stats
{"total":12,"new":2,"session_relevant":1,"online":true,"last_sync_seconds_ago":4}
```

Reports concisely: `online · 12 cards · 2 new · 1 relevant to ./auth`.

## Nightly (v0.1 stub)

User: "run nightly insights sync"

Claude is honest about the stub:

```
$ logfile=~/.claude/insights/server.log
$ [[ -f $logfile ]] && mv "$logfile" "${logfile}.20260425"
$ bash $CLAUDE_PLUGIN_ROOT/scripts/insights-client.sh stats
$ echo "(v0.1 stub: no real automation; rotation + stats only)"
```

Reports:

> Rotated server.log → server.log.20260425. Real nightly automation
> (dedup, stale-card flagging, digest emission) lands in v0.4. No-op for
> now.
