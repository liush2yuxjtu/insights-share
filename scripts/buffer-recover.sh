#!/usr/bin/env bash
# buffer-recover.sh — orphan-buffer crash recovery.
#
# Per design doc Open Question #7:
#   If Claude Code crashes mid-session, on next plugin startup scan
#   ~/.gstack/insights/<repo-slug>/.buffer/ for orphan files older than 30min
#   idle threshold and finalize them through the same pipeline.
#
# Args:
#   $1  repo_slug   optional — defaults to canonical slug from cwd
#
# Behavior:
#   For each buffer file with an mtime older than INSIGHTS_IDLE_THRESHOLD_S
#   AND no live watchdog process, run finalize-buffer.sh once with
#   idle_threshold=0.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
INSIGHTS_ROOT="${INSIGHTS_ROOT:-$HOME/.gstack/insights}"
IDLE_THRESHOLD_S="${INSIGHTS_IDLE_THRESHOLD_S:-1800}"

slug="${1:-$(bash "${PLUGIN_ROOT}/scripts/canonical-remote.sh" --slug 2>/dev/null || echo no-remote)}"
buffer_dir="${INSIGHTS_ROOT}/${slug}/.buffer"

if [[ ! -d "$buffer_dir" ]]; then
  printf '{"recovered":0,"slug":"%s","reason":"no_buffer_dir"}\n' "$slug"
  exit 0
fi

shopt -s nullglob
recovered=0
skipped=0
now=$(date +%s)
for f in "$buffer_dir"/*.jsonl; do
  session=$(basename "$f" .jsonl)
  watchdog_pid_file="${buffer_dir}/.watchdog-${session}.pid"
  # Skip if a watchdog is alive.
  if [[ -f "$watchdog_pid_file" ]]; then
    if kill -0 "$(cat "$watchdog_pid_file" 2>/dev/null)" 2>/dev/null; then
      skipped=$((skipped + 1))
      continue
    fi
    # Stale pid file — clean up.
    rm -f "$watchdog_pid_file"
  fi
  mtime=$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null || echo 0)
  if (( now - mtime < IDLE_THRESHOLD_S )); then
    skipped=$((skipped + 1))
    continue
  fi
  bash "${PLUGIN_ROOT}/scripts/finalize-buffer.sh" "$slug" "$session" 0 || true
  if [[ ! -f "$f" ]]; then
    recovered=$((recovered + 1))
  fi
done
shopt -u nullglob

printf '{"slug":"%s","recovered":%s,"skipped":%s}\n' "$slug" "$recovered" "$skipped"
