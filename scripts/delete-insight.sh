#!/usr/bin/env bash
# delete-insight.sh — delete one insight card by id.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CLIENT="${PLUGIN_ROOT}/scripts/insights-client.sh"

id=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) id="${2:-}"; shift 2 ;;
    --id=*) id="${1#--id=}"; shift ;;
    -h|--help) echo "usage: delete-insight.sh --id <insight-id>" >&2; exit 0 ;;
    *) shift ;;
  esac
done

[[ -n "$id" ]] || { echo '{"error":"id_required"}'; exit 2; }
bash "$CLIENT" delete "$id"
