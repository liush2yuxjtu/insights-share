#!/usr/bin/env bash
# conflict-insights.sh — detect tag conflicts across project sources.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CLIENT="${PLUGIN_ROOT}/scripts/insights-client.sh"
STATE_DIR="${INSIGHTS_STATE_DIR:-$HOME/.claude/insights}"
CONFLICTS_PATH="${INSIGHTS_CONFLICTS_PATH:-$STATE_DIR/conflicts.jsonl}"

tag=""
id=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) tag="${2:-}"; shift 2 ;;
    --tag=*) tag="${1#--tag=}"; shift ;;
    --id) id="${2:-}"; shift 2 ;;
    --id=*) id="${1#--id=}"; shift ;;
    *) shift ;;
  esac
done

mkdir -p "$STATE_DIR"

if [[ -n "$id" ]]; then
  CONFLICTS_PATH="$CONFLICTS_PATH" ID="$id" python3 - <<'PY'
import json, os
for line in open(os.environ["CONFLICTS_PATH"], errors="ignore") if os.path.exists(os.environ["CONFLICTS_PATH"]) else []:
    try:
        obj = json.loads(line)
    except Exception:
        continue
    if obj.get("conflict_id") == os.environ["ID"]:
        print(json.dumps(obj, ensure_ascii=False))
        raise SystemExit(0)
print(json.dumps({"error": "not_found", "conflict_id": os.environ["ID"]}))
raise SystemExit(1)
PY
  exit $?
fi

[[ -n "$tag" ]] || { echo '{"error":"tag_required"}'; exit 2; }
cards=$(bash "$CLIENT" list)
conflict=$(TAG="$tag" CARDS="$cards" python3 - <<'PY'
import hashlib, json, os, sys, time
tag = os.environ["TAG"].lower()
try:
    cards = json.loads(os.environ["CARDS"])
except Exception:
    cards = []
versions = []
projects = set()
for c in cards if isinstance(cards, list) else []:
    if not isinstance(c, dict):
        continue
    tags = [str(t).lower() for t in c.get("tags", []) or []]
    if tag not in tags:
        continue
    project = c.get("project_slug") or c.get("repo_slug") or c.get("project") or c.get("source_project") or c.get("scope") or "unknown"
    projects.add(project)
    versions.append({
        "id": c.get("id"),
        "source": f"{c.get('author','unknown')}@{project}",
        "project": project,
        "content": c.get("title") or c.get("trap") or "",
        "timestamp": c.get("created_at") or c.get("updated_at") or "",
    })
if len(versions) < 2 or len(projects) < 2:
    print(json.dumps({"conflict": False, "tag": tag, "versions": versions}, ensure_ascii=False))
    raise SystemExit(3)
seed = tag + "|" + "|".join(sorted(str(v.get("id")) for v in versions))
cid = "conf_" + hashlib.sha1(seed.encode()).hexdigest()[:12]
obj = {
    "conflict": True,
    "conflict_id": cid,
    "tag": tag,
    "versions": versions,
    "resolution": "manual",
    "resolution_hint": "compare project context and pick or merge",
    "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}
print(json.dumps(obj, ensure_ascii=False))
PY
)
printf '%s\n' "$conflict"
if echo "$conflict" | grep -q '"conflict": true'; then
  if ! grep -q "$(printf '%s' "$conflict" | python3 -c 'import json,sys; print(json.load(sys.stdin)["conflict_id"])')" "$CONFLICTS_PATH" 2>/dev/null; then
    printf '%s\n' "$conflict" >> "$CONFLICTS_PATH"
  fi
fi
