#!/bin/bash
# install-statusline.sh — wire insights-share badge into ~/.claude/settings.json
#
# Operates in POSTFIX mode by default: any existing statusLine command stays,
# and our badge runs after it. Idempotent — running twice is a no-op.
# Backs up settings.json to settings.json.bak before each run.
#
# Usage:
#   bash install-statusline.sh                     # postfix mode (recommended)
#   bash install-statusline.sh --solo              # replace existing statusLine entirely
#   bash install-statusline.sh --force             # rewrite even if already wired
#   bash install-statusline.sh --allow-production  # required to touch real ~/.claude
#   bash install-statusline.sh --check             # only print sandbox/production banner & exit
set -e

MODE="postfix"
FORCE=0
ALLOW_PROD=0
CHECK_ONLY=0
for arg in "$@"; do
  case "${arg}" in
    --solo)              MODE="solo" ;;
    --postfix)           MODE="postfix" ;;
    --force|-f)          FORCE=1 ;;
    --allow-production)  ALLOW_PROD=1 ;;
    --check)             CHECK_ONLY=1 ;;
    *) echo "unknown flag: ${arg}" >&2; exit 2 ;;
  esac
done

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: node is required (used to merge settings.json safely)." >&2
  exit 1
fi

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
SETTINGS="${CLAUDE_DIR}/settings.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PULSE="${SCRIPT_DIR}/statusline-pulse.sh"
MARKER="# insights-share-pulse"

# --- Sandbox vs Production self-check ---------------------------------------
# Decision rules (sandbox if ANY of these is true):
#   1. CLAUDE_CONFIG_DIR is set to something OTHER than $real_user_home/.claude
#   2. HOME has a .sandbox-marker file (set by sandbox-bootstrap.sh)
#   3. CLAUDE_DIR path starts with /tmp or /var/folders (mktemp-style)
#   4. HOME starts with /tmp or /var/folders
SANDBOX=0
SANDBOX_REASON=""
REAL_USER_HOME="${SUDO_USER:+/Users/${SUDO_USER}}"
[ -z "${REAL_USER_HOME}" ] && REAL_USER_HOME="$(eval echo "~$(id -un)")"

if [ -f "${HOME}/.sandbox-marker" ]; then
  SANDBOX=1; SANDBOX_REASON=".sandbox-marker found at ${HOME}/.sandbox-marker"
elif [[ "${CLAUDE_DIR}" == /tmp/* ]] || [[ "${CLAUDE_DIR}" == /var/folders/* ]]; then
  SANDBOX=1; SANDBOX_REASON="CLAUDE_DIR (${CLAUDE_DIR}) is in tempdir"
elif [[ "${HOME}" == /tmp/* ]] || [[ "${HOME}" == /var/folders/* ]]; then
  SANDBOX=1; SANDBOX_REASON="HOME (${HOME}) is in tempdir"
elif [ -n "${CLAUDE_CONFIG_DIR:-}" ] && [ "${CLAUDE_CONFIG_DIR}" != "${REAL_USER_HOME}/.claude" ]; then
  SANDBOX=1; SANDBOX_REASON="CLAUDE_CONFIG_DIR (${CLAUDE_CONFIG_DIR}) overrides real ~/.claude"
fi

# ANSI colour helpers
C_RED=$'\033[1;31m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'

if [ "${SANDBOX}" -eq 1 ]; then
  printf '%s🦆 [SANDBOX]%s  %s\n' "${C_GREEN}" "${C_RESET}" "${SANDBOX_REASON}"
  printf '   HOME             = %s\n' "${HOME}"
  printf '   CLAUDE_CONFIG_DIR= %s\n' "${CLAUDE_DIR}"
  printf '   target settings  = %s\n' "${SETTINGS}"
else
  printf '%s🚨 [PRODUCTION]%s  writing to your real ~/.claude\n' "${C_RED}" "${C_RESET}"
  printf '   HOME             = %s\n' "${HOME}"
  printf '   CLAUDE_CONFIG_DIR= %s\n' "${CLAUDE_DIR}"
  printf '   target settings  = %s\n' "${SETTINGS}"
  if [ "${ALLOW_PROD}" -ne 1 ]; then
    printf '%s   refusing to touch production without --allow-production%s\n' "${C_YELLOW}" "${C_RESET}"
    printf '   either rerun with --allow-production, or source scripts/sandbox-bootstrap.sh first.\n'
    exit 3
  fi
  printf '%s   --allow-production passed; proceeding.%s\n' "${C_YELLOW}" "${C_RESET}"
fi

if [ "${CHECK_ONLY}" -eq 1 ]; then
  printf '%s   --check only; not writing anything.%s\n' "${C_DIM}" "${C_RESET}"
  exit 0
fi

mkdir -p "${CLAUDE_DIR}"
[ ! -f "${SETTINGS}" ] && echo '{}' > "${SETTINGS}"
cp "${SETTINGS}" "${SETTINGS}.bak"

PULSE_PATH="${PULSE}" SETTINGS_PATH="${SETTINGS}" MODE="${MODE}" FORCE="${FORCE}" MARKER="${MARKER}" \
node <<'EOF'
const fs = require('fs');
const settingsPath = process.env.SETTINGS_PATH;
const pulsePath    = process.env.PULSE_PATH;
const mode         = process.env.MODE;
const force        = process.env.FORCE === '1';
const marker       = process.env.MARKER;

const s = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
const pulseInvocation = `bash "${pulsePath}"`;
const taggedPulse = `${pulseInvocation} ${marker}`;

const existing = s.statusLine;
let existingCmd = '';
if (typeof existing === 'string') existingCmd = existing;
else if (existing && typeof existing.command === 'string') existingCmd = existing.command;

const alreadyWired = existingCmd.includes(marker);
if (alreadyWired && !force) {
  console.log(JSON.stringify({ status: 'noop', reason: 'already wired', command: existingCmd }));
  process.exit(0);
}

let newCmd;
if (mode === 'solo' || existingCmd === '') {
  newCmd = taggedPulse;
} else {
  // strip any prior pulse insertion (force re-wire)
  const stripped = existingCmd.replace(new RegExp(`\\s*;?\\s*bash\\s+["']?[^"']*statusline-pulse\\.sh["']?\\s+${marker}\\s*`, 'g'), '').replace(/;\s*$/, '').trim();
  newCmd = `${stripped}; ${taggedPulse}`;
}

s.statusLine = { type: 'command', command: newCmd };
fs.writeFileSync(settingsPath, JSON.stringify(s, null, 2) + '\n');
console.log(JSON.stringify({ status: 'wired', mode: mode, command: newCmd }));
EOF

echo "[insights-share] statusLine wired (${MODE}). Backup: ${SETTINGS}.bak"
echo "[insights-share] Restart Claude Code to pick up the change."
