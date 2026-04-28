#!/bin/bash
# generate-index.sh — Add new insight to local index
# Usage: upload-insight skill calls this after capturing raw content

set -e

TEAM_DIR="${HOME}/.claude-team"
INDEX="${TEAM_DIR}/insights/index.json"
RAW_DIR="${TEAM_DIR}/insights/raw"

mkdir -p "${TEAM_DIR}/insights" "${RAW_DIR}"

NEW_ENTRY="$1"

if [[ -z "${NEW_ENTRY}" ]]; then
  echo "Usage: generate-index.sh '<json-entry>'"
  exit 1
fi

if [[ ! -f "${INDEX}" ]]; then
  echo "[]" > "${INDEX}"
fi

TEMP=$(mktemp)
jq --argjson entry "${NEW_ENTRY}" '. += [$entry]' "${INDEX}" > "${TEMP}" && mv "${TEMP}" "${INDEX}"

echo "[insights-share] Index updated"

# --- pulse-pipe flag (statusline badge, pipe segment) -------------------
# Tolerates both legacy flat-array and {insights:[...]} index shapes.
TOTAL=$(jq 'if type=="array" then length else (.insights | length) end' "${INDEX}" 2>/dev/null || echo 0)
TOTAL="${TOTAL//[^0-9]/}"; TOTAL="${TOTAL:-0}"
UNCAT=$(jq '[ if type=="array" then .[] else .insights[] end | select(.topic_slug=="uncategorized") ] | length' "${INDEX}" 2>/dev/null || echo 0)
UNCAT="${UNCAT//[^0-9]/}"; UNCAT="${UNCAT:-0}"
if [ "${TOTAL}" -gt 0 ]; then
  UNCAT_PCT=$(( UNCAT * 100 / TOTAL ))
else
  UNCAT_PCT=0
fi
STAGING=$(ls -1 "${TEAM_DIR}/insights/staging/" 2>/dev/null | wc -l | tr -d ' ')
STAGING="${STAGING:-0}"
NOW_TS=$(date +%s)
FLAG="${TEAM_DIR}/.pulse-pipe"
[ -L "${FLAG}" ] || {
  TMP="${FLAG}.$$.${NOW_TS}"
  printf '%s|%s|%s' "${UNCAT_PCT}" "${STAGING}" "${NOW_TS}" > "${TMP}" && chmod 600 "${TMP}" && mv "${TMP}" "${FLAG}"
} 2>/dev/null || true
