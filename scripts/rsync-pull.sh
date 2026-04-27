#!/bin/bash
# rsync-pull.sh — Pull latest insights index from LAN teammates
# Usage: Run on SessionStart (silent)

set -e

TEAM_DIR="${HOME}/.claude-team"
CONFIG="${TEAM_DIR}/config/teammates.json"
PEER_INDEXES="${TEAM_DIR}/cache/peer-indexes"

mkdir -p "${PEER_INDEXES}"

if [[ ! -f "${CONFIG}" ]]; then
  exit 0
fi

TEAMMATES=$(cat "${CONFIG}" | jq -r '.teammates[] | @base64' 2>/dev/null || echo "")

for entry in ${TEAMMATES}; do
  NAME=$(echo "${entry}" | base64 -d | jq -r '.name')
  IP=$(echo "${entry}" | base64 -d | jq -r '.ip')

  PEER_INDEX="${PEER_INDEXES}/${NAME}.index.json"

  USERNAME=$(echo "${entry}" | base64 -d | jq -r '.username // "m1"')
  rsync -az --timeout=30 "${USERNAME}@${IP}:\${HOME}/.claude-team/insights/index.json" "${PEER_INDEX}" 2>/dev/null || true

  if [[ -f "${PEER_INDEX}" ]]; then
    echo "[insights-share] Pulled index from ${NAME} (${IP})"
  fi
done

exit 0
