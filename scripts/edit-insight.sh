#!/usr/bin/env bash
# edit-insight.sh — partial-field edit wrapper for one insight card.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CLIENT="${PLUGIN_ROOT}/scripts/insights-client.sh"

usage() {
  cat >&2 <<'USAGE'
usage: edit-insight.sh --id <insight-id> --field <field> --value <value> [--actor <author>]

Values that parse as JSON are sent as JSON values, e.g.
  --value '["archived","kernel-fix"]'
Otherwise the value is sent as a string.
USAGE
}

id=""
field=""
value=""
actor=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) id="${2:-}"; shift 2 ;;
    --id=*) id="${1#--id=}"; shift ;;
    --field) field="${2:-}"; shift 2 ;;
    --field=*) field="${1#--field=}"; shift ;;
    --value) value="${2:-}"; shift 2 ;;
    --value=*) value="${1#--value=}"; shift ;;
    --actor) actor="${2:-}"; shift 2 ;;
    --actor=*) actor="${1#--actor=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ -n "$id" && -n "$field" ]] || { usage; exit 2; }
case "$field" in
  id|created_at|author) echo '{"error":"immutable_field"}'; exit 2 ;;
esac

if [[ -n "$actor" ]]; then
  current=$(bash "$CLIENT" get "$id")
  allowed=$(INSIGHTS_CARD="$current" INSIGHTS_ACTOR="$actor" python3 - <<'PY'
import json
import os

card = json.loads(os.environ["INSIGHTS_CARD"])
actor = os.environ["INSIGHTS_ACTOR"]
print("yes" if str(card.get("author", "")) == actor else "no")
PY
)
  if [[ "$allowed" != "yes" ]]; then
    printf '{"error":"forbidden","actor":"%s","id":"%s"}\n' "$actor" "$id"
    exit 13
  fi
fi

patch=$(mktemp)
trap 'rm -f "$patch"' EXIT
INSIGHTS_FIELD="$field" INSIGHTS_VALUE="$value" python3 - <<'PY' > "$patch"
import json
import os
import re
import sys

field = os.environ.get("INSIGHTS_FIELD", "")
raw = os.environ.get("INSIGHTS_VALUE", "")
if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", field):
    print('{"error":"bad_field"}')
    sys.exit(2)
try:
    value = json.loads(raw)
except Exception:
    value = raw
print(json.dumps({field: value}, ensure_ascii=False))
PY

bash "$CLIENT" update "$id" "$patch"
