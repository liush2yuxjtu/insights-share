#!/bin/bash
# digest-claudefast.sh — Ingest ~/.claude/projects/*.jsonl into the team insights index
# using `claudefast -p` (MiniMax-backed local Claude). Atomic, idempotent, and bounded.
#
# Usage:
#   digest-claudefast.sh [--days N] [--max-files N] [--dry-run]
#
# Examples:
#   digest-claudefast.sh --days 7 --max-files 10        # smoke test
#   digest-claudefast.sh --days 7                       # last week, full
#   DRY_RUN=1 digest-claudefast.sh --days 30            # plan-only
#
# Idempotency: every processed jsonl path is recorded in
# ${TEAM_DIR}/.processed-files; subsequent runs skip them.
# Index merge is atomic (write tmp, mv).

# Note: -e + pipefail is incompatible with `... | head -N` (head closes pipe → SIGPIPE → exit 141).
# We use -u for catching typos and trap+per-step error handling instead.
set -u

DAYS=7
MAX_FILES=999999
DRY_RUN=${DRY_RUN:-0}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days) DAYS="$2"; shift 2 ;;
    --max-files) MAX_FILES="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

TEAM_DIR="${HOME}/.claude-team"
PROJECTS_DIR="${HOME}/.claude/projects"
RAW_DIR="${TEAM_DIR}/insights/raw"
INDEX="${TEAM_DIR}/insights/index.json"
LOG_DIR="${TEAM_DIR}/logs"
LOG="${LOG_DIR}/digest-$(date +%Y%m%d-%H%M%S).log"
PROCESSED_LIST="${TEAM_DIR}/.processed-files"

mkdir -p "${RAW_DIR}" "${LOG_DIR}"
touch "${PROCESSED_LIST}"
[[ ! -s "${INDEX}" ]] && echo '{"insights":[]}' > "${INDEX}"

UPLOADER=$(whoami)
UPLOADER_IP=$(hostname)

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "${LOG}"; }

log "start days=${DAYS} max=${MAX_FILES} dry=${DRY_RUN} index=${INDEX}"

# Collect candidate files (portable, bash 3.2 compatible — no mapfile)
FILE_LIST=$(mktemp)
trap 'rc=$?; rm -f "${FILE_LIST}" "${INDEX}.tmp" 2>/dev/null; log "EXIT rc=${rc} line=${LINENO:-?} cmd=${BASH_COMMAND:-?}"' EXIT
# Newest first so first batch lands on freshest sessions; size>=2KB skips trivial probe files.
find "${PROJECTS_DIR}" -name "*.jsonl" -type f -mtime "-${DAYS}" -size +2k 2>/dev/null \
  | xargs -I{} stat -f '%m %N' {} 2>/dev/null \
  | sort -rn | awk '{$1=""; sub(/^ /,""); print}' > "${FILE_LIST}"
TOTAL=$(wc -l < "${FILE_LIST}" | tr -d ' ')
log "candidates: ${TOTAL} files in last ${DAYS} days"

PROCESSED=0
SKIPPED=0
NEW_INSIGHTS=0
ERRORS=0

while IFS= read -r jsonl; do
  [[ -z "${jsonl}" ]] && continue
  [[ ${PROCESSED} -ge ${MAX_FILES} ]] && { log "max-files reached"; break; }

  # idempotent skip
  if grep -qxF "${jsonl}" "${PROCESSED_LIST}"; then
    SKIPPED=$((SKIPPED+1))
    continue
  fi

  PROCESSED=$((PROCESSED+1))
  log "[${PROCESSED}/${TOTAL}] ${jsonl##*/}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    continue
  fi

  # Extract only meaningful conversation turns (user + assistant text), skip raw tool noise.
  CONTENT=$(jq -r '
      select(.type=="user" or .type=="assistant")
      | . as $row
      | ($row.message.content // $row.content // null)
      | if . == null then empty
        elif type=="array" then
          map(select(.type=="text") | .text) | join("\n")
        else . end
      | select(. != null and . != "")
      | "[" + ($row.type) + "] " + .
    ' "${jsonl}" 2>/dev/null \
      | head -c 18000)
  # Fallback: if jq path missed everything, take literal head of file.
  if [[ -z "${CONTENT}" ]]; then
    CONTENT=$(head -300 "${jsonl}" 2>/dev/null | head -c 18000)
  fi
  if [[ -z "${CONTENT}" ]]; then
    log "  empty, skipping"
    echo "${jsonl}" >> "${PROCESSED_LIST}"
    continue
  fi

  RAW_HASH=$(printf '%s' "${CONTENT}" | shasum -a 256 | awk '{print $1}')
  RAW_PATH="${RAW_DIR}/${RAW_HASH}.json"
  if [[ ! -f "${RAW_PATH}" ]]; then
    jq -n --arg c "${CONTENT}" --arg u "${UPLOADER}" --arg ip "${UPLOADER_IP}" \
          --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg src "${jsonl}" \
       '{original_message:$c, uploader:$u, uploader_ip:$ip, source:$src, created_at:$t}' \
       > "${RAW_PATH}"
  fi

  PROMPT="You are a Claude Code knowledge extractor. From this session log, extract 0-3 actionable insights or traps that another engineer would benefit from. Return ONLY a valid JSON array (no markdown, no prose, no explanation) where each item is {\"name\":string<=80, \"when_to_use\":string<=100, \"description\":string<=200}. If nothing notable, return []. Session log:
${CONTENT}"

  RESPONSE=$(timeout 180 zsh -i -c "claudefast -p $(printf '%q' "${PROMPT}")" 2>>"${LOG}" || echo "")

  # Strip code fences and noise; extract first JSON array.
  CLEAN=$(printf '%s' "${RESPONSE}" \
            | sed -e 's/^```json//' -e 's/^```//' -e 's/```$//' \
            | tr -d '\r' \
            | awk '/^\[/{flag=1} flag{print} /\]$/{flag=0}' \
            | head -200)

  if ! ARRAY=$(printf '%s' "${CLEAN}" | jq -c '.' 2>/dev/null); then
    log "  unparseable response (${#RESPONSE} chars), skipping"
    ERRORS=$((ERRORS+1))
    echo "${jsonl}" >> "${PROCESSED_LIST}"
    continue
  fi

  COUNT=$(printf '%s' "${ARRAY}" | jq 'length' 2>/dev/null || echo 0)
  if [[ "${COUNT}" == "0" ]]; then
    log "  no insights"
    echo "${jsonl}" >> "${PROCESSED_LIST}"
    continue
  fi

  ADDED=0
  for i in $(seq 0 $((COUNT-1))); do
    NAME=$(printf '%s' "${ARRAY}" | jq -r ".[$i].name // empty")
    WHEN=$(printf '%s' "${ARRAY}" | jq -r ".[$i].when_to_use // empty")
    DESC=$(printf '%s' "${ARRAY}" | jq -r ".[$i].description // empty")
    [[ -z "${NAME}" || -z "${DESC}" ]] && continue

    CONTENT_HASH=$(printf '%s|%s|%s' "${NAME}" "${WHEN}" "${DESC}" | shasum -a 256 | awk '{print $1}')
    if jq -e --arg h "${CONTENT_HASH}" '.insights | any(.content_hash == $h)' "${INDEX}" >/dev/null 2>&1; then
      continue
    fi

    jq --arg n "${NAME}" --arg u "${UPLOADER}" --arg ip "${UPLOADER_IP}" \
       --arg w "${WHEN}" --arg d "${DESC}" --arg ch "${CONTENT_HASH}" \
       --arg rh "${RAW_HASH}" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.insights += [{
          name:$n, uploader:$u, uploader_ip:$ip,
          when_to_use:$w, description:$d,
          content_hash:$ch, raw_hashes:[$rh], created_at:$t
        }]' \
       "${INDEX}" > "${INDEX}.tmp" && mv "${INDEX}.tmp" "${INDEX}"
    ADDED=$((ADDED+1))
    NEW_INSIGHTS=$((NEW_INSIGHTS+1))
  done

  log "  ${ADDED} new (of ${COUNT} extracted)"
  echo "${jsonl}" >> "${PROCESSED_LIST}"
done < "${FILE_LIST}"

log "done processed=${PROCESSED} new_insights=${NEW_INSIGHTS} skipped=${SKIPPED} errors=${ERRORS} log=${LOG}"
