#!/usr/bin/env bash
# finalize-buffer.sh — async finalize watchdog.
#
# Runs out-of-band per session. Sleeps until the buffer goes idle for the
# configured threshold (default 30min), then:
#   1. Tail-reads the transcript captured during the session.
#   2. Pipes raw text through Layer 1 (regex) → Layer 2 (haiku) PII filter.
#   3. Drops the turn if Layer 2 confidence < 0.8 OR timeout fires.
#   4. Otherwise appends a finalized record to the per-repo lessons.jsonl
#      and queues an upload to the GitHub mirror via sync-mirror.sh.
#   5. Removes the buffer file.
#
# Args: <repo_slug> <session_id> <idle_threshold_seconds>

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
INSIGHTS_ROOT="${INSIGHTS_ROOT:-$HOME/.gstack/insights}"

repo_slug="${1:-}"
session_id="${2:-}"
idle_threshold="${3:-1800}"

[[ -z "$repo_slug" || -z "$session_id" ]] && exit 0

buffer_dir="${INSIGHTS_ROOT}/${repo_slug}/.buffer"
buffer_file="${buffer_dir}/${session_id}.jsonl"
lessons_file="${INSIGHTS_ROOT}/${repo_slug}/lessons.jsonl"
watchdog_marker="${buffer_dir}/.watchdog-${session_id}.pid"

mkdir -p "$(dirname "$lessons_file")"

cleanup() {
  rm -f "$watchdog_marker" 2>/dev/null || true
}
trap cleanup EXIT

# Wait for idle: sleep in small chunks, re-check buffer mtime each round.
sleep_chunk=15
elapsed=0
max_wait=$(( idle_threshold * 4 ))
while (( elapsed < max_wait )); do
  if [[ ! -f "$buffer_file" ]]; then
    exit 0
  fi
  mtime=$(stat -f '%m' "$buffer_file" 2>/dev/null || stat -c '%Y' "$buffer_file" 2>/dev/null || echo 0)
  now=$(date +%s)
  if (( now - mtime >= idle_threshold )); then
    break
  fi
  sleep "$sleep_chunk"
  elapsed=$(( elapsed + sleep_chunk ))
done

[[ -f "$buffer_file" ]] || exit 0

# Resolve last transcript path / cwd from buffer (latest record).
transcript=$(tail -1 "$buffer_file" 2>/dev/null | python3 -c '
import json, sys
try: print(json.loads(sys.stdin.read()).get("transcript_path",""))
except Exception: print("")
' 2>/dev/null || echo "")

cwd=$(tail -1 "$buffer_file" 2>/dev/null | python3 -c '
import json, sys
try: print(json.loads(sys.stdin.read()).get("cwd",""))
except Exception: print("")
' 2>/dev/null || echo "")

if [[ -z "$transcript" || ! -f "$transcript" ]]; then
  rm -f "$buffer_file"
  exit 0
fi

# Tail last 16KB of transcript (keep cost bounded; sufficient for typical lesson).
raw_text=$(tail -c 16384 "$transcript" 2>/dev/null || true)
[[ -z "$raw_text" ]] && { rm -f "$buffer_file"; exit 0; }

# Layer 1 regex redact
redacted=$(printf '%s' "$raw_text" | bash "${PLUGIN_ROOT}/scripts/filter-pii.sh")

# Layer 2 haiku redact + topic infer (best-effort, may drop)
haiku_json=$(printf '%s' "$redacted" | bash "${PLUGIN_ROOT}/scripts/filter-haiku.sh" 2>/dev/null || echo '{"dropped":true}')
dropped=$(printf '%s' "$haiku_json" | python3 -c '
import json, sys
try: print("1" if json.loads(sys.stdin.read()).get("dropped") else "0")
except Exception: print("1")
' 2>/dev/null || echo "1")

if [[ "$dropped" == "1" ]]; then
  # Per design: drop turn from upload (turn still seen by user in own session).
  rm -f "$buffer_file"
  exit 0
fi

topic_tags=$(printf '%s' "$haiku_json" | python3 -c '
import json, sys
try: print(",".join(json.loads(sys.stdin.read()).get("topic_tags",[])[:5]))
except Exception: print("")
' 2>/dev/null || echo "")

# Apply Layer 2 redact spans on top of Layer 1 output.
final_text=$(printf '%s' "$redacted" | TXT_HAIKU="$haiku_json" python3 -c '
import json, os, sys
text = sys.stdin.read()
spans = json.loads(os.environ.get("TXT_HAIKU","{}")).get("redact_spans", [])
spans = sorted([s for s in spans if isinstance(s, dict)], key=lambda s: s.get("start",0))
out, cursor = [], 0
for s in spans:
    a, b, r = s.get("start",0), s.get("end",0), s.get("reason","custom")
    if a < cursor or a > len(text) or b > len(text) or a >= b: continue
    out.append(text[cursor:a]); out.append(f"[REDACTED:{r}]"); cursor = b
out.append(text[cursor:])
print("".join(out))
')

# Construct final lesson record.
lesson_id="lesson-$(date +%s)-${session_id:0:8}"
commit_id=$(cd "$cwd" 2>/dev/null && git rev-parse --short HEAD 2>/dev/null || echo "no-commit")

LESSON_ID="$lesson_id" \
SESSION_ID="$session_id" \
REPO_SLUG="$repo_slug" \
COMMIT_ID="$commit_id" \
TOPIC_TAGS="$topic_tags" \
TEXT="$final_text" \
python3 -c '
import json, os, time
rec = {
    "id": os.environ["LESSON_ID"],
    "session_id": os.environ["SESSION_ID"],
    "repo_slug": os.environ["REPO_SLUG"],
    "commit_id": os.environ["COMMIT_ID"],
    "captured_at": int(time.time()),
    "model_version": os.environ.get("CLAUDE_MODEL_VERSION","unknown"),
    "topic_tags": [t for t in os.environ["TOPIC_TAGS"].split(",") if t],
    "kind": "raw",
    "text": os.environ["TEXT"],
}
print(json.dumps(rec))
' >> "$lessons_file"

# Queue upload to GitHub mirror (best-effort).
nohup bash "${PLUGIN_ROOT}/scripts/sync-mirror.sh" push "$repo_slug" \
      >/dev/null 2>&1 &
disown 2>/dev/null || true

# Drop the buffer entry — finalize succeeded.
rm -f "$buffer_file"
exit 0
