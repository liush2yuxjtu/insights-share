#!/usr/bin/env bash
# insight-log.sh — render source lineage for one insight card.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CLIENT="${PLUGIN_ROOT}/scripts/insights-client.sh"

usage() {
  cat >&2 <<'USAGE'
usage: insight-log.sh --id <insight-id> [--json]
       insight-log.sh --tag <tag> --include-conflicts [--json]
USAGE
}

id=""
tag=""
include_conflicts=0
json_out=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) id="${2:-}"; shift 2 ;;
    --id=*) id="${1#--id=}"; shift ;;
    --tag) tag="${2:-}"; shift 2 ;;
    --tag=*) tag="${1#--tag=}"; shift ;;
    --include-conflicts) include_conflicts=1; shift ;;
    --json) json_out=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

if [[ -n "$tag" && "$include_conflicts" == "1" ]]; then
  CONFLICTS_PATH="${INSIGHTS_CONFLICTS_PATH:-${INSIGHTS_STATE_DIR:-$HOME/.claude/insights}/conflicts.jsonl}" \
  AUDIT_PATH="${INSIGHTS_AUDIT_PATH:-${INSIGHTS_STATE_DIR:-$HOME/.claude/insights}/audit.jsonl}" \
  TAG="$tag" python3 - <<'PY'
import json, os
tag = os.environ["TAG"].lower()
out = {"tag": tag, "conflicts": [], "audit": []}
for key, path in (("conflicts", os.environ["CONFLICTS_PATH"]), ("audit", os.environ["AUDIT_PATH"])):
    if not os.path.exists(path):
        continue
    for line in open(path, errors="ignore"):
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if str(obj.get("tag", "")).lower() == tag:
            out[key].append(obj)
print(json.dumps(out, ensure_ascii=False))
PY
  exit 0
fi

[[ -n "$id" ]] || { usage; exit 2; }

card=$(bash "$CLIENT" get "$id")
if [[ "$json_out" == "1" ]]; then
  printf '%s\n' "$card"
  exit 0
fi

python3 -c '
import json, sys
try:
    card = json.load(sys.stdin)
except Exception:
    card = {}
def csv(value):
    if isinstance(value, list):
        return ",".join(str(x) for x in value)
    return str(value or "")
for key in ("id", "title", "scope", "status", "author", "created_at", "updated_at"):
    print(key + "=" + str(card.get(key, "")))
print("source_projects=" + csv(card.get("source_projects")))
print("promoted_from=" + csv(card.get("promoted_from")))
print("source_authors=" + csv(card.get("source_authors")))
' <<<"$card"
