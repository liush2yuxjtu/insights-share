#!/usr/bin/env bash
# rate-lesson.sh — backing script for the /insight-rate skill.
#
# Per design doc:
#   /insight-rate <lesson-id> <good|bad|irrelevant>  [reason]
#   Writes to ratings.jsonl per repo. Inline thumb prompt suppressed in v1.
#
# Args:
#   $1  lesson_id     (required, e.g. lesson-1714044020-abc12345)
#   $2  verdict       (required: good|bad|irrelevant)
#   $@  reason        (optional, free text)

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
INSIGHTS_ROOT="${INSIGHTS_ROOT:-$HOME/.gstack/insights}"

lesson_id="${1:-}"
verdict="${2:-}"
shift 2 || true
reason="${*:-}"

case "$verdict" in
  good|bad|irrelevant) ;;
  *) echo "ERROR: verdict must be one of good|bad|irrelevant (got '$verdict')" >&2; exit 2 ;;
esac
[[ -z "$lesson_id" ]] && { echo "ERROR: lesson_id required" >&2; exit 2; }

slug=$(bash "${PLUGIN_ROOT}/scripts/canonical-remote.sh" --slug 2>/dev/null || echo "no-remote")
ratings_file="${INSIGHTS_ROOT}/${slug}/ratings.jsonl"
mkdir -p "$(dirname "$ratings_file")"

LESSON_ID="$lesson_id" \
VERDICT="$verdict" \
REASON="$reason" \
SLUG="$slug" \
USER="${USER:-unknown}" \
python3 -c '
import json, os, time
rec = {
    "lesson_id": os.environ["LESSON_ID"],
    "verdict":   os.environ["VERDICT"],
    "reason":    os.environ["REASON"],
    "rated_by":  os.environ["USER"],
    "rated_at":  int(time.time()),
    "repo_slug": os.environ["SLUG"],
}
print(json.dumps(rec))
' >> "$ratings_file"

# Background sync (best-effort).
nohup bash "${PLUGIN_ROOT}/scripts/sync-mirror.sh" push "$slug" >/dev/null 2>&1 &
disown 2>/dev/null || true

printf '{"lesson_id":"%s","verdict":"%s","slug":"%s"}\n' "$lesson_id" "$verdict" "$slug"
