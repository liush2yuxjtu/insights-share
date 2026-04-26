#!/usr/bin/env bash
# notifications.sh — list local insight notifications.

set -euo pipefail

STATE_DIR="${INSIGHTS_STATE_DIR:-$HOME/.claude/insights}"
NOTIFICATIONS_PATH="${INSIGHTS_NOTIFICATIONS_PATH:-$STATE_DIR/notifications.jsonl}"

python3 - <<'PY' "$NOTIFICATIONS_PATH"
import json, os, sys
path = sys.argv[1]
out = []
if os.path.exists(path):
    for line in open(path, errors="ignore"):
        try:
            obj = json.loads(line)
        except Exception:
            continue
        out.append(obj)
print(json.dumps(out, ensure_ascii=False))
PY
