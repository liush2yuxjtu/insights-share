#!/bin/bash
# rsync-push.sh — Push local insights to LAN teammates
# Usage: Triggered after upload or digest

set -e

TEAM_DIR="${HOME}/.claude-team"
CONFIG="${TEAM_DIR}/config/teammates.json"

if [[ ! -f "${CONFIG}" ]]; then
  exit 0
fi

TEAMMATES=$(cat "${CONFIG}" | jq -r '.teammates[] | @base64' 2>/dev/null || echo "")

for entry in ${TEAMMATES}; do
  NAME=$(echo "${entry}" | base64 -d | jq -r '.name')
  IP=$(echo "${entry}" | base64 -d | jq -r '.ip')

  USERNAME=$(echo "${entry}" | base64 -d | jq -r '.username // "m1"')
  rsync -az --timeout=30 "${HOME}/.claude-team/insights/" "${USERNAME}@${IP}:\${HOME}/.claude-team/insights/" 2>/dev/null || true

  echo "[insights-share] Pushed insights to ${NAME} (${IP})"
done

exit 0
