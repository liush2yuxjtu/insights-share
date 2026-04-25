#!/usr/bin/env bash
# statusline.sh — beautiful insights statusline frontend.
#
# Reads JSON from Claude Code on stdin (model, cwd, etc.), emits one line.
# Falls back gracefully when server unreachable.
#
# Modes (env INSIGHTS_STATUSLINE_MODE): lite | full | ultra (default: full)
#
# Output examples:
#   lite : 💡12
#   full : 💡 12 ▸ 🎯 3 here ▸ ✨ 2 NEW ▸ ⏺ live
#   ultra: ╭ INSIGHTS ╮ 💡12 │ 🎯3 in ./hooks │ ✨2 NEW │ 🛰 srv ok │ ⏱ 12s ago

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CLIENT="${PLUGIN_ROOT}/scripts/insights-client.sh"
MODE="${INSIGHTS_STATUSLINE_MODE:-full}"

stdin_json="$(cat || true)"
cwd=$(printf '%s' "$stdin_json" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("cwd",""))
except Exception: print("")' 2>/dev/null || echo "")

basename_cwd=$(basename "${cwd:-$PWD}")

stats_json=$(bash "$CLIENT" stats "${cwd:-$PWD}" 2>/dev/null || echo '{"total":0,"new":0,"session_relevant":0,"online":false}')

parsed=$(printf '%s' "$stats_json" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get("total", 0),
      d.get("new", 0),
      d.get("session_relevant", 0),
      "1" if d.get("online", True) else "0",
      d.get("last_sync_seconds_ago", -1))
')
read -r total new_cnt session_rel online last_sync <<<"$parsed"

# server presence indicator
if [[ "$online" == "1" ]]; then
  srv="⏺"
  srv_full="🛰 srv ok"
else
  srv="○"
  srv_full="🛰 offline"
fi

# NEW badge
if [[ "${new_cnt}" -gt 0 ]]; then
  new_badge="✨ ${new_cnt} NEW"
else
  new_badge="✓ all read"
fi

# session-relevant
if [[ "${session_rel}" -gt 0 ]]; then
  here="🎯 ${session_rel} here"
  here_ultra="🎯${session_rel} in ./${basename_cwd}"
else
  here="🎯 0"
  here_ultra="🎯0 in ./${basename_cwd}"
fi

# last sync
if [[ "${last_sync}" =~ ^-?[0-9]+$ ]] && [[ "${last_sync}" -ge 0 ]]; then
  last="⏱ ${last_sync}s ago"
else
  last="⏱ —"
fi

case "$MODE" in
  lite)
    printf '💡%s' "$total"
    ;;
  ultra)
    printf '╭ INSIGHTS ╮ 💡%s │ %s │ %s │ %s │ %s' \
      "$total" "$here_ultra" "$new_badge" "$srv_full" "$last"
    ;;
  full|*)
    printf '💡 %s ▸ %s ▸ %s ▸ %s' "$total" "$here" "$new_badge" "$srv"
    ;;
esac
