#!/bin/bash
# query-insights.sh — Query relevant insights based on user prompt
# Usage: Called on UserPromptSubmit hook

set -e

TEAM_DIR="${HOME}/.claude-team"
INDEX="${TEAM_DIR}/insights/index.json"
CACHE="${TEAM_DIR}/cache/query_cache.json"
PROMPT="${1:-}"

if [[ -z "${PROMPT}" ]]; then
  exit 0
fi

mkdir -p "${TEAM_DIR}/cache"

CACHED=$(cat "${CACHE}" 2>/dev/null | jq -r --arg p "${PROMPT}" '.[] | select(.prompt == $p) | .result' 2>/dev/null || echo "")

if [[ -n "${CACHED}" ]]; then
  echo "${CACHED}"
  exit 0
fi

if [[ ! -f "${INDEX}" ]]; then
  exit 0
fi

RESULTS=$(jq --arg p "${PROMPT}" -r '.insights[] | select([.name, .description, .when_to_use] | any(test($p; "i"))) | "### \(.name)\n**When:** \(.when_to_use)\n**Uploader:** \(.uploader) @ \(.uploader_ip)\n**Description:** \(.description)\n---"' "${INDEX}" 2>/dev/null || echo "")

if [[ -n "${RESULTS}" ]]; then
  ENTRY="**📚 Relevant Insights:**\n\n${RESULTS}"

  TEMP=$(mktemp)
  if [[ -f "${CACHE}" ]]; then
    jq --arg p "${PROMPT}" --arg r "${ENTRY}" '. += [{prompt: $p, result: $r}]' "${CACHE}" > "${TEMP}" && mv "${TEMP}" "${CACHE}"
  else
    echo "[{\"prompt\":\"${PROMPT}\",\"result\":\"${ENTRY}\"}]" > "${CACHE}"
  fi

  echo "${ENTRY}"
fi

# --- pulse-hit flag (statusline badge) -----------------------------------
# Count this turn's matches and atomically write 1-3 chars to the flag.
# Symlink-safe (refuses if target is a symlink), 0600 perms, temp+rename.
HIT=$(jq --arg p "${PROMPT}" '[.insights[] | select([.name,.description,.when_to_use] | any(test($p; "i")))] | length' "${INDEX}" 2>/dev/null || echo 0)
HIT="${HIT//[^0-9]/}"; HIT="${HIT:-0}"; [ "${#HIT}" -gt 3 ] && HIT=999
FLAG="${TEAM_DIR}/.pulse-hit"
[ -L "${FLAG}" ] || {
  TMP="${FLAG}.$$.$(date +%s)"
  printf '%s' "${HIT}" > "${TMP}" && chmod 600 "${TMP}" && mv "${TMP}" "${FLAG}"
} 2>/dev/null || true

exit 0
