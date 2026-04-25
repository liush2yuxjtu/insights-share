#!/usr/bin/env bash
# cold-start.sh — first-prompt lazy mirror discovery.
#
# Per design doc:
#   First UserPromptSubmit hook in the repo lazy-detects missing mirror clone
#   at ~/.gstack/insights/<repo-slug>/.mirror/. If missing → background-clone
#   with up to 5s wait. If mirror does not exist on remote → log warning +
#   disable retrieval until manually created. Retrieval reads from local cache
#   only; no network in hot path.
#
# Usage:
#   cold-start.sh <cwd>                      # called from fetch-insights hook
#   cold-start.sh --status <repo-slug>       # JSON {clone_present, last_synced_ago_s}
#
# Output: silent on success; warning JSON on miss.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
INSIGHTS_ROOT="${INSIGHTS_ROOT:-$HOME/.gstack/insights}"
COLD_START_BUDGET_S="${INSIGHTS_COLDSTART_BUDGET_S:-5}"

mode="bootstrap"
if [[ "${1:-}" == "--status" ]]; then
  mode="status"; shift
  slug="${1:-}"
elif [[ -n "${1:-}" ]]; then
  cwd="$1"
  slug=$(bash "${PLUGIN_ROOT}/scripts/canonical-remote.sh" --slug "$cwd" 2>/dev/null || echo "")
else
  cwd="$PWD"
  slug=$(bash "${PLUGIN_ROOT}/scripts/canonical-remote.sh" --slug 2>/dev/null || echo "")
fi

[[ -z "$slug" ]] && exit 0

mirror_dir="${INSIGHTS_ROOT}/${slug}/.mirror"
sync_marker="${INSIGHTS_ROOT}/${slug}/.last-sync"

if [[ "$mode" == "status" ]]; then
  if [[ -d "$mirror_dir/.git" ]]; then
    last=$(stat -f '%m' "$sync_marker" 2>/dev/null || stat -c '%Y' "$sync_marker" 2>/dev/null || echo 0)
    now=$(date +%s)
    age=$((now - last))
    printf '{"clone":true,"last_synced_ago_s":%s,"path":"%s"}\n' "$age" "$mirror_dir"
  else
    printf '{"clone":false,"path":"%s"}\n' "$mirror_dir"
  fi
  exit 0
fi

# Bootstrap: trigger ensure in background, then poll up to budget.
if [[ ! -d "$mirror_dir/.git" ]]; then
  bash "${PLUGIN_ROOT}/scripts/sync-mirror.sh" ensure "$slug" >/dev/null 2>&1 &
  ensure_pid=$!
  elapsed=0
  while (( elapsed < COLD_START_BUDGET_S )); do
    if [[ -d "$mirror_dir/.git" ]]; then
      break
    fi
    if ! kill -0 "$ensure_pid" 2>/dev/null; then
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
fi

# Update last-sync marker (track age for retrieval staleness logic).
mkdir -p "$(dirname "$sync_marker")"
touch "$sync_marker" 2>/dev/null || true

# Schedule a background pull every 30 minutes (best-effort; idempotent).
sync_lock="${INSIGHTS_ROOT}/${slug}/.bg-sync.pid"
if [[ ! -f "$sync_lock" ]] || ! kill -0 "$(cat "$sync_lock" 2>/dev/null)" 2>/dev/null; then
  (
    while sleep 1800; do
      bash "${PLUGIN_ROOT}/scripts/sync-mirror.sh" pull "$slug" >/dev/null 2>&1 || true
      touch "$sync_marker" 2>/dev/null || true
    done
  ) &
  echo $! > "$sync_lock" 2>/dev/null || true
  disown 2>/dev/null || true
fi
exit 0
