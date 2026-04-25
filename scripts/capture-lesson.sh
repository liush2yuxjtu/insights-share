#!/usr/bin/env bash
# capture-lesson.sh — Stop hook.
# Fires when Claude finishes responding. Looks at the just-finished turn and,
# if it smells like a lesson Claude should record, prints a system-reminder
# nudging Claude to invoke /insight-add. Otherwise stays silent.
#
# Hook input (stdin, JSON): { "session_id": "...", "stop_hook_active": false, ... }
# Hook output (stdout): empty, or a system-reminder block.
# Exit 0 always (never block the user).

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CLIENT="${PLUGIN_ROOT}/scripts/insights-client.sh"
TRIGGER_LOG="${INSIGHTS_LESSON_LOG:-$HOME/.claude/insights/last-trigger.log}"

input=$(cat || true)

# Pull transcript_path if present; bail if not.
transcript=$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get("transcript_path") or "")
' 2>/dev/null || echo "")

[[ -z "$transcript" || ! -f "$transcript" ]] && exit 0

# Avoid double-firing within a 60s window per session.
mkdir -p "$(dirname "$TRIGGER_LOG")"
session_id=$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get("session_id") or "")' 2>/dev/null || echo "")
if [[ -n "$session_id" ]]; then
  now=$(date +%s)
  last=""
  if [[ -f "$TRIGGER_LOG" ]]; then
    last=$(awk -v s="$session_id" '$1==s {print $2}' "$TRIGGER_LOG" 2>/dev/null | tail -1 || true)
  fi
  if [[ -n "$last" ]] && (( now - last < 60 )); then
    exit 0
  fi
  printf '%s %s\n' "$session_id" "$now" >> "$TRIGGER_LOG"
fi

# Heuristic: scan last 4KB of transcript for trap-shaped phrases.
tail_text=$(tail -c 4096 "$transcript" 2>/dev/null || true)
[[ -z "$tail_text" ]] && exit 0

if printf '%s' "$tail_text" | grep -Eqi 'fixed (the )?bug|root cause|got burned|trap|gotcha|do not (use|do)|never (use|do)|surprised me|silently (fail|misbehav)|lesson learn|debugged for'; then
  count=0
  if stats=$("$CLIENT" stats 2>/dev/null); then
    count=$(printf '%s' "$stats" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("total",0))
except Exception: print(0)')
  fi
  cat <<EOF
<insights-share>
This session looked like it contained a non-trivial lesson. If another Claude instance on this team would benefit, invoke \`/insight-add\` to record it now (current team total: ${count}). If it was trivial, ignore this nudge.
</insights-share>
EOF
fi

exit 0
