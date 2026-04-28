#!/bin/bash
# statusline-pulse.sh — three-segment ANSI badge for insights-share
#
# Renders [is HIT │ VAULT │ PIPE] from three flag files written by:
#   - query-insights.sh  → ~/.claude-team/.pulse-hit
#   - rsync-pull.sh      → ~/.claude-team/.pulse-sync
#   - generate-index.sh  → ~/.claude-team/.pulse-pipe (also written by rsync-pull)
#
# Hardened like caveman-statusline.sh: refuses symlinks, caps reads at 64
# bytes, validates content with whitelist regex. Any anomaly → empty stdout
# (we never echo attacker bytes into the user's terminal).
#
# Usage in ~/.claude/settings.json:
#   "statusLine": { "type": "command",
#                   "command": "bash /existing-line.sh; bash <plugin>/scripts/statusline-pulse.sh" }

set -u

TEAM_DIR="${HOME}/.claude-team"
HIT_FLAG="${TEAM_DIR}/.pulse-hit"
SYNC_FLAG="${TEAM_DIR}/.pulse-sync"
PIPE_FLAG="${TEAM_DIR}/.pulse-pipe"

# ANSI palette (256-color). Match caveman's orange-leaning aesthetic but split
# severity so the eye picks up red at a glance.
C_RESET=$'\033[0m'
C_GREEN=$'\033[38;5;71m'    # calm sage
C_YELLOW=$'\033[38;5;179m'  # warning amber
C_RED=$'\033[38;5;167m'     # alert coral
C_DIM=$'\033[38;5;244m'     # dormant grey

# Read a flag safely. Returns empty string on any anomaly.
read_flag() {
  local path="$1" max="${2:-64}"
  [ -L "${path}" ] && return 0
  [ ! -f "${path}" ] && return 0
  local raw
  raw=$(head -c "${max}" "${path}" 2>/dev/null | tr -d '\n\r')
  printf '%s' "${raw}"
}

# Parse hit (single integer, 0-999)
HIT_RAW=$(read_flag "${HIT_FLAG}" 8)
HIT_RAW="${HIT_RAW//[^0-9]/}"
HIT="${HIT_RAW:-0}"
[ "${#HIT}" -gt 3 ] && HIT=999

# Parse sync (STATE|TOTAL|PEERS|TS)
SYNC_RAW=$(read_flag "${SYNC_FLAG}" 64)
S_STATE=""; S_TOTAL=0; S_PEERS=0; S_TS=0
if [[ "${SYNC_RAW}" =~ ^(OK|FAIL|PART|NOCFG)\|([0-9]{1,6})\|([0-9]{1,6})\|([0-9]{1,11})$ ]]; then
  S_STATE="${BASH_REMATCH[1]}"
  S_TOTAL="${BASH_REMATCH[2]}"
  S_PEERS="${BASH_REMATCH[3]}"
  S_TS="${BASH_REMATCH[4]}"
fi

# Parse pipe (UNCAT_PCT|STAGING|TS)
PIPE_RAW=$(read_flag "${PIPE_FLAG}" 32)
P_UNCAT=0; P_STAGING=0; P_TS=0
if [[ "${PIPE_RAW}" =~ ^([0-9]{1,3})\|([0-9]{1,5})\|([0-9]{1,11})$ ]]; then
  P_UNCAT="${BASH_REMATCH[1]}"
  [ "${P_UNCAT}" -gt 100 ] && P_UNCAT=100
  P_STAGING="${BASH_REMATCH[2]}"
  P_TS="${BASH_REMATCH[3]}"
fi

# All three flags missing/invalid → minimal grey badge so user knows plugin loaded
if [ -z "${SYNC_RAW}${PIPE_RAW}" ] && [ "${HIT}" = "0" ]; then
  printf '%s[is]%s' "${C_DIM}" "${C_RESET}"
  exit 0
fi

# --- HIT segment ------------------------------------------------------------
HIT_COLOR="${C_DIM}"
HIT_SUFFIX=""
if [ "${HIT}" -ge 5 ]; then
  HIT_COLOR="${C_RED}"; HIT_SUFFIX="☠"
elif [ "${HIT}" -ge 1 ]; then
  HIT_COLOR="${C_YELLOW}"; HIT_SUFFIX="⚠"
fi

# --- VAULT segment ----------------------------------------------------------
NOW=$(date +%s)
SINCE=$(( NOW - S_TS ))
[ "${S_TS}" -eq 0 ] && SINCE=999999

# Friendly relative time
fmt_since() {
  local s="$1"
  if [ "${s}" -lt 60 ]; then printf '%ds' "${s}"
  elif [ "${s}" -lt 3600 ]; then printf '%dm' "$(( s / 60 ))"
  elif [ "${s}" -lt 86400 ]; then printf '%dh' "$(( s / 3600 ))"
  else printf '%dd' "$(( s / 86400 ))"; fi
}

VAULT_COLOR="${C_GREEN}"
VAULT_BODY="${S_TOTAL}✓"
case "${S_STATE}" in
  OK)
    VAULT_BODY="${S_TOTAL}✓$(fmt_since "${SINCE}")"
    if [ "${SINCE}" -gt 3600 ]; then
      VAULT_COLOR="${C_RED}"
    elif [ "${SINCE}" -gt 600 ] || [ "${S_PEERS}" -lt 3 ]; then
      VAULT_COLOR="${C_YELLOW}"
    fi
    ;;
  PART)
    VAULT_COLOR="${C_YELLOW}"
    VAULT_BODY="${S_TOTAL}~$(fmt_since "${SINCE}")"
    ;;
  FAIL)
    VAULT_COLOR="${C_RED}"
    VAULT_BODY="✗sync $(fmt_since "${SINCE}")"
    ;;
  NOCFG|"")
    VAULT_COLOR="${C_DIM}"
    VAULT_BODY="${S_TOTAL}·"
    ;;
esac
# Single-peer / lopsided sharing → degrade
if [ "${S_PEERS}" -lt 3 ] && [ "${S_TOTAL}" -gt 50 ] && [ "${VAULT_COLOR}" = "${C_GREEN}" ]; then
  VAULT_COLOR="${C_YELLOW}"
  VAULT_BODY="${S_TOTAL}/${S_PEERS}⚠"
fi

# --- PIPE segment -----------------------------------------------------------
PIPE_COLOR="${C_GREEN}"
if [ -z "${PIPE_RAW}" ]; then
  PIPE_COLOR="${C_DIM}"; PIPE_BODY="·"
elif [ "${P_UNCAT}" -gt 60 ] || [ "${P_STAGING}" -gt 20 ]; then
  PIPE_COLOR="${C_RED}"
  if [ "${P_UNCAT}" -gt 60 ]; then PIPE_BODY="${P_UNCAT}%☠"; else PIPE_BODY="${P_STAGING}stg☠"; fi
elif [ "${P_UNCAT}" -gt 30 ] || [ "${P_STAGING}" -gt 5 ]; then
  PIPE_COLOR="${C_YELLOW}"
  if [ "${P_STAGING}" -gt 5 ]; then PIPE_BODY="${P_STAGING}stg⚠"; else PIPE_BODY="${P_UNCAT}%cat"; fi
else
  PIPE_BODY="${P_UNCAT}%cat"
fi

# --- Final assembly ---------------------------------------------------------
# Frame priority: red > yellow > green > dim. Dim only wins when every segment
# is dim (i.e. flags missing); a dim "0 hits" must NOT drag a green frame down.
FRAME_COLOR="${C_DIM}"
HAS_RED=0; HAS_YELLOW=0; HAS_GREEN=0
for c in "${HIT_COLOR}" "${VAULT_COLOR}" "${PIPE_COLOR}"; do
  case "${c}" in
    "${C_RED}")    HAS_RED=1;;
    "${C_YELLOW}") HAS_YELLOW=1;;
    "${C_GREEN}")  HAS_GREEN=1;;
  esac
done
if   [ "${HAS_RED}"    -eq 1 ]; then FRAME_COLOR="${C_RED}"
elif [ "${HAS_YELLOW}" -eq 1 ]; then FRAME_COLOR="${C_YELLOW}"
elif [ "${HAS_GREEN}"  -eq 1 ]; then FRAME_COLOR="${C_GREEN}"
fi

printf '%s[is %s%s%s%s%s │ %s%s%s │ %s%s%s%s]%s' \
  "${FRAME_COLOR}" \
  "${HIT_COLOR}" "${HIT}" "${HIT_SUFFIX}" "${C_RESET}" "${FRAME_COLOR}" \
  "${VAULT_COLOR}" "${VAULT_BODY}" "${FRAME_COLOR}" \
  "${PIPE_COLOR}" "${PIPE_BODY}" "${C_RESET}" "${FRAME_COLOR}" \
  "${C_RESET}"
