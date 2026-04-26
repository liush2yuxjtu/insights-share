#!/usr/bin/env bash
# list-insights.sh — list server insights or locally buffered offline adds.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CLIENT="${PLUGIN_ROOT}/scripts/insights-client.sh"
OUTBOX_DIR="${INSIGHTS_OUTBOX_DIR:-$HOME/.claude/insights/outbox}"

status=""
tag=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status) status="${2:-}"; shift 2 ;;
    --status=*) status="${1#--status=}"; shift ;;
    --tag) tag="${2:-}"; shift 2 ;;
    --tag=*) tag="${1#--tag=}"; shift ;;
    *) shift ;;
  esac
done

if [[ "$status" == "buffered" || "$status" == "pending" ]]; then
  OUTBOX_DIR="$OUTBOX_DIR" python3 - <<'PY'
import glob, json, os
out = []
for path in sorted(glob.glob(os.path.join(os.environ["OUTBOX_DIR"], "*.json"))):
    try:
        with open(path) as fh:
            card = json.load(fh)
    except Exception:
        continue
    if isinstance(card, dict):
        card["status"] = "buffered"
        card["pending_sync"] = True
        card["buffer_path"] = path
        out.append(card)
print(json.dumps(out, ensure_ascii=False))
PY
  exit 0
fi

cards=$(bash "$CLIENT" list)
if [[ -z "$tag" ]]; then
  printf '%s\n' "$cards"
  exit 0
fi

TAG="$tag" CARDS="$cards" python3 - <<'PY'
import json, os, sys
tag = os.environ["TAG"].lower()
try:
    cards = json.loads(os.environ["CARDS"])
except Exception:
    cards = []
out = []
for c in cards if isinstance(cards, list) else []:
    if not isinstance(c, dict):
        continue
    tags = [str(t).lower() for t in c.get("tags", []) or []]
    if tag in tags:
        out.append(c)
print(json.dumps(out, ensure_ascii=False))
PY
