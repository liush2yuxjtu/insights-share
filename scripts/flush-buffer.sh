#!/usr/bin/env bash
# flush-buffer.sh — backing script for the /insight-flush skill.
#
# Force-finalize all session buffers in the current repo's slug. Runs
# finalize-buffer.sh synchronously with idle_threshold=0 so the filter pipeline
# fires immediately.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
INSIGHTS_ROOT="${INSIGHTS_ROOT:-$HOME/.gstack/insights}"

slug=$(bash "${PLUGIN_ROOT}/scripts/canonical-remote.sh" --slug 2>/dev/null || echo "no-remote")
buffer_dir="${INSIGHTS_ROOT}/${slug}/.buffer"

if [[ ! -d "$buffer_dir" ]]; then
  printf '{"finalized":0,"slug":"%s","reason":"no_buffer_dir"}\n' "$slug"
  exit 0
fi

shopt -s nullglob
finalized=0
dropped=0
for f in "$buffer_dir"/*.jsonl; do
  session=$(basename "$f" .jsonl)
  before=$(wc -l < "$f" 2>/dev/null || echo 0)
  bash "${PLUGIN_ROOT}/scripts/finalize-buffer.sh" "$slug" "$session" 0 || true
  if [[ -f "$f" ]]; then
    dropped=$((dropped + 1))
  else
    finalized=$((finalized + 1))
  fi
done
shopt -u nullglob

# Trigger a synchronous push so user sees confirmation in the same turn.
push_out=$(bash "${PLUGIN_ROOT}/scripts/sync-mirror.sh" push "$slug" 2>/dev/null || echo '{"pushed":false}')

printf '{"slug":"%s","finalized":%s,"dropped":%s,"push":%s}\n' \
       "$slug" "$finalized" "$dropped" "$push_out"
