#!/usr/bin/env bash
# resolve-conflict.sh — mark a detected conflict resolved and notify peers.

set -euo pipefail

STATE_DIR="${INSIGHTS_STATE_DIR:-$HOME/.claude/insights}"
CONFLICTS_PATH="${INSIGHTS_CONFLICTS_PATH:-$STATE_DIR/conflicts.jsonl}"
NOTIFICATIONS_PATH="${INSIGHTS_NOTIFICATIONS_PATH:-$STATE_DIR/notifications.jsonl}"
AUDIT_PATH="${INSIGHTS_AUDIT_PATH:-$STATE_DIR/audit.jsonl}"

id=""
pick=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --conflict-id|--id) id="${2:-}"; shift 2 ;;
    --conflict-id=*|--id=*) id="${1#*=}"; shift ;;
    --pick) pick="${2:-}"; shift 2 ;;
    --pick=*) pick="${1#--pick=}"; shift ;;
    *) shift ;;
  esac
done

[[ -n "$id" && -n "$pick" ]] || { echo '{"error":"conflict_id_and_pick_required"}'; exit 2; }
mkdir -p "$STATE_DIR"

result=$(CONFLICTS_PATH="$CONFLICTS_PATH" ID="$id" PICK="$pick" python3 - <<'PY'
import json, os, time
path = os.environ["CONFLICTS_PATH"]
cid = os.environ["ID"]
pick = os.environ["PICK"]
items = []
found = None
if os.path.exists(path):
    for line in open(path, errors="ignore"):
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if obj.get("conflict_id") == cid:
            obj["resolution"] = "picked:" + pick
            obj["resolved_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            found = obj
        items.append(obj)
if not found:
    print(json.dumps({"error": "not_found", "conflict_id": cid}))
    raise SystemExit(1)
with open(path, "w") as fh:
    for obj in items:
        fh.write(json.dumps(obj, ensure_ascii=False) + "\n")
print(json.dumps(found, ensure_ascii=False))
PY
)

printf '%s\n' "$result"
note=$(RESULT="$result" python3 - <<'PY'
import json, os, time
obj = json.loads(os.environ["RESULT"])
print(json.dumps({
    "type": "conflict_resolved",
    "conflict_id": obj["conflict_id"],
    "tag": obj.get("tag"),
    "resolution": obj.get("resolution"),
    "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}, ensure_ascii=False))
PY
)
printf '%s\n' "$note" >> "$NOTIFICATIONS_PATH"
printf '%s\n' "$note" >> "$AUDIT_PATH"
