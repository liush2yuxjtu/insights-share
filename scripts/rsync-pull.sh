#!/bin/bash
# rsync-pull.sh — Pull latest insights index from LAN teammates
# Usage: Run on SessionStart (silent)

set -e

TEAM_DIR="${HOME}/.claude-team"
CONFIG="${TEAM_DIR}/config/teammates.json"
PEER_INDEXES="${TEAM_DIR}/cache/peer-indexes"

mkdir -p "${PEER_INDEXES}"

OK_COUNT=0
TRY_COUNT=0
PEER_TOTAL=0

if [[ ! -f "${CONFIG}" ]]; then
  STATE="NOCFG"
else
  TEAMMATES=$(cat "${CONFIG}" | jq -r '.teammates[] | @base64' 2>/dev/null || echo "")
  for entry in ${TEAMMATES}; do
    TRY_COUNT=$((TRY_COUNT + 1))
    NAME=$(echo "${entry}" | base64 -d | jq -r '.name')
    IP=$(echo "${entry}" | base64 -d | jq -r '.ip')

    PEER_INDEX="${PEER_INDEXES}/${NAME}.index.json"
    BEFORE_MTIME=$(stat -f %m "${PEER_INDEX}" 2>/dev/null || echo 0)

    USERNAME=$(echo "${entry}" | base64 -d | jq -r '.username // "m1"')
    rsync -az --timeout=30 "${USERNAME}@${IP}:\${HOME}/.claude-team/insights/index.json" "${PEER_INDEX}" 2>/dev/null || true

    if [[ -f "${PEER_INDEX}" ]]; then
      AFTER_MTIME=$(stat -f %m "${PEER_INDEX}" 2>/dev/null || echo 0)
      [ "${AFTER_MTIME}" -gt "${BEFORE_MTIME}" ] && OK_COUNT=$((OK_COUNT + 1))
      echo "[insights-share] Pulled index from ${NAME} (${IP})"
      C=$(jq '.insights | length' "${PEER_INDEX}" 2>/dev/null || echo 0)
      PEER_TOTAL=$((PEER_TOTAL + C))
    fi
  done
  if [ "${TRY_COUNT}" -eq 0 ]; then STATE="NOCFG"
  elif [ "${OK_COUNT}" -eq 0 ]; then STATE="FAIL"
  elif [ "${OK_COUNT}" -lt "${TRY_COUNT}" ]; then STATE="PART"
  else STATE="OK"; fi
fi

# --- pulse-sync + pulse-pipe flags (statusline badge) -------------------
# pulse-sync = STATE|TOTAL|PEERS|TS  (vault segment)
# pulse-pipe = UNCAT_PCT|STAGING|TS  (pipe segment)
INDEX="${TEAM_DIR}/insights/index.json"
TOTAL=$(jq '.insights | length' "${INDEX}" 2>/dev/null || echo 0)
TOTAL="${TOTAL//[^0-9]/}"; TOTAL="${TOTAL:-0}"
UNCAT=$(jq '[.insights[]|select(.topic_slug=="uncategorized")] | length' "${INDEX}" 2>/dev/null || echo 0)
UNCAT="${UNCAT//[^0-9]/}"; UNCAT="${UNCAT:-0}"
if [ "${TOTAL}" -gt 0 ]; then
  UNCAT_PCT=$(( UNCAT * 100 / TOTAL ))
else
  UNCAT_PCT=0
fi
STAGING=$(ls -1 "${TEAM_DIR}/insights/staging/" 2>/dev/null | wc -l | tr -d ' ')
STAGING="${STAGING:-0}"
NOW_TS=$(date +%s)

write_flag() {
  local FLAG="$1" VALUE="$2"
  [ -L "${FLAG}" ] && return 0
  local TMP="${FLAG}.$$.${NOW_TS}"
  printf '%s' "${VALUE}" > "${TMP}" 2>/dev/null && chmod 600 "${TMP}" 2>/dev/null && mv "${TMP}" "${FLAG}" 2>/dev/null || true
}

write_flag "${TEAM_DIR}/.pulse-sync" "${STATE}|${TOTAL}|${PEER_TOTAL}|${NOW_TS}"
write_flag "${TEAM_DIR}/.pulse-pipe" "${UNCAT_PCT}|${STAGING}|${NOW_TS}"

exit 0
