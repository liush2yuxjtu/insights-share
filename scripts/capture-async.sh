#!/usr/bin/env bash
# capture-async.sh — silent Stop-hook capture (replaces nudge-only model).
#
# Per design doc B-locked decisions:
#   - Capture trigger = Claude Code Stop hook (per agent response, NOT per
#     tool call NOR per turn).
#   - Append response to per-session buffer at
#     ~/.gstack/insights/<repo-slug>/.buffer/$CLAUDE_SESSION_ID.jsonl.
#   - Finalize triggers: (a) `claude --resume` boundary, (b) 30min idle,
#     (c) explicit `/insight-flush`.
#   - Finalize runs ASYNC in background. Stop hook returns immediately.
#   - User never observes capture latency.
#
# Hook input (stdin, JSON): { session_id, transcript_path, ... }
# Hook stdout: empty (silent capture).
# Exit 0 always.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
INSIGHTS_ROOT="${INSIGHTS_ROOT:-$HOME/.gstack/insights}"
IDLE_THRESHOLD_S="${INSIGHTS_IDLE_THRESHOLD_S:-1800}"      # 30 min
INACTIVE_DEADLINE_S="${INSIGHTS_INACTIVE_DEADLINE_S:-1800}"
QUIET="${INSIGHTS_CAPTURE_QUIET:-1}"

input=$(cat || true)
session_id=$(printf '%s' "$input" | python3 -c '
import json, sys
try: print(json.load(sys.stdin).get("session_id",""))
except Exception: print("")
' 2>/dev/null || echo "")

transcript=$(printf '%s' "$input" | python3 -c '
import json, sys
try: print(json.load(sys.stdin).get("transcript_path",""))
except Exception: print("")
' 2>/dev/null || echo "")

cwd=$(printf '%s' "$input" | python3 -c '
import json, sys
try: print(json.load(sys.stdin).get("cwd",""))
except Exception: print("")
' 2>/dev/null || echo "")
[[ -z "$cwd" ]] && cwd="$PWD"

# Resolve repo-slug from canonical remote (needed for buffer scoping).
repo_slug=$(bash "${PLUGIN_ROOT}/scripts/canonical-remote.sh" --slug "$cwd" 2>/dev/null || echo "no-remote")

[[ -z "$session_id" ]] && session_id="anon-$$-$(date +%s)"

buffer_dir="${INSIGHTS_ROOT}/${repo_slug}/.buffer"
mkdir -p "$buffer_dir" 2>/dev/null || exit 0
buffer_file="${buffer_dir}/${session_id}.jsonl"

# Append a single capture record (one line of JSONL).
# Body intentionally small: pointers, not raw text. The finalize pass tail-reads
# the transcript later. This keeps Stop hook return time well under 50ms.
now=$(date +%s)
SESSION_ID="$session_id" \
TRANSCRIPT="$transcript" \
CWD="$cwd" \
NOW="$now" \
REPO_SLUG="$repo_slug" \
python3 -c '
import json, os
rec = {
    "ts": int(os.environ["NOW"]),
    "session_id": os.environ["SESSION_ID"],
    "transcript_path": os.environ["TRANSCRIPT"],
    "cwd": os.environ["CWD"],
    "repo_slug": os.environ["REPO_SLUG"],
    "kind": "stop-event",
}
print(json.dumps(rec))
' >> "$buffer_file" 2>/dev/null || true

# Update last-touch marker for idle detection.
touch "${buffer_dir}/.last-touch" 2>/dev/null || true

# Spawn async finalize-on-idle watchdog (one per session at most).
watchdog_marker="${buffer_dir}/.watchdog-${session_id}.pid"
if [[ ! -f "$watchdog_marker" ]] || ! kill -0 "$(cat "$watchdog_marker" 2>/dev/null)" 2>/dev/null; then
  nohup bash "${PLUGIN_ROOT}/scripts/finalize-buffer.sh" \
        "$repo_slug" "$session_id" "$IDLE_THRESHOLD_S" \
        >/dev/null 2>&1 &
  echo $! > "$watchdog_marker" 2>/dev/null || true
  disown 2>/dev/null || true
fi

exit 0
