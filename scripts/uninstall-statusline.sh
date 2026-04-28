#!/bin/bash
# uninstall-statusline.sh — reverse install-statusline.sh.
# Strips the marked pulse invocation from settings.json. If nothing else is
# left in statusLine.command, removes the statusLine field entirely so Claude
# Code falls back to default.
set -e

ALLOW_PROD=0
for arg in "$@"; do
  case "${arg}" in
    --allow-production) ALLOW_PROD=1 ;;
    *) echo "unknown flag: ${arg}" >&2; exit 2 ;;
  esac
done

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: node required." >&2
  exit 1
fi

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
SETTINGS="${CLAUDE_DIR}/settings.json"
MARKER="# insights-share-pulse"

# Same sandbox detection as install-statusline.sh
SANDBOX=0
REAL_USER_HOME="$(eval echo "~$(id -un)")"
if [ -f "${HOME}/.sandbox-marker" ]; then SANDBOX=1
elif [[ "${CLAUDE_DIR}" == /tmp/* ]] || [[ "${CLAUDE_DIR}" == /var/folders/* ]]; then SANDBOX=1
elif [[ "${HOME}" == /tmp/* ]] || [[ "${HOME}" == /var/folders/* ]]; then SANDBOX=1
elif [ -n "${CLAUDE_CONFIG_DIR:-}" ] && [ "${CLAUDE_CONFIG_DIR}" != "${REAL_USER_HOME}/.claude" ]; then SANDBOX=1
fi
C_RED=$'\033[1;31m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'; C_RESET=$'\033[0m'

if [ "${SANDBOX}" -eq 1 ]; then
  printf '%s🦆 [SANDBOX]%s  uninstalling from %s\n' "${C_GREEN}" "${C_RESET}" "${SETTINGS}"
else
  printf '%s🚨 [PRODUCTION]%s  uninstalling from real %s\n' "${C_RED}" "${C_RESET}" "${SETTINGS}"
  if [ "${ALLOW_PROD}" -ne 1 ]; then
    printf '%s   refusing to touch production without --allow-production%s\n' "${C_YELLOW}" "${C_RESET}"
    exit 3
  fi
fi

if [ ! -f "${SETTINGS}" ]; then
  echo "[insights-share] no settings.json at ${SETTINGS}; nothing to do."
  exit 0
fi

cp "${SETTINGS}" "${SETTINGS}.bak"

SETTINGS_PATH="${SETTINGS}" MARKER="${MARKER}" node <<'EOF'
const fs = require('fs');
const settingsPath = process.env.SETTINGS_PATH;
const marker = process.env.MARKER;
const s = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
const e = s.statusLine;
if (!e) { console.log(JSON.stringify({status:'noop'})); process.exit(0); }
let cmd = (typeof e === 'string') ? e : (e.command || '');
const stripped = cmd.replace(new RegExp(`\\s*;?\\s*bash\\s+["']?[^"']*statusline-pulse\\.sh["']?\\s+${marker}\\s*`, 'g'), '').replace(/^\s*;\s*/, '').replace(/\s*;\s*$/, '').trim();
if (stripped === '') { delete s.statusLine; }
else { s.statusLine = { type: 'command', command: stripped }; }
fs.writeFileSync(settingsPath, JSON.stringify(s, null, 2) + '\n');
console.log(JSON.stringify({status:'unwired', command: stripped || null}));
EOF

echo "[insights-share] statusLine unwired. Backup: ${SETTINGS}.bak"
